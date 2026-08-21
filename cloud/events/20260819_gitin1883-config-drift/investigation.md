# Investigation — GITIN-1883's later patches missing from live VM despite documented deploy + verification

**Status:** Closed 2026-08-19 — false alarm, root cause was an assistant misreading, not a real production gap. GITIN-1883's fix (`TraceKey`/`TenantId`/`Service`/`Environment` promotion + Sales naming-unification, both branches) IS fully deployed and persisted on the live VM. Confirmed by direct `grep` of all 8 `event.set(...)` lines in the live file against the repo copy — byte-identical. No regression, no gap, no false verification by GITIN-1883. See "Resolution" below.

## Objective

Determine why the live Logstash pipeline file on `sfcloud-monitoreo` (`/etc/logstash/conf.d/azure-eventhub-to-graylog.conf`) only contains GITIN-1883's **first** patch (`TraceKey`/`TenantId` promotion) and not the two later ones from the same ticket (`Service`/`Environment` promotion; Sales naming-unification + `Properties` stringification + 3 Graylog Pipeline Rule updates) — despite GITIN-1883's `investigation.md`/`ops-events.md` (closed 2026-08-18) documenting all of it as deployed **and verified against live traffic** (a real Sales message at `21:35:23Z` showing `Service: "Sales"`, `Environment: "Production"`, no `Properties_*` remaining).

## Confirmed facts

- **VM file fetched 2026-08-19** via `sudo cat /etc/logstash/conf.d/azure-eventhub-to-graylog.conf` over SSH (correct host/path, confirmed by the user) — saved to `cloud/events/20260819_promote-remaining-clef-fields/vm-live-azure-eventhub-to-graylog.conf`. Diffed against `cloud-graylog/docs/azure-eventhub-to-graylog.conf` (the repo's versioned copy, itself confirmed in sync with the VM as of GITIN-1883's close).
- The VM's GITIN-1883 comment block and code only cover `TraceKey`/`TenantId` — the comment text itself is the **first-patch wording** ("GITIN-1883: TraceKey / TenantId — promote from Properties.TraceKey and Properties.TenantId..."), not the final wording GITIN-1883's own investigation.md quotes ("TraceKey / TenantId / Service / Environment — promote to bare top-level fields, unified across ALL services...").
- The Sales branch (`top_props = event.get("Properties")`, the stringification, the whole "Sales direct-GELF" comment section) is **entirely absent** from the live file — not just missing 2 fields, the whole second branch doesn't exist there.
- The `input {}` block (Event Hub connection string / storage connection) is also absent from the fetched file — the user confirmed this is deliberate redaction before sharing the file in this repo, not part of the drift itself. Not investigated further here.

## Ruled out

- Not a wrong-host/wrong-path fetch — user explicitly re-confirmed the exact `ssh ... sudo cat /etc/logstash/conf.d/azure-eventhub-to-graylog.conf` command used.
- Not a stale local repo copy comparison artifact — `cloud-graylog/docs/azure-eventhub-to-graylog.conf` has the full 4-field + Sales-unification GITIN-1883 code (confirmed by direct read in this session, prior to any GITIN-1892 edits).

## Current working theory

Not yet established. Candidates to check, none confirmed:
1. GITIN-1883's later 2 patches (`gitin-1883-service.patch`, `gitin-1883-environment.patch`, `gitin-1883-sales-unify.patch` — files should exist in `cloud/events/20260818_properties-flat-other-services/`) were applied to a **different** file/host than the one actually serving production traffic, or applied and then the file was reverted/restored from an older backup or checkpoint mechanism afterward.
2. Logstash was reinstalled/redeployed (e.g. VM rebuild, config-management run, package reinstall) after GITIN-1883's session, resetting `conf.d/` to an earlier state — would need to check VM provisioning/config-management logs, not yet done.
3. GITIN-1883's own verification was against a different file than the one actually loaded by the running Logstash service (e.g. a `.conf.bak`, a symlink pointing elsewhere, multiple Logstash instances) — the live-traffic confirmation could have been real but not caused by the same file being diffed now.
4. The live-traffic verification samples in GITIN-1883's `ops-events.md` were captured, then something reverted the file afterward, unrelated to that session.

## Resolution (2026-08-19)

All 3 checks came back clean, and together they revealed the real cause:

- **C1 (Graylog Pipeline Rules):** all 3 rules already reference bare `Service`/`Environment` — never reverted.
- **C2 (live Sales traffic):** a real message from the last hour has bare `Service`/`Environment`/`TraceKey`/`TenantId`, zero `Properties_*` fields — production behavior already matches GITIN-1883's documented outcome.
- **C3 (VM file mtime + backups):** found `azure-eventhub-to-graylog.conf.orig` (a `patch`-generated pre-patch snapshot, mtime 2026-08-18 19:32) alongside the live file (mtime 19:53:32) — consistent with a later patch landing between those two timestamps, not a rollback.

Diffing `.orig` against the live file showed the live file **has** the `Environment` promotion line and the entire Sales-unification branch that `.orig` lacks — the opposite of what the assistant originally concluded. Direct `grep` of all 8 `event.set("TraceKey"/"TenantId"/"Service"/"Environment", ...)` lines in both the live VM file and the repo copy confirmed byte-identical code.

**Actual root cause of the false alarm:** GITIN-1883's own deployment practice (documented in its own `ops-events.md`) is to patch only *code* lines on the VM, deliberately never rewriting the block's leading `#` comment — to keep each incremental patch minimal and reduce hunk-context risk. That means the live file's comment still reads "GITIN-1883: TraceKey / TenantId — promote from..." (the wording from the *first* patch), even though the code beneath it was correctly extended twice more. When the assistant first read the live file in this session, it read that stale comment, didn't look carefully enough at the actual code below it, and wrongly concluded the whole later-patch work was missing. It wasn't — this event folder documents the false alarm and its correction so it doesn't get re-litigated in a future session.

## Open questions / next steps

None — closed. GITIN-1892 can proceed using the live VM file already fetched to `cloud/events/20260819_promote-remaining-clef-fields/vm-live-azure-eventhub-to-graylog.conf` as the correct patch base.
