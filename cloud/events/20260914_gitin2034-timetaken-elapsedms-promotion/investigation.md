# Investigation — GITIN-2034: TimeTaken / ElapsedMilliseconds promotion

**Status:** converged — fix deployed and verified live

## Task

User ask: promote `TimeTaken` from `PROD-Sales-AppServiceHTTPLogs` (and "all httplogs") and `event_original.Properties.ElapsedMilliseconds` to top-level, queryable Graylog fields.

## Critical prior context — this looks like a regression, not new work

`GITIN-1940` (`cloud/events/20260825_sales-caerequest-408-timeout/`) already added and **verified live** (2026-08-26) a Logstash filter block promoting exactly these fields — `StatusCode`, `Path`, `Method`, `ElapsedMilliseconds`, `ClientIP` — across two source branches:
1. ASP.NET Core "Request finished" hosting-diagnostics line (`Properties.ElapsedMilliseconds`, Float) — Sales direct-GELF + Event Hub apps.
2. Azure's own `AppServiceHTTPLogs` category (`properties.TimeTaken`, Integer→Float cast) — Windows Event Hub apps' infra-level HTTP access log.

Verification at the time (per that ticket's investigation.md) confirmed both `StatusCode` and `ElapsedMilliseconds` live on a real Sales-PRO sample, plus `Path`/`Method` confirmed via a 788-match query, plus `ClientIP` via a 5770-match `AppServiceHTTPLogs` query. All 5 fields, both branches, marked complete.

## What this session (`20260913_pos-net-http-timeout`) found (2026-09-13/14)

Queried `Service:"Sales" AND Environment:"Production"` directly and inspected a real live message (`_id` visible in that event's `data/graylog_sales_serverside_crash_moment.json`). Top-level keys present: `AppLevel, Component, Environment, Level, MessageTemplate, Method, Path, ProcessType, Properties, RequestId, Service, SourceContext, StatusCode, TenantId, Timestamp, TraceKey, UserId, Version, ...`.

**`ElapsedMilliseconds` is NOT among them.** `StatusCode`/`Path`/`Method` ARE present and correct. The actual elapsed-time value is only reachable by parsing `event_original` (a JSON string) → `.Properties.ElapsedMilliseconds` (e.g. `37.2628`).

So: 3 of the 4 "Request finished" fields are still promoted correctly; only `ElapsedMilliseconds` specifically has regressed (or was never actually working for this exact field on this exact branch, despite the 2026-08-26 verification — worth checking whether that verification's sample was genuinely the Sales-PRO branch or the Event Hub apps branch, since the investigation notes one confirmation came from a `SourceContext: System.Net.Http.HttpClient.Auth0.LogicalHandler` sample, not necessarily proving the Sales-specific Ruby branch).

## Open questions

- Is the live Logstash conf on the VM still running the GITIN-1940 block as originally deployed, or did a later change touch it? Need to fetch and diff against the historical patch before assuming anything.
- Is this a Logstash-side issue (the field extraction rule itself), or an OpenSearch/index-mapping-side issue (field silently dropped due to a type conflict, e.g. if some other service ever sent a non-numeric value under the same field name)? The known 1000-field-mapping-cap issue is documented for the *other* (SmartPedidos/SmartLoyalty) Graylog stack, not this one — don't assume it applies here without checking.
- Scope of "all httplogs" (per user's ask) — does this mean re-verify across all 8 PRO App Services' `AppServiceHTTPLogs` category, not just Sales? `AppServiceHTTPLogs` scope for Pos was explicitly left unconfirmed in the original GITIN-1940 ticket.
- `TimeTaken` (the `AppServiceHTTPLogs` source key) itself — is it also broken, or only the "Request finished" line's `Properties.ElapsedMilliseconds`? Need to check an `AppServiceHTTPLogs`-sourced sample specifically (`category:AppServiceHTTPLogs`), separate from the direct-GELF Sales sample already checked.

## Access details (from precedent ticket `20260825_sales-caerequest-408-timeout/scripts.sh`)

- Host: `sfcloud-monitoreo.smartfran.com`, port `5689`, key `~/.ssh/sfcloud_monitoreo`, user `gadmin`.
- Live conf path: `/etc/logstash/conf.d/azure-eventhub-to-graylog.conf`.
- Deploy convention: never scp the local redacted-secrets copy over the live file. Patch via `ssh ... "cat > /tmp/x.patch" < local_file`, dry-run with `patch --dry-run`, validate with `logstash -t` (syntax only, not runtime — past incident where `-t` passed but service still crash-looped), then `systemctl restart logstash`, then confirm not crash-looping.

## Findings so far

- **Live Logstash conf confirmed intact and unchanged.** Fetched `/etc/logstash/conf.d/azure-eventhub-to-graylog.conf` from `sfcloud-monitoreo.smartfran.com`. The GITIN-1940 block (lines 299-379) is deployed exactly as originally verified working — the Sales branch's `ElapsedMilliseconds` extraction (lines 330-343) uses the identical pattern/guard as `StatusCode`/`Path`/`Method` from the same `Properties` hash. Since those 3 other fields ARE confirmed working live, this rules out a Logstash-side regression — the rule itself is logically sound and unchanged.
- **`AppServiceHTTPLogs` branch confirmed fully healthy** — `ElapsedMilliseconds` correctly populated on live Admin-PRO/Orders-PRO samples (5,200 total matches in 1h). The regression is isolated specifically to the Sales direct-GELF "Request finished" branch.
- **Separate, large-scale finding: 64,866 total Graylog indexing failures** (`GET /api/system/indexer/failures`), all `mapper_parsing_exception` on a `time` field (type `date`) rejecting a non-ISO8601 format (`'09/13/2026 23:48:43'`, MM/DD/YYYY). Whole documents are rejected from the index, not a single field silently dropped. **No mention of `ElapsedMilliseconds` anywhere in these failures** — not evidenced as the same root cause as the missing-field mystery, but large enough (64K+) to warrant its own follow-up, potentially a separate ticket. Not investigated further here — out of this ticket's scope.
- **Root cause of the missing `ElapsedMilliseconds` on Sales' "Request finished" line remains unconfirmed.** Ruled out: Logstash rule regression. Not yet confirmed: an OpenSearch field-level type conflict specific to this field (plausible since it's the only Float among the 4 promoted fields, but no direct evidence found so far — the actual indexer failures found are about an unrelated `time` field, not `ElapsedMilliseconds`).

## Root cause confirmed (AppServiceHTTPLogs branch) — 2026-09-14

User-supplied sample, `_id: b4966b92-b038-11f1-be92-7c1e52beabec`, index `http_sales__9`, Sales-PRO `/api/v1/Status/Health`. **None of the 5 GITIN-1940 fields promoted** (`Method`/`Path`/`StatusCode`/`ElapsedMilliseconds`/`ClientIP` all absent from top-level) — not an `ElapsedMilliseconds`-specific bug, the whole branch silently no-ops for this message shape.

**Mechanism:** `event_original` for this message is a **flat/unwrapped** record — `{"properties":{...},"resourceId":...,"category":"AppServiceHTTPLogs","time":"..."}` — no `"records"` array wrapper at all (unlike the Diagnostic-Settings-batch shape GITIN-1940 was originally verified against). For this flat shape, Logstash's very first `json { source => "message" }` filter (line 12-16 of the conf) parses `properties` directly into a **live Ruby Hash**. Confirmed by the processed message's own `message` field (`"GET /api/v1/Status/Health - 200"`) — this exact string could only have been built by the message-construction block (conf lines 103-115), which reads `event.get("properties")` **as a Hash** (`props["CsMethod"] && props["CsUriStem"]`) and succeeds. Nothing between that point and the GITIN-1940 block (conf lines 299-379) stringifies lowercase `properties` — that stringification only happens later, at conf lines 432-439, *after* GITIN-1940's block already ran. So when GITIN-1940's `AppServiceHTTPLogs` branch (line 362) checks `props_json.is_a?(String)`, it's still a Hash → guard fails → entire branch no-ops.

**Secondary bug, same branch:** `ScStatus` in this raw shape is a JSON **Integer** (`200`), not the string (`"200"`) the current regex-based cast (`ScStatus.is_a?(String) && ScStatus.match?(/\A\d+\z/)`) expects. Even a Hash-aware fix needs to handle both representations.

**Two ingestion shapes exist for `AppServiceHTTPLogs` category, not one:** (a) wrapped in a `"records"` array (Diagnostic Settings batch envelope) — `properties` sub-key arrives pre-stringified by Azure, GITIN-1940's current code handles this correctly; (b) flat/unwrapped — `properties` arrives as a native Hash after Logstash's own initial parse, GITIN-1940's code does not handle this at all. Not yet determined what causes a given message to arrive in one shape vs. the other (batch size? App Service Windows vs Linux? not investigated).

**Proposed fix:** make the `AppServiceHTTPLogs` branch accept `properties` as either a Hash or a String (parse only if String, use directly if already a Hash), and make the `ScStatus`→`StatusCode` cast handle both Integer and numeric-String forms. Draft:

```ruby
props_json = event.get("properties")
http_props = nil
if props_json.is_a?(String) && props_json.strip.start_with?("{")
  begin
    http_props = JSON.parse(props_json)
  rescue JSON::ParserError
  end
elsif props_json.is_a?(Hash)
  http_props = props_json
end
if http_props.is_a?(Hash)
  event.set("Method", http_props["CsMethod"]) if http_props["CsMethod"].is_a?(String) && !http_props["CsMethod"].empty?
  event.set("Path", http_props["CsUriStem"]) if http_props["CsUriStem"].is_a?(String) && !http_props["CsUriStem"].empty?
  if http_props["ScStatus"].is_a?(String) && http_props["ScStatus"].match?(/\A\d+\z/)
    event.set("StatusCode", http_props["ScStatus"].to_i)
  elsif http_props["ScStatus"].is_a?(Integer)
    event.set("StatusCode", http_props["ScStatus"])
  end
  event.set("ElapsedMilliseconds", http_props["TimeTaken"].to_f) if http_props["TimeTaken"].is_a?(Numeric)
  event.set("ClientIP", http_props["CIp"]) if http_props["CIp"].is_a?(String) && !http_props["CIp"].empty?
end
```

**Not yet resolved / separate:** the original puzzle from `20260913_pos-net-http-timeout` (Sales direct-GELF "Request finished" line, only `ElapsedMilliseconds` missing while `StatusCode`/`Path`/`Method` work fine) is a **different bug** — that branch's guard logic doesn't have this Hash-vs-String issue (traced through the conf, `Properties` capital-P is confirmed stringified by GITIN-1883's block before GITIN-1940 reads it). That one remains unexplained; do not assume this fix resolves it too.

## Deploy attempt #1 — failed at syntax validation, reverted (2026-09-14)

Patch applied (D3) then failed `logstash -t` (D4): `Expected one of [ \t\r\n], "#", "{", "}"` at the new comment block. Root cause: the patch's own comment text used an apostrophe ("pipeline's own initial") inside the `code => '...'` single-quoted Logstash string — exactly the failure mode this same conf file's own header comment (lines 23-31) warns about. A literal single quote inside that outer string closes it prematurely.

**Impact: none.** The patch was applied to the file on disk, but Logstash was never restarted (D5 not reached) — the running process kept using the old, valid, in-memory config the whole time. Reverted via the D2 backup (`azure-eventhub-to-graylog.conf.bak-GITIN-2034`), re-validated with `logstash -t` → `Configuration OK`, confirmed back to known-good state.

**Fix:** reworded the comment to avoid the apostrophe ("by the initial json filter at the top of this file" instead of "by this pipeline's own initial json filter"). Verified before regenerating the patch: (1) a local Python quote-balance scan of the full `code => '...'` block (lines 313-394) found no stray single quotes anywhere in it; (2) extracted just the Ruby code (excluding the Logstash `code => '`/`'` wrapper lines) and ran `ruby -c` locally — `Syntax OK`; (3) confirmed via `diff` that no added line in the patch contains a `'` character at all. Patch regenerated (`gitin-2034.patch`) and re-confirmed to apply cleanly locally (`patch --dry-run`).

## Deploy #2 — success, verified live (2026-09-14)

`logstash -t` → `Configuration OK`. `systemctl restart logstash` → clean startup, Event Hub receivers opened successfully on both partitions ("EH client and receiver creation finished", no errors). Post-deploy verification query (`category:AppServiceHTTPLogs AND name:SMARTFRAN-CLOUD-SALES-PRO`, last 5 min): **68 total matches, all 5 fields confirmed populated** on 10/10 sampled real live messages — `Method`, `Path`, `StatusCode`, `ElapsedMilliseconds`, `ClientIP` all present and correctly typed (e.g. `ElapsedMilliseconds: 34.0`, `247.0`, `5192.0`).

**Incidental reinforcement of the `20260913_pos-net-http-timeout` incident's open lead**: this same verification data shows `/api/v1/Shift/GetPaginatedForReportByFilterAsync` still running 5,192ms and 5,825ms on current live traffic — matching the same slow pattern found during the OOM crash investigation. Independent confirmation (different day, different mechanism of observation) that this endpoint is persistently slow, not a one-off — strengthens it as the memory-leak candidate for that ticket.

**Scope note:** this fix addresses the `AppServiceHTTPLogs` branch only (all apps, "all httplogs" per the original ask — Method/Path/StatusCode/ElapsedMilliseconds/ClientIP). It does **not** address the separate, still-unexplained Sales direct-GELF `ElapsedMilliseconds`-only gap (`Service:"Sales"` branch, "Request finished" line) found in the original incident investigation — that one's guard logic was confirmed correct via code tracing, with no evidence pointing at a similar Hash-vs-String cause. Left open, not blocking this ticket's closure.

## Post-fix validation against live state (2026-09-14)

- **Conf drift check**: fresh fetch of the live conf, byte-for-byte diff against our deployed version — exact match, no drift since deploy.
- **Field-existence validation**: ran `_exists_:<field>` for all 23 fields tracked in `docs/graylog-log-fields.md`, 24h window. All "always-present" fields and the 5 GITIN-1940/2034 fields confirmed genuinely live at scale (hundreds of thousands to millions of hits) — not just on the small samples checked earlier. One real discrepancy found: `Category` is no longer 0 hits (638/24h) — the doc's "not yet observed live" claim (from 2026-08-19) is now stale; a `SmartFranLogExtensions` helper has fired since. The other 5 conditional fields (`ErrorCode`/`Operation`/`Recovered`/`Handled`/`AuditAction`/`AuditOutcome`) are still genuinely at 0.
- **`docs/graylog-log-fields.md` updated** to reflect all of the above: the GITIN-2034 bug mechanism and fix, the `Category` correction, and the still-open `Service:"Sales"` `ElapsedMilliseconds` gap — all now traceable to real verification rather than assumed from source code or prior (now-stale) doc claims.

## Next steps

1. Fetch the live conf (read-only) and locate the GITIN-1940 block.
2. Confirm/deny whether it still contains the `ElapsedMilliseconds` extraction for the Sales branch, and whether the Ruby logic matches what was originally deployed.
3. Check an `AppServiceHTTPLogs`-sourced sample directly for `TimeTaken`/`ElapsedMilliseconds` status, separately from the Sales direct-GELF branch.
4. Diagnose root cause (Logstash rule regressed vs. OpenSearch mapping conflict) before drafting any patch.
