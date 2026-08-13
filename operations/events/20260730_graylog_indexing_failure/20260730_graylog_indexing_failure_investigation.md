# Investigation — 20260730_graylog_indexing_failure

**Status:** in progress

## Scope note

Split out from `20260729_graylog_sin_datos` (2026-07-31) — that investigation covers two entangled-in-timing but independently-caused problems: (1) the Business/Sales volume collapse at 2026-07-28 06:00 UTC (Logstash restart theory, still open there) and (2) these OpenSearch indexing failures. Root cause for (2) was already established in the other investigation's session; this file exists to carry that problem forward on its own ticket rather than block it on the still-open Logstash-restart question. Facts below marked "(from 20260729 investigation)" are carried over, not re-derived.

## Confirmed facts

- **(from 20260729 investigation, C34-C36)** Graylog UI "Message Errors" panel, checked 2026-07-30: Input errors 0, processing errors 0, failed to index 146,813 total. Of those, 62,876 fall in the window since the 2026-07-28 06:00 UTC cliff (identical count whether measured "since cliff" or "since 24h before cliff" — i.e. zero failures in the day *before* the cliff, all 62,876 start exactly at it and were still ongoing as of the 2026-07-30 check, sample timestamp `2026-07-30T12:18:57`). Remaining ~83,937 predate 2026-07-27 06:00 — old/stale, not investigated.
- **(from 20260729 investigation, C34-C36)** All sampled failures (n=25) are on index `business__6`, `type: indexing`, identical error: `Document contains at least one immense term in field="event_original"` — OpenSearch/Lucene 32,766-byte max term length exceeded, actual observed sizes 131,736-131,792 bytes.
- **(from 20260729 investigation, C39)** The 2026-07-02 fix (`/etc/logstash/conf.d/azure-eventhub-to-graylog.conf` line 62, `event.set("event_original", record.to_json)`) is present in the config — grep confirms the line exists. **Re-opened below (2026-07-31): presence of the line does not confirm it's actually applied to the specific payloads that fail.**
- **(from 20260729 investigation)** `EnableSensitiveDataLogging(true)` is hardcoded, unconditional (no environment guard), in `SmartFran.Cloud.Business.API/Program.cs`, confirmed via `git log -L` blame to commit `32385fef2` (2023-10-25) — logs full SQL parameter values. **Downgraded below (2026-07-31): real finding, but no longer the leading explanation for the 131KB term size.**
- **New data point (2026-07-31, this session, user-reported from Graylog UI):** failed-to-index count now reads **88,120**. Not directly comparable to the 146,813/62,876 API-based figures from 2026-07-30 (different scope/cache) — superseded by the C40-C43 reconciliation below, which found the underlying problem has worsened, not improved.
- **(2026-07-31, this session, C43)** Decoded the 30-byte "prefix of the first immense term" from the OpenSearch error (bytes `123,34,114,101,99,111,114,100,115,34,58,32,91,123,32,34,116,105,109,101,34,58,32,34,50,48,50,54,45,48`) → ASCII: `{"records": [{ "time": "2026-0...`. This is the Azure Diagnostic Settings **batch wrapper** shape (`{"records": [...]}`), not the shape a correctly-scoped single record (`record.to_json`) should produce.
- **(2026-07-31, this session, C44/C45)** Queried Log Analytics workspace `SmartFranCloudPro` directly (Business has a confirmed dual Diagnostic Settings destination — Event Hub and Log Analytics both receive the same raw records, per `cloud-graylog/CLAUDE.md`) for the longest Business log entries in the same few-minute window as the C43 failures. **Longest entries found: 2,918 / 2,912 / 2,398 / 2,398 / 2,393 characters** (full SQL command text plus `EnableSensitiveDataLogging` parameter dump) — `Executed`/`Executing DbCommand` EF Core entries (franchise/city/province/country IDs, GUIDs, promotional text — no names/emails observed; raw values not persisted to this file). **None come close to 32,766 bytes, let alone 131KB** — the largest individual record found is ~45x smaller than the smallest observed oversized term (131,193 bytes). A single Business log record, even at its largest observed with full SQL text and parameter logging, is nowhere near large enough to be the source of the oversized `event_original` term on its own.

## Theory 1 (2026-07-31, C46 — full pipeline config) — conditional guard, no fallback

Pulled the full `azure-eventhub-to-graylog.conf` (not just the `event_original` line). The 2026-07-02 fix (lines 51-67) is real but **conditional, with no fallback**:

```ruby
record = event.get("records")
if record.is_a?(Hash)
  event.set("event_original", record.to_json)   # the fix — only runs inside this guard
  record.each { |k, v| event.set(k, v) }
  event.remove("records")
end
```

No `else`. Per the pipeline's own comment (lines 55-56), `decorate_events => true` (azure_event_hubs input, line 9) sets `event_original` at ingestion to **the full raw Event Hub message — the whole multi-record batch** — before any filter runs. Any event that reaches this ruby block with `record` not a Hash (nil, still an Array, or missing) silently skips the entire block, including the overwrite, and keeps the original full-batch value. This matched the decoded error-prefix shape (`{"records": [{ "time": "2026-0...`, C43) and the Log Analytics size evidence (C44/C45).

**Patched and tested this session (C47-C50) — confirmed NOT the (sole) cause.** A patch based on this theory (see "Patch attempt" below) had **zero measurable effect** on the live failure rate after deployment, even 7+ minutes after the pipeline resumed consuming. This doesn't fully rule out the guard-fallback gap as a real, separate issue — it just proves it isn't what's producing the failures currently being observed. See Theory 2.

## Theory 2 (2026-07-31, C51-C52) — ECS-nested `[event][original]` field, separate from the flat one

`pipeline.ecs_compatibility: v8` is confirmed active at the pipeline level (surfaced in every `logstash -t` validation, not present in this `.conf` file — must be set in `pipelines.yml`/`logstash.yml`, not yet read directly). Under ECS compatibility, `decorate_events => true` on `azure_event_hubs` may populate a **nested** `[event][original]` field (the real ECS `event.original`) rather than, or in addition to, the flat `event_original` field this pipeline's Ruby code reads/writes via `event.get("event_original")`/`event.set("event_original", ...)`. If so, the `gelf` output — also ECS-aware by pipeline default — would independently derive the outgoing `event_original` GELF key from the nested field, meaning **all of this pipeline's Ruby filter code has been operating on a field that was never the one reaching the indexer.**

Supporting evidence:
- The Theory-1 patch (which only touches the flat field) had zero effect — consistent with the flat field being the wrong target entirely, not just an incompletely-covered guard.
- A brief, partial `rubydebug` capture (before it crashed the pipeline — see incident below) showed a fragment `        "original" => "{\"records\": [{ \"time\": ...` at an indentation level consistent with a **nested** key (i.e. under a parent `event` hash), not a flat top-level field.

**Not yet conclusively confirmed** — the rubydebug evidence is suggestive (indentation-based), not a verified full event structure dump, since the capture crashed before more could be reviewed. Needs a cleaner, safer confirmation method (see Open questions).

## Patch attempt and incident (2026-07-31, C47-C54) — reverted, pipeline restored to original state

1. **C47-C49:** Deployed a Theory-1 patch (else-branch tag + unconditional flat-`event_original` truncation before `gelf` output) directly via SSH (user has host access). Validated syntactically OK, restarted cleanly, pipeline resumed consuming Event Hub normally.
2. **C49-C50:** Post-restart verification showed **zero effect** — failure rate unchanged (~34.8/sec, same order of magnitude as before), newest failures still 131KB+, same batch-wrapper shape. This falsified Theory 1 as sufficient on its own and motivated Theory 2.
3. **C51:** Added a content-free structural diagnostic (Ruby filter logging field names + byte sizes only, to a file, not stdout) to check for a nested `[event][original]` field safely. File never populated within the wait window — inconclusive on its own.
4. **C52 — incident:** To get a faster read, additionally enabled the pipeline's pre-existing commented `stdout { codec => rubydebug }` output. This attempted to pretty-print full multi-hundred-KB events via `amazing_print`, **exhausted the 1GB JVM heap** (`java.lang.OutOfMemoryError`), and put Logstash into a crash/restart loop (3 restarts within ~2 minutes). The partial output before the crash provided the Theory 2 evidence above, but the instability was an unacceptable cost for further use of this method.
5. **C53-C54 — recovery:** No `.bak-debug-*` backup was found on the host (only the live `.conf` and a manually-made `azure-eventhub-to-graylog.old` from before any of today's changes). Restored `.old`, validated, restarted — **confirmed stable** (single PID, no restart cycling, Event Hub reconnected normally). **This reverted both today's patch attempts.** As of end of session, `smartfran-graylog-pro` is running its original, pre-2026-07-31 config — the indexing-failure bug is confirmed still present and unfixed; stability was prioritized over an incomplete/unverified fix.

## Patch v2 (2026-07-31, C55-C58) — dual-field truncation, deployed, early signal positive

Redeployed via SSH copy-paste (`filter {}`/`output {}` blocks only, `input {}` with real credentials left untouched): the else-branch/tag from Theory 1, plus an unconditional truncation ruby filter covering **both** `event_original` (flat) and `[event][original]` (ECS-nested) — sidesteps needing to conclusively confirm which field the `gelf` output actually serializes (Theory 2 was suggestive, not proven).

- **C55:** Backup created and confirmed present this time (`ls` showed the `.bak-*` file, unlike the earlier attempt).
- **C56:** `logstash -t` → `Configuration OK`.
- **C57:** Restart at `14:40:26Z` — clean startup, Event Hub partitions reconnecting normally (`onOpenComplete`, `PartitionPump ... creation finished`), no OOM, no restart cycling.
- **C58:** Verification — newest failures at check time were all timestamped `14:37:46Z`, **before** the restart (nothing newer). Explicit count check `since=2026-07-31T14:40:30Z` (i.e. after restart) → checked at `14:41:49Z` (79s later) → **`{"count": 0}`**. Against the pre-fix rate of ~35 failures/sec, 79 seconds of zero failures is a strong early positive signal.

**Not yet fully confirmed as resolved** — 79 seconds is a short soak window. Needs a longer-duration recheck (several minutes to tens of minutes) before this is called fixed, and settings/`prod-sfcloud-monitoreo` mirror needs updating to match this deployed version once confirmed stable.

## Ruled out

- Individual Business log record size, even under `EnableSensitiveDataLogging`, as sufficient on its own to trigger the 32,766-byte limit — confirmed via Log Analytics (C44/C45, this session): largest observed record in the failure window was 2,918 characters (full SQL text + parameters), ~45x too small to explain the 131,193+ byte oversized terms.
- The Theory-1 patch (flat `event_original` guard fallback + truncation) as a sufficient fix on its own — deployed and verified to have zero effect on the live failure rate (C49-C50).
- `stdout { codec => rubydebug }` as a safe diagnostic method at this event size/volume — reliably causes JVM heap exhaustion and a crash loop (C52). Do not re-enable without a much smaller/filtered sample scope (e.g. a `if` condition limiting it to one specific event, or piping through something that truncates before printing).

## Reconciliation — count check via API, not UI panel (2026-07-31, this session, C40-C43)

Same method as C34-C36 (`/api/system/indexer/failures/count`), three `since` windows plus a 5-record sample:
- C40 (`since=2000-01-01`, effectively all-time): `count: 62874`
- C41 (`since=2026-07-28T06:00:00Z`, the confirmed cliff): `count: 62874`
- C42 (`since=`~1 hour before the call): `count: 62931`
- C43 (5 most recent failures): all 5 timestamped `2026-07-31T12:18:46.1xx-2xx` (sub-second apart, sequential `letter_id`s), all on index `business__7` (not `business__6` — index has rotated since 2026-07-30), identical error signature (`event_original` immense term, sizes 131,193-131,735 bytes — same range as before).

**All three counts are nearly identical regardless of the `since` window**, including the ~1-hour window. The only way a ~1-hour window returns essentially the same count as an all-time window is if the entire visible failure history (~62,900 records) now falls within roughly the last hour — i.e. the failure rate has increased enough to fully cycle through whatever the failures store holds (capped/rolling, per Graylog's typical indexer-failures storage) in under an hour. On 2026-07-30 the rate was measured at ~1,164/hr; a buffer of ~62,900 fully turning over within ~1hr implies a current rate on the order of tens of failures/second — roughly 1-2 orders of magnitude higher than 24h ago.

**Conclusion: this is not an improvement.** The 88,120 UI figure and the 146,813/62,876 API figures from 2026-07-30 aren't on a common enough basis to compute a clean before/after delta (different scopes/caching, possible buffer capping), but the C40-C43 evidence independently shows the problem has gotten materially worse, not better, and remains actively ongoing (confirmed by C43's live timestamps). Index rotation (`business__6` → `business__7`) is normal Graylog behavior, not itself a finding — the same error signature persists across the rotation, confirming the underlying cause (oversized `event_original`, `EnableSensitiveDataLogging`) is unchanged.

**Not yet confirmed:** the exact current failure rate (tens/sec is inferred, not measured directly) and whether it's a sustained new baseline or a burst. A narrower `since` window (e.g. last 5 minutes) would pin this down if precision is needed before writing the ticket.

## Open questions / next steps

- **Status: pipeline reverted to original (unfixed) state, stability confirmed, bug still active.** Next attempt should target the nested `[event][original]` field (Theory 2), not just the flat one.
- **Confirm Theory 2 safely** before the next patch attempt — options, roughly in order of preference:
  - A structural-only Ruby filter (like C51) that explicitly checks `event.get("[event][original]")` (bracket/nested syntax) vs. `event.get("event_original")` (flat) and logs sizes/presence to a file — give it a longer wait window this time (C51's 20s may simply not have been enough for the file to populate; the pipeline resumes consuming in ~15-40s per prior restarts, then needs at least one full event to flow through).
  - If a raw content dump is still wanted, scope it tightly (e.g. gate the `stdout`/file-write with an `if` condition matching only a specific known-large event, or truncate the string before printing) — never repeat an unscoped `rubydebug` at this volume/size again (C52 incident).
- **Once Theory 2 is confirmed:** the fix needs to truncate/replace *both* the flat `event_original` and (if it exists) the nested `[event][original]` unconditionally before the `gelf` output — not just one or the other — since it's not yet certain which one (or both) the `gelf` output actually serializes into the outgoing GELF `event_original` key.
- The Theory-1 guard-fallback fix (else branch + tag) is still worth keeping in any future patch for the visibility it adds (via `event_original_guard_skipped`), even though it wasn't sufficient alone — just don't rely on it as the whole fix.
- Validate any Logstash config change with `logstash -t` before `systemctl restart logstash` (per `cloud-graylog/CLAUDE.md` working guidelines — this project has no test suite, that's the equivalent gate). Also confirm no restart-loop after every restart (`systemctl status`, uptime holding, no repeated PIDs) before considering a change "deployed."
- The Dev escalation on `EnableSensitiveDataLogging(true)` can still reuse `20260729_graylog_sin_datos`'s existing action item 2, but frame it as a separate, lower-urgency finding rather than the fix for this specific indexing-failure bug.
- Housekeeping: no `.bak-debug-*` file was ever found on the host despite the backup command being included in what was run — worth a quick check next session on why (permissions? glob mismatch? command not actually executed?) so backups can be trusted going forward.
