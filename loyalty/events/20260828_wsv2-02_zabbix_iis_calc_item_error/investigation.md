# GITIN-1956 — Zabbix: calculated item error on SFCG-WSV2-02 (IIS Post/Get Requests/Sec)

Jira: https://smartit-ar.atlassian.net/browse/GITIN-1956

## Status

New (2026-08-28). Reported error:

```
Cannot evaluate function: item "/SFCG-WSV2-02/perf_counter_en["\Web Service({$IIS.APP.NAME})\Post Requests/Sec", {$IIS_CURRCONN_UPDATE_INTERVAL}]" does not exist
at "last(//perf_counter_en["\Web Service({$IIS.APP.NAME})\Post Requests/Sec", {$IIS_CURRCONN_UPDATE_INTERVAL}],{$CALC_ITEM_AVG_TIME})
   +last(//perf_counter_en["\Web Service({$IIS.APP.NAME})\Get Requests/Sec", {$IIS_CURRCONN_UPDATE_INTERVAL}],{$CALC_ITEM_AVG_TIME})"
```

This is a **calculated item** (native `IIS by Zabbix agent active` template, likely "Requests/Sec"
or similar), not a custom UserParameter — it sums two `perf_counter_en` items via `last()`. The
error means one or both of those raw `perf_counter_en` items don't exist as *items* on
`SFCG-WSV2-02` at all (not "unsupported" — Zabbix distinguishes the two; this is "item does not
exist").

## Background (from GITIN-1238, same host)

Per `loyalty/events/20260826_wsv2lb_vm2_trustedlaunch_no_traffic/investigation.md` → "Zabbix
monitoring parity" section (2026-08-27): `SFCG-WSV2-02` (hostid `10678`) was cloned from
`SFCG-WSV2-01` (hostid `10665`) via the Zabbix frontend's "Clone" host feature, same day. Confirmed
at the time: identical templates (`IIS by Zabbix agent active`, `Windows by Zabbix agent active`)
and identical host macros (`{$IIS.APP.NAME}`, `{$IIS.APPPOOL.MATCHES}`, `{$IIS.PORT}=8080`,
`{$IIS.SERVICE}=https`), confirmed `zabbix_agent2.conf` `Hostname=SFCG-WSV2-02` matches, and
confirmed "real, current data flowing (`perf_counter_en` items, live `lastclock`)" — but that check
did not specifically verify the Post/Get Requests/Sec discovered items, only that *some*
`perf_counter_en` items were live.

## Leading hypothesis (not yet confirmed)

The `IIS by Zabbix agent active` template's per-counter items (`Post Requests/Sec`,
`Get Requests/Sec`, etc.) are populated via **Windows Performance Counters LLD** (low-level
discovery) — the raw `perf_counter_en[...]` items only get created on a host once discovery finds a
matching `\Web Service(<instance>)\...` counter instance. Two ways this fails on a freshly-cloned
host:

1. **LLD hasn't run yet / hasn't completed a discovery cycle** since the clone (2026-08-27) — the
   discovered item prototypes for VM2 simply don't exist yet. Least likely at this point (>24h
   since clone) unless the discovery rule's interval is unusually long or discovery itself is
   erroring.
2. **`{$IIS.APP.NAME}` (or the counter instance name it resolves against) doesn't match VM2's
   actual IIS Web Service instance name.** The macro value was cloned identically from VM1, but the
   macro is a *filter/name* used to match a discovered instance — if VM2's actual Windows
   `\Web Service(...)\` instance name differs from VM1's (e.g. different site name, or VM2 exposes
   a differently-named instance because of the already-documented VM1/VM2 deployment differences —
   see GITIN-1238 investigation, "different code/deployment versions"), discovery finds no match on
   VM2 and the per-counter items are never created there, even though the calculated item (which
   hardcodes the macro into its own key rather than depending on LLD matching) still tries to
   reference them and fails.

Both explain "item does not exist" specifically (not "unsupported") — the item was simply never
created by discovery.

## Confirmed (2026-08-28)

`{$IIS.APP.NAME}` value is **identical on both hosts** (user). This rules out "macro was cloned
wrong" but does **not** rule out the core hypothesis — the macro can be identical on both hosts and
still fail to match VM2's actual IIS Web Service instance name if VM1's and VM2's IIS site
configurations differ (already documented elsewhere as running different deployments/code). The
macro is a static string; whether it matches is host-specific, dependent on what Windows actually
exposes as the counter instance name on each host — an identical macro value doesn't imply an
identical match outcome.

## ROOT CAUSE FOUND: Web Service perf counter was not started on VM2 (2026-08-28)

User ran `Get-Counter -ListSet "Web Service"` on `SFCG-WSV2-02` — the counter set was **not
started**. This fully explains the symptom: with the counter set inactive, Windows exposes zero
`\Web Service(...)\` instances at all, so Zabbix's LLD finds nothing to discover regardless of what
`{$IIS.APP.NAME}` is set to — no macro/instance-name mismatch needed. The calculated item still
references the macro-built key directly and fails with "item does not exist" because no such item
was ever created.

**Action taken (user):** counter set started on `SFCG-WSV2-02`.

**Confirmed post-fix (2026-08-28):** `Get-Counter -ListSet "Web Service"` on `SFCG-WSV2-02` now
returns the full counter list, including `\Web Service(SmartLoyalty.WebServiceV2)\Post Requests/sec`
and `\Web Service(SmartLoyalty.WebServiceV2)\Get Requests/sec`. Instance name is
`SmartLoyalty.WebServiceV2` — matches the app/site name used elsewhere for this host (consistent
with the `{$IIS.APP.NAME}` macro, which was already confirmed identical to VM1). This is exactly the
raw counter the calculated item needs; with the counter set active, LLD has what it needs to
discover the corresponding `perf_counter_en` items on VM2.

**Progress confirmed (2026-08-28):** the calculated item's error changed from "item ... does not
exist" to:

```
Cannot evaluate function: not enough data
at "last(//perf_counter_en[...Post Requests/Sec...],{$CALC_ITEM_AVG_TIME})+last(//perf_counter_en[...Get Requests/Sec...],{$CALC_ITEM_AVG_TIME})"
```

This is a distinct, expected Zabbix error class — "does not exist" meant the item itself was
missing; "not enough data" means the raw `perf_counter_en` items now **exist** (LLD created them
after the counter set was started) but haven't accumulated enough polled history yet for `last()`
to return a value. This is transient and self-resolving — it will clear once the item has been
polled at least once (bounded by its own update interval) and, depending on `{$CALC_ITEM_AVG_TIME}`,
possibly needs a short window of history rather than a single poll.

**Still reproducing (2026-08-28, follow-up):** user reports the exact same "not enough data" error
persists. Elapsed time since the counter set was started is not yet known — if it's still within one
`{$CALC_ITEM_AVG_TIME}` window of the raw item's first successful poll, this could still be the
expected transient state. But it could equally mean the raw `perf_counter_en` items were discovered
(explaining the error-class change from "does not exist") but are **not actually polling
successfully** — a distinct, real problem (e.g. an agent-side error reading that specific counter)
masquerading as "just needs more time." Not distinguishable without checking the raw items directly.

**Disambiguated (2026-08-28): this is a real, persistent failure, not just timing.** `Monitoring →
Latest data` on `SFCG-WSV2-02` shows:

- `SmartLoyalty.WebServiceV2: IIS Method POST requests per second` (the macro-driven item the
  calculated item depends on) — **no Last check, no Last value at all.** Never successfully
  collected, not "still accumulating."
- `IIS: Method POST requests per second` (the sibling `_Total`-instance item, same host, same
  underlying "Web Service" counter set) — **collecting fine**, last check 33s ago, value `0.0165`.

Since the counter set is confirmed running (Get-Counter output earlier showed the
`SmartLoyalty.WebServiceV2` instance present with these exact counters) and the `_Total` instance on
the *same* counter set collects successfully, the counter set being off is **not** what's currently
blocking data — that was fixed. The new, distinct problem: the Zabbix agent specifically can't
resolve the **named-instance** (`SmartLoyalty.WebServiceV2`) counter path, only the `_Total`
aggregate.

**Leading theory:** `zabbix_agent2`'s Windows perf-counter (PDH) layer caches the set of known
counter instances and was already running when the "Web Service" counter set was started — a known
class of gotcha where a process that opened its PDH counter enumeration before a new instance became
available won't see it until that cache is refreshed, which for some Windows Zabbix agent
configurations only happens on agent restart. This would explain exactly this split: `_Total` (a
long-standing, always-present instance) resolves fine, while the newly-available
`SmartLoyalty.WebServiceV2` instance — which didn't exist in the agent's cached view when it was
last (re)started — doesn't.

**Needed to disambiguate:** ~~resolved, see below~~

## ROOT CAUSE, REVISED: known Zabbix Agent2 bug with Windows perf counters, not the counter-set fix (2026-08-28)

`zabbix_agent2.log` on `SFCG-WSV2-02` (pasted by user) shows the real, distinct blocker:

```
2026/08/28 04:09:43 Detected performance counter with negative denominator the second time after retry, giving up...
2026/08/28 08:29:24 / 08:32:49 / 08:32:50 / 08:34:16 / 08:34:17 / 08:36:42 / 13:09:43  (same message, repeating)
```

This explains why `Monitoring → Latest data` showed **no Last check / no Last value at all** for
`SmartLoyalty.WebServiceV2: IIS Method POST requests per second` while the sibling `_Total`-instance
item collected fine (33s ago, `0.0165`) — the agent isn't failing to *discover* the named-instance
counter, it's failing to *compute* its rate value every time it polls, then giving up on that poll
cycle entirely. Confirmed via web search: this is a known Zabbix Agent2 issue on Windows,
specifically with IIS/performance-rate counters — **ZBX-22463** (this exact log message), related to
`ZBX-21661` ("A counter with a negative value was detected"), `ZBX-22438` (Agent2 not retrieving IIS
performance counters), and `ZBX-20356` (a related OS-counters issue reportedly fixed since 6.2.7 —
this instance is 6.0.32, predates that fix). Not caused by our earlier fix (starting the "Web
Service" counter set) or by anything specific to this host's config — it's a platform-level Agent2
limitation.

**Possible trigger, not confirmed as cause:** the same log shows a brief connectivity blip to the
Zabbix proxy (`172.191.99.60:10051`) at `2026-08-27 23:20:09` (`cannot connect ... i/o timeout`,
recovered within ~1 second, `history upload ... is working again`). Community reports for this bug
describe it "sometimes starting a couple of hours or days after network errors begin" — the first
negative-denominator failure here was ~5 hours later (`04:09` on 08-28), consistent with but not
proof of that pattern.

**Standard workaround (per community reports), applied 2026-08-28:** user restarted the Zabbix Agent
2 service on `SFCG-WSV2-02` (confirmed via `$env:COMPUTERNAME` first). This is the documented
mitigation — some users have gone as far as automatic restart-on-failure at the Windows service
level for persistent recurrence.

**Confirmed (2026-08-28): restart cleared the raw-item failure.** `Monitoring → Latest data` now
shows `SmartLoyalty.WebServiceV2: IIS Method POST requests per second` with a real value (`0.01002`,
last check 1m24s ago). The negative-denominator failure is not recurring on this item since the
restart.

**New finding (2026-08-28): a second, separate problem — the `Get Requests/Sec` raw item may never
have existed on this host at all.** The calculated item's error is back, but changed class again —
now specifically for `Get Requests/Sec`, back to "item ... does not exist" (not "not enough data").
This is a different signature from the Post item's earlier journey (does-not-exist → not-enough-data
→ real value) — "does not exist" for an item that's never shown up in any Latest data/Items check
so far suggests it may simply never have been created as a Zabbix item on `SFCG-WSV2-02`, unlike
`Post Requests/Sec` which does exist (confirmed in the Items list) and now collects data.

**Consistent with:** the earlier `Data collection → Items` listing the user pulled (filtered/searched
for "Post Requests") only ever showed **Post** variants for both hosts — no `Get Requests/Sec` row
appeared for either host in that view, but that search was scoped to "Post Requests" text, so it
doesn't confirm one way or the other whether a `Get Requests/Sec` item exists at all on `01` or `02`.

**Needed to confirm:**
1. `Data collection → Hosts → SFCG-WSV2-02 → Items`, searched for "Get Requests" — does the
   macro-driven `Get Requests/Sec` item (parallel to the existing `SmartLoyalty.WebServiceV2: IIS
   Method POST requests per second`) exist at all on this host?
2. Same search on `SFCG-WSV2-01` — since that host's calculated item (`Avg Requests (POST + GET)`)
   shows "Enabled" (working), its `Get Requests/Sec` item must exist there; compare its exact
   name/key to confirm what VM2 is missing.
3. If confirmed missing on VM2: the fix is creating that item on `SFCG-WSV2-02`, mirroring VM1's
   equivalent (same key `perf_counter_en["\Web Service({$IIS.APP.NAME})\Get Requests/Sec",
   {$IIS_CURRCONN_UPDATE_INTERVAL}]`, type Zabbix agent (active), update interval
   `{$IIS:ITEM_UPDATE_INTERVAL}`, same tags as the Post item) — likely an incomplete artifact of the
   `GITIN-1238` host clone, not a new issue.

**Confirmed (2026-08-28): `Get Requests/Sec` item was genuinely missing on VM2, now created.** User
created the item on `SFCG-WSV2-02`. Confirmed on VM1 the equivalent item is named plainly `IIS Method
GET requests per second` (not prefixed `SmartLoyalty.WebServiceV2:` like the Post item — a minor,
pre-existing naming inconsistency between the two counters on VM1 itself, not something this ticket
introduced; not worth fixing as part of this ticket). VM1's Get item has a real value (`0.05017`,
3m37s old) — confirms the item type/config is sound. VM2's newly-created copy shows no Last
check/value yet — expected immediately after creation, needs at least one active-check poll cycle.

**Progress (2026-08-28):** the calculated item (`Avg Requests (POST + GET)`) is now **Enabled** on
VM2 (was "Not supported" earlier) — config-level state is healthy. Its error changed from "item ...
Get Requests/Sec ... does not exist" to "not enough data" — same expected progression the Post item
went through (does-not-exist → not-enough-data → real value) as the newly-created Get item
accumulates history within `{$CALC_ITEM_AVG_TIME}`. No sign of the negative-denominator bug on this
item so far.

**RESOLVED (2026-08-28):** `Data collection → Items` now shows `Avg Requests (POST + GET)` as
**Enabled** with a clean Info column (no error) on both `SFCG-WSV2-02` and `SFCG-WSV2-01`. The
calculated item is evaluating successfully on VM2.

**Not confirmed / worth watching, not blocking closure:**
- Whether the negative-denominator bug (the real root cause of the Post item's earlier failure,
  `ZBX-22463`) recurs later on either raw item — it's documented in community reports as
  intermittent, not necessarily a one-time event. No fix was applied for the bug itself, only the
  workaround (agent restart) plus the separately-needed missing-item creation.

## Summary — two independent problems, both resolved (2026-08-28)

1. **`Web Service` Windows performance-counter set was not started on `SFCG-WSV2-02`** — fixed by
   starting it. This alone was not sufficient (see below).
2. **Zabbix Agent2 known bug (`ZBX-22463`, "negative denominator ... giving up")** blocked the
   `Post Requests/Sec` raw item from ever collecting data after the counter set was started, even
   though Windows exposed the counter correctly. Fixed by restarting the Zabbix Agent 2 service on
   `SFCG-WSV2-02` (documented community workaround).
3. **`Get Requests/Sec` raw item had never been created on `SFCG-WSV2-02` at all** — a separate,
   pre-existing gap (likely an incomplete artifact of the `GITIN-1238` Zabbix host clone from VM1),
   unrelated to the other two problems. Fixed by creating the item on VM2, mirroring VM1's
   configuration.

All three needed fixing before the calculated item (`Avg Requests (POST + GET)`) could evaluate
successfully — each one individually would have left the item broken. Confirmed working on both
hosts as of this entry.

**Not yet confirmed:**
- Why the counter set was stopped on VM2 in the first place (default state on a fresh
  clone/reimage? explicitly disabled at some point? — VM2's `D:\` is a temp disk and the VM has been
  stopped/started repeatedly this week per `GITIN-1238`, so this may simply be a fresh-boot default
  that was never true on VM1, which has stayed running longer). Worth checking whether it needs to
  be re-enabled on every VM2 boot, or whether Windows persists "started" state across restarts —
  relevant given VM2's documented power cycling.
- Whether Zabbix's LLD has re-run since the counter was started and the `perf_counter_en` items for
  Post/Get Requests/Sec now actually exist as Zabbix items on VM2, and whether the calculated item's
  error has cleared in the frontend.

## Needed to confirm

1. Value of `{$IIS.APP.NAME}` on `SFCG-WSV2-02` (Data collection → Hosts → SFCG-WSV2-02 → Macros) —
   compare against `SFCG-WSV2-01`'s value (expected identical per the clone) and against the actual
   IIS site name in use on VM2.
2. `Data collection → Hosts → SFCG-WSV2-02 → Items`, filtered to key `perf_counter_en` — do any
   `\Web Service(...)\...` items exist at all for VM2? If yes, what instance name do they show
   (compare literal key text to VM1's equivalents)?
3. `Data collection → Hosts → SFCG-WSV2-02 → Discovery` (LLD rules) — status of the Windows
   Performance Counters (or equivalent) discovery rule: last execution time, any errors, item
   prototype count found on VM2 vs VM1.
4. On `SFCG-WSV2-02` itself: `Get-Counter -ListSet "Web Service"` (or `typeperf -q | findstr "Web Service"`)
   to get the real instance name Windows exposes for the site — the ground truth to compare macro/
   discovery against.

## Next step

Waiting on user to pull #1–#3 from the Zabbix frontend (or via API per `ope-zabbix` skill's known
API-access pattern, if scripting is preferred) and #4 from VM2 directly.
