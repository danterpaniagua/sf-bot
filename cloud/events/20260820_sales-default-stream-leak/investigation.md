# Investigation — Default Stream carrying a lot of Sales messages (GITIN-1905)

**Status:** converged and fixed — root cause confirmed, live Graylog Pipeline Rule updated, fix validated against real live traffic (not just source diff). Ready for ticket.

## Fix deployed and validated (2026-08-20)

Pipeline Rule `6a7f2cb84814bcaed30c8de3` updated via `PUT /api/system/pipelines/rule/{id}` — `modified_at` confirms `2026-08-20T19:04:53.891Z`, source now includes `remove_from_stream(id: "000000000000000000000001")` immediately after the existing `route_to_stream()` call. Local reference file `cloud-graylog/docs/sales-direct-gelf-clef-format.rule` updated to match (also corrected a separate, unrelated drift found in the same pass: the file had `Properties_Service`/`Properties_Environment` in the `when` condition, live rule actually uses bare `$message.Service`/`$message.Environment`).

**Validated on real live traffic, not just the rule source:** a query for `name:SMARTFRAN-CLOUD-SALES-PRO AND _exists_:MessageTemplate` in Default Stream, absolute time range from `2026-08-20T19:04:54.000Z` (one second after the fix) onward, returned **0 messages** — confirms new direct-GELF Sales messages are no longer duplicating into Default Stream. Matches this project's own validation requirement (a pipeline mitigation isn't "confirmed" from source/simulator alone).

## Confirmed facts

- Sales' real dedicated stream is `PROD-Sales-AppServicePlan`, id `6a47c5c94b3c88a95fad7a7a` (created 2026-07-03), rule `field: name, type: 1 (exact), value: SMARTFRAN-CLOUD-SALES-PRO`, `remove_matches_from_default_stream: true` — correctly configured, same as every other app stream (Admin, Orders, Person, Platform, Pos, Business, Catalog, DEV all confirmed `true` via a live `GET /api/streams` list, 2026-08-20).
- Sales has **two separate ingestion paths** into Graylog: the standard Event Hub → Logstash pipeline (same as the other 7 App Services), and a **direct-GELF/CLEF sink** (GITIN-1811/1835) that bypasses Diagnostic Settings/Event Hub entirely — established because `AppServiceConsoleLogs` is structurally unsupported for .NET on Windows, and Sales runs on Windows. Direct-GELF messages arrive as bare Serilog CLEF JSON (`MessageTemplate`/`Properties`/etc., no `resourceId`/`records` envelope) and never touch the Logstash `azure-eventhub-to-graylog.conf` pipeline.
- Root cause, confirmed with live data (2026-08-20): `cloud-graylog/docs/sales-direct-gelf-clef-format.rule`, rule `"GITIN-1835: CLEF Azure resource fields for Sales PRO"` (lines 88–99), fires on every direct-GELF Sales message and calls `route_to_stream(id: "6a47c5c94b3c88a95fad7a7a")` to explicitly add the Sales stream — but never calls the matching `remove_from_stream(id: "000000000000000000000001")` to remove Default Stream. Because Graylog's Stream Router evaluates Stream Rules **before** any pipeline rule runs (the `name` field this stream's rule matches on doesn't exist yet at that point — it's set later, inside this same pipeline rule), every direct-GELF Sales message is already assigned to Default Stream by the time the pipeline explicitly adds Sales — `remove_matches_from_default_stream: true` never gets a chance to apply, because the message was never excluded by the normal Stream Rule matching path in the first place. Net effect: **every direct-GELF Sales message is permanently duplicated into both streams**, not intermittently — not stale historical data, not a partial-match issue.
- Quantified via live queries (2026-08-20, `GRAYLOG_API_KEY`):
  - `name:SMARTFRAN-CLOUD-SALES-PRO` in Default Stream, last 24h: **1,101,464** messages.
  - Same query in `PROD-Sales-AppServicePlan`, last 24h: **1,987,186** messages (higher — Sales stream also receives Event-Hub-path messages that aren't duplicated into Default, since those are excluded correctly by normal Stream Rule matching).
  - `name:SMARTFRAN-CLOUD-SALES-PRO AND _exists_:MessageTemplate` (isolating the direct-GELF path specifically) in Default Stream, last 1h: **99,786** messages — confirms the volume is coming from the direct-GELF path, consistent with the 24h totals.
  - A pulled raw sample from Default Stream confirms both: `MessageTemplate` present (direct-GELF CLEF shape, not Event-Hub shape) and `"streams": ["6a47c5c94b3c88a95fad7a7a", "000000000000000000000001"]` — both stream IDs present on the same message, direct proof of duplication rather than two disjoint populations.

## Fix

Add the missing `remove_from_stream()` call to the same pipeline rule, immediately after the existing `route_to_stream()` call:

```
route_to_stream(id: "6a47c5c94b3c88a95fad7a7a");
remove_from_stream(id: "000000000000000000000001");
```

Needs to be applied to the **live Graylog Pipeline Rule** (via the Graylog API — this is a pipeline rule managed in Graylog itself, not a file Graylog reads directly) and mirrored in the local reference copy, `cloud-graylog/docs/sales-direct-gelf-clef-format.rule`, to keep them in sync (same convention already established for the Logstash `.conf` reference copies in this project).

Scope check: this only affects Sales' direct-GELF path. No other app uses `route_to_stream()` this way — Pos and Sales are the only Windows-hosted apps with the `AppServiceConsoleLogs`-unsupported problem GITIN-1811 was about, but Pos hasn't adopted the same direct-GELF workaround (per `graylog-log-fields.md`, confirmed in a prior ticket) — so this rule, and this bug, is Sales-specific. Worth a quick confirmation that no other pipeline rule in this Graylog instance has the same `route_to_stream`-without-`remove_from_stream` pattern before closing this as fully scoped.

## Ruled out

- **Sales never having `remove_matches_from_default_stream` flipped to `true`, unlike the 6 GITIN-1834 apps** — ruled out. Live query confirms it's already `true` on Sales' real stream (id `6a47c5c94b3c88a95fad7a7a`). A stream ID cited by this project's own historical docs (`20260630_graylog-vm-terraform`) as Sales' stream turned out, on live query, to actually be `PROD-Business-AppServicePlan` today — stale/wrong doc reference, not a real config gap. Don't reuse `6a452a0d18ebc987b1ca003a` as "the Sales stream" going forward.
- **Stale historical data** (messages indexed before the stream/flag existed, not an active leak) — ruled out. The 1-hour and 24-hour counts are both consistent and large; this is live, ongoing duplication of current traffic, not residue.
- **Stream rule not matching some Sales traffic shapes** (partial-match failure, same class as `20260703_index-separation` H2) — ruled out as the cause of *this* volume. The rule matches correctly (confirmed via the raw sample showing both stream IDs) — the issue is the missing removal action in the pipeline rule, not the stream rule itself failing to match.

## Open questions / next steps

1. Apply the fix to the live Graylog Pipeline Rule (state-changing — needs explicit confirmation before running, see `ops.md`/scripts.sh once drafted).
2. Update the local reference file `cloud-graylog/docs/sales-direct-gelf-clef-format.rule` to match.
3. Confirm no other pipeline rule in this Graylog instance uses `route_to_stream()` without a paired `remove_from_stream()` — quick sweep before closing scope as Sales-only.
4. Post-fix: re-run the same 24h count query against Default Stream (`name:SMARTFRAN-CLOUD-SALES-PRO`) — expect it to drop to ~0 going forward (existing already-indexed duplicates won't retroactively disappear, only new messages stop duplicating).
5. Decide whether to also purge the ~2M+ already-duplicated historical messages from Default Stream, or leave them (they'll age out via normal index rotation/retention eventually) — a cleanup decision, not a pipeline fix.

Jira: `https://smartit-ar.atlassian.net/browse/GITIN-1905` (per user; parent not specified — check if this is a GITIN-1835 child like the recent Graylog work, or standalone).
