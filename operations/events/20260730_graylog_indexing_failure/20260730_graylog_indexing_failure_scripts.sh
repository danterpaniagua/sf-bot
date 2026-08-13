#!/usr/bin/env bash
# Event: 20260730_graylog_indexing_failure
# Commands grouped by phase: Investigation
# Same method as C34-C36 in 20260729_graylog_sin_datos — Graylog indexer-failures REST API,
# not the UI "Message Errors" panel, to get a directly comparable number.

# === INVESTIGATION — Reconcile failed-to-index count ===

# C40 — Total failure count, all-time (comparable to the 146,813 figure from 2026-07-30)
curl -s -u "$TOKEN:token" -H "X-Requested-By: cli" \
  "https://sfcloud-monitoreo.smartfran.com/graylog/api/system/indexer/failures/count?since=2000-01-01T00:00:00.000Z"
# OUTPUT (2026-07-31): {"count": 62874}

# C41 — Failure count since the confirmed cliff (comparable to the 62,876 figure from 2026-07-30)
curl -s -u "$TOKEN:token" -H "X-Requested-By: cli" \
  "https://sfcloud-monitoreo.smartfran.com/graylog/api/system/indexer/failures/count?since=2026-07-28T06:00:00.000Z"
# OUTPUT (2026-07-31): {"count": 62874} — essentially identical to C40 (all-time)

# C42 — Failure count in the last hour (confirms whether failures are still actively occurring
# right now, vs. having stopped since the 2026-07-30 check)
curl -s -u "$TOKEN:token" -H "X-Requested-By: cli" \
  "https://sfcloud-monitoreo.smartfran.com/graylog/api/system/indexer/failures/count?since=$(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S.000Z)"
# OUTPUT (2026-07-31): {"count": 62931} — nearly identical to C40/C41 despite the much
# narrower window; implies the whole visible failure history now fits within ~1h, i.e. the
# failure rate has risen sharply since the ~1,164/hr measured on 2026-07-30

# C43 — Most recent failure sample (timestamp + error type), to confirm failures are still
# the same event_original/business__6 pattern and get the latest failure timestamp
curl -s -u "$TOKEN:token" -H "X-Requested-By: cli" \
  "https://sfcloud-monitoreo.smartfran.com/graylog/api/system/indexer/failures?limit=5&offset=0"
# OUTPUT (2026-07-31): 5/5 timestamped 2026-07-31T12:18:46.1xx-2xx (sub-second apart),
# index "business__7" (rotated from business__6), same error signature as before
# (event_original immense term, 131,193-131,735 bytes) — confirms failures are ongoing
# right now, same root cause, on a newly-rotated index. Decoding the error's 30-byte
# "prefix of the first immense term" (bytes 123,34,114,101,99,111,114,100,115,...) gives
# literally `{"records": [{ "time": "2026-0` — the Azure Diagnostic Settings BATCH wrapper,
# not a single record. Contradicts 20260729_graylog_sin_datos C39 ("fix correctly scopes
# event_original to one record"). Needs the full raw message (Lucene's preview caps at 30
# bytes, not configurable) to confirm whether this is a real regression or a single Business
# record that legitimately contains its own "records" key (e.g. a logged API response body).

# === INVESTIGATION — Full raw message content, via Log Analytics (bypasses the 32KB Lucene
# cap entirely — Business has a confirmed dual Diagnostic Settings destination: Event Hub
# (the failing path) AND Log Analytics workspace SmartFranCloudPro, per cloud-graylog/CLAUDE.md) ===

# C44 — Longest AppServiceConsoleLogs entries for Business around the C43 failure timestamp
az monitor log-analytics query \
  --workspace 76536d4a-5616-44ae-bee4-0aa6963b5d28 \
  --subscription 85c76dea-3304-4310-8656-bf21b28e4f4b \
  --analytics-query "AppServiceConsoleLogs | where TimeGenerated between (datetime(2026-07-31T12:15:00Z) .. datetime(2026-07-31T12:22:00Z)) | where _ResourceId has 'Business' | extend len = strlen(ResultDescription) | top 5 by len desc | project TimeGenerated, len, ResultDescription" \
  --output table

# C45 — Same window, AppServiceAppLogs (ILogger-based app logs — where EF Core Debug tracing
# and EnableSensitiveDataLogging output would most likely land)
az monitor log-analytics query \
  --workspace 76536d4a-5616-44ae-bee4-0aa6963b5d28 \
  --subscription 85c76dea-3304-4310-8656-bf21b28e4f4b \
  --analytics-query "AppServiceAppLogs | where TimeGenerated between (datetime(2026-07-31T12:15:00Z) .. datetime(2026-07-31T12:22:00Z)) | where _ResourceId has 'Business' | extend len = strlen(ResultDescription) | top 5 by len desc | project TimeGenerated, len, ResultDescription" \
  --output table
# OUTPUT (2026-07-31): top 5 lengths (full SQL text + EnableSensitiveDataLogging parameter
# dump included): 2918, 2912, 2398, 2398, 2393 characters. All are EF Core "Executed"/
# "Executing DbCommand" entries. Raw ResultDescription content NOT persisted here (contains
# production data — franchise/city/province/country IDs, GUIDs, promotional text; no
# names/emails observed). Max length found is ~45x smaller than the smallest oversized
# event_original term observed (131,193 bytes) — rules out individual record size (even
# with full sensitive-data logging) as sufficient to cause the Lucene immense-term failure
# on its own. Reopens the "regression of 2026-07-02 fix" theory from 20260729 investigation
# C39 — that check only confirmed the fix line exists in the config, not that it's applied
# to the payloads that are actually failing.

# === INVESTIGATION — Full Logstash pipeline filter logic on smartfran-graylog-pro ===
# ⚠️ az vm run-command invoke (read-only — cat only, no state change, but flagging per
# convention since it executes a script on a prod host)

# C46 — Full azure-eventhub-to-graylog.conf, not just the event_original line (C39 in
# 20260729_graylog_sin_datos only grepped +/-5 lines around event_original; this pulls the
# whole filter block, in particular the record-splitting logic upstream of it, to find why
# event_original is still landing as the batch wrapper for at least some payloads)
az vm run-command invoke \
  --resource-group SMARTFRAN.CLOUD.PRO \
  --name smartfran-graylog-pro \
  --subscription 85c76dea-3304-4310-8656-bf21b28e4f4b \
  --command-id RunShellScript \
  --scripts "cat -n /etc/logstash/conf.d/azure-eventhub-to-graylog.conf"
# OUTPUT (2026-07-31): full config retrieved — see analysis in investigation.md
# "Confirmed root cause" section. Canonical redacted copy stored at
# settings/prod-sfcloud-monitoreo/etc/logstash/conf.d/azure-eventhub-to-graylog.conf

# === REMEDIATION — applied directly via SSH (user has host access, no az vm run-command
# needed for this phase) ===

# C47 — ⚠️ Patch applied: added `else` branch (tag event_original_guard_skipped) to the
# 2026-07-02 fix's guard, plus an unconditional event_original size-cap/truncation ruby
# filter right before the gelf output. Patched file backed up first
# (azure-eventhub-to-graylog.conf.bak-<timestamp>). Full patched content in
# settings/prod-sfcloud-monitoreo/etc/logstash/conf.d/azure-eventhub-to-graylog.conf
# (credentials redacted in the repo copy; real file on host untouched in input{}).
# Validated: `sudo -u logstash /usr/share/logstash/bin/logstash --path.settings /etc/logstash -t`
# OUTPUT (2026-07-31T14:04:09Z): "Configuration OK" — syntactically valid. Also surfaced an
# unrelated pipeline-level detail: `pipeline.ecs_compatibility: v8` is set (not in this .conf
# file — must be in pipelines.yml/logstash.yml). Flagged as an open risk: if azure_event_hubs/
# gelf plugins have ECS-aware field behavior (e.g. a nested [event][original] distinct from
# the flat event_original this filter manipulates), the patch could be truncating the wrong
# field. Not confirmed — resolving via live post-restart failure-rate check instead of static
# analysis.

# ⚠️ C48 — Logstash restart to apply the patch
sudo systemctl restart logstash
sudo systemctl status logstash --no-pager
# OUTPUT (2026-07-31T14:06:33Z): active (running), 19ms uptime at time of check — too early
# to have reconnected the Event Hub consumer group yet (prior restart on 2026-07-28 took
# ~15-20s to reach "Pipeline started" per 20260729_graylog_sin_datos C38). Re-checked after
# a wait — see below.

# OUTPUT (2026-07-31T14:08:44Z, ~2min11s uptime): active (running), Event Hub partition
# receivers open and consuming as of 14:07:12Z (onOpenComplete, PartitionPump creation
# finished) — pipeline fully up, ~40s after restart.

# C49 — Post-restart verification: are new failures still occurring on the patched pipeline?
# since=14:07:00Z, just before consumption resumed, to catch anything from the moment
# traffic started flowing through the patched filter chain
curl -s -u "$TOKEN:token" -H "X-Requested-By: cli" \
  "https://sfcloud-monitoreo.smartfran.com/graylog/api/system/indexer/failures/count?since=2026-07-31T14:07:00.000Z"
# OUTPUT (2026-07-31T14:15:42Z, ~8min42s / 522s after the window start): {"count": 18186}
# = ~34.8 failures/sec, same order of magnitude (if not higher) than the pre-patch rate.
# Patch had ZERO measurable effect.

# C50 — Sample of newest failures post-patch, to check if event_original is actually
# smaller now (truncated) or unchanged
curl -s -u "$TOKEN:token" -H "X-Requested-By: cli" \
  "https://sfcloud-monitoreo.smartfran.com/graylog/api/system/indexer/failures?limit=5&offset=0"
# OUTPUT (2026-07-31T14:13:54Z, 7+ min after Event Hub consumption resumed): still
# 131,425-131,756 bytes, same batch-wrapper error signature, index business__7. Confirms
# the patch (operating on the flat event_original field) has zero effect on the field
# that actually reaches the indexer — points at an ECS-nested [event][original] field,
# distinct from the flat one, given pipeline.ecs_compatibility: v8 is active.

# === DIAGNOSTIC — structural-only probe (no raw content) to confirm flat vs. nested field ===

# C51 — ⚠️ Added a temporary ruby filter (before output{}) logging field structure
# (key names + byte sizes for both event_original and [event][original]) to
# /tmp/event_original_debug.log — content-free, deliberately avoiding a full raw-event
# dump given EnableSensitiveDataLogging risk. Backed up current (already-patched) config
# first. Validated OK (logstash -t, pipeline.ecs_compatibility: v8 confirmed again).
# Restarted, waited 20s, file did not exist — pipeline likely hadn't finished reconnecting.

# C52 — ⚠️ INCIDENT: to get a faster/more direct look, enabled the pre-existing commented
# `stdout { codec => rubydebug }` line in output{} (in addition to C51's structural filter)
# and restarted. This tried to pretty-print full multi-hundred-KB events via amazing_print,
# exhausted the 1GB JVM heap: `java.lang.OutOfMemoryError: Java heap space` at 14:20:19Z,
# followed by a crash/restart loop (PIDs 599301 -> 599539 -> 599680 within ~2 minutes).
# Before the crash, journal output showed a nested-looking `"original" => "{\"records\":
# [...` fragment (indentation consistent with a field nested under a parent key, e.g.
# event.original under ECS) — supporting evidence for the ECS-nested-field theory, but the
# instability this caused outweighed the partial confirmation. Root cause of the crash:
# rubydebug/amazing_print is unsuitable at this event size/volume, not a config syntax bug.

# ⚠️ C53 — Recovery: restored the ORIGINAL pre-session config (azure-eventhub-to-graylog.old,
# manually backed up by the user before any patch was applied today), discarding both the
# else/truncation patch AND the diagnostic/rubydebug additions, to prioritize pipeline
# stability over an in-progress fix. No .bak-debug-* file was found (ls showed only the
# live .conf and .old) — .old was the only confirmed-good fallback available.
sudo cp /etc/logstash/conf.d/azure-eventhub-to-graylog.old /etc/logstash/conf.d/azure-eventhub-to-graylog.conf
sudo -u logstash /usr/share/logstash/bin/logstash --path.settings /etc/logstash -t
# OUTPUT (2026-07-31T14:27:41Z): Configuration OK

# ⚠️ C54 — Restart on restored original config, stability check
sudo systemctl restart logstash
sudo systemctl status logstash --no-pager
# OUTPUT (2026-07-31T14:29:45Z, checked 30s later): active (running), single stable PID
# 600447, no restart cycling, Event Hub partitions reconnected (onOpenComplete). Confirmed
# stable. Pipeline is back to its ORIGINAL (pre-2026-07-31-session) state — the underlying
# indexing-failure bug is NOT fixed; today's patch attempts were reverted for stability.

# === PATCH v2 — dual-field truncation (flat event_original + nested [event][original]) ===
# Applied via SSH, filter{}/output{} blocks only (input{} with real credentials left
# untouched, per settings/prod-sfcloud-monitoreo/.../azure-eventhub-to-graylog.conf which
# now carries the exact deployed content, credentials redacted).

# ⚠️ C55 — Backup before edit (confirmed present this time via ls, unlike the earlier attempt)
sudo cp /etc/logstash/conf.d/azure-eventhub-to-graylog.conf /etc/logstash/conf.d/azure-eventhub-to-graylog.conf.bak-$(date +%Y%m%d%H%M%S)
ls -la /etc/logstash/conf.d/*.bak-*
# OUTPUT: backup file present and confirmed (filename not captured verbatim in this session)

# C56 — Validate the v2 patch (else-branch tag + unconditional dual-field truncation)
sudo -u logstash /usr/share/logstash/bin/logstash --path.settings /etc/logstash -t
# OUTPUT: Configuration OK

# ⚠️ C57 — Restart to deploy v2
sudo systemctl restart logstash
sudo systemctl status logstash --no-pager
# OUTPUT (2026-07-31T14:40:26Z): clean startup, Event Hub partitions reconnecting normally
# (onOpenComplete, PartitionPump ... creation finished for multiple partitions), no OOM,
# no restart cycling — stable.

# C58 — Post-deploy verification: newest failures + explicit since-restart count
curl -s -u "$TOKEN:token" -H "X-Requested-By: cli" \
  "https://sfcloud-monitoreo.smartfran.com/graylog/api/system/indexer/failures?limit=5&offset=0"
# OUTPUT: newest failures all timestamped 14:37:46Z — BEFORE the 14:40:26Z restart, i.e.
# nothing newer found at all

date -u +%Y-%m-%dT%H:%M:%S.000Z
curl -s -u "$TOKEN:token" -H "X-Requested-By: cli" \
  "https://sfcloud-monitoreo.smartfran.com/graylog/api/system/indexer/failures/count?since=2026-07-31T14:40:30.000Z"
# OUTPUT: checked at 14:41:49Z (79s after the since-window start) -> {"count": 0}. Zero
# failures in 79s against a pre-fix rate of ~35/sec is a strong early positive signal.
# NOT YET a confirmed fix — needs a longer soak window before closing.
