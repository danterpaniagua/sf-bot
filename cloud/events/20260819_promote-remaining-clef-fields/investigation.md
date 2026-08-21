# Investigation — promote remaining canonical `Properties` fields to top-level (GITIN-1892, parent GITIN-1835)

**Status:** Closed 2026-08-19. Deployed, corrected twice, and redeployed same day — final scope is 13 fields, not 12 (see below). Confirmed on live traffic: `ProcessType`/`Component`/`RequestId`/`SourceContext` all active, including on Sales (the scope-fix branch). `UserId` at 0 hits is expected (always empty in real traffic, guard correctly skips it).

**Post-close verification (2026-08-20):** cross-checked `ops.md`'s Resumen ("13 campos") against the deployed Ruby block and `devs-log-structure.md` §9 — the 13 match exactly, no gap in what this ticket claims vs. what's actually deployed. Found 3 canonical fields not in the 13 and never in this ticket's scope: `Attempt`, `Action`, `Outcome` (PascalCase companions to `_recovered`/`_audit_action`/`_audit_outcome`, arrive via message-template placeholder rather than helper scope). Already tracked as explicitly out-of-scope in `graylog-log-fields.md`'s "Full field list" section; added as `ops.md` action item #11 (non-blocking, no ticket) purely for traceability, since the field-count question keeps recurring.

**Third correction — `Version` added to scope (2026-08-19):** validating §3.2 of `devs-log-structure.md` against `EnrichmentMiddleware.cs` (prompted by a direct question: "are the §3.2 fields promoted?") found that `Version` — one of §3.2's 8 canonical fields — was never promoted by either GITIN-1883 or GITIN-1892, confirmed via `grep` (no `event.set("Version", ...)` anywhere in the pipeline). Added to both repo copies, both branches, validated with 2 new isolated test scenarios, deployed via a third scoped patch (`gitin-1892-add-version.patch`) — `Configuration OK`, `active (running)`. `ops.md` now carries a coverage table for all 8 §3.2 fields, confirming full coverage.

**Unrelated to §3.2 itself: §3.2 was validated and found accurate** (unlike §3.3) — the live-data mismatch on `Component` (`"Api"`/`"Web"` observed vs. business-domain names in source) remains unexplained; flagged as GITIN-1892 H2 for Dev to confirm deployed build, not resolved here. Also found: `EnrichmentMiddleware.cs`'s own XML doc comment claims the tenant header is `X-Tenant-Id`, but the real code constant is `"TenantId"` — a source-code-internal inconsistency, not a `devs-log-structure.md` bug (the doc already had it right).

**Critical correction found by validating against real source (`cloud/repo/SmartFran.Cloud`, `dev` branch) after first deploy:** `devs-log-structure.md` §3.6 claims all `Properties` keys are PascalCase, no `_` prefix — false for 5 of the 6 conditional fields. `SmartFranLogExtensions.cs` actually sets `_error_code`/`_recovered`/`_handled`/`_audit_action`/`_audit_outcome` (underscore-prefixed) via `BeginScope`, not `ErrorCode`/`Recovered`/`Handled`/`AuditAction`/`AuditOutcome`. Only `Operation` (via message-template placeholder rendering) and `Category` matched the doc exactly. This is why C2's 7-day search and C5's 30-min post-deploy search both found 0 hits for these fields — the field names literally didn't exist, not "helper hasn't fired yet" as first assumed. Fixed in both repo copies (kept the promoted top-level names as already communicated; changed only the source-key read), re-validated with 5 new isolated test scenarios using the real key names, and redeployed via a second scoped patch (`gitin-1892-fix-field-names.patch`) — `Configuration OK`, `active (running)`. `Category` and the 6 conditional fields (now reading correct source keys) remain at 0 live hits — genuinely just no matching helper has fired yet in the sampled window; non-blocking follow-up (`ops.md` action 6). The `devs-log-structure.md` inaccuracy itself is flagged as a separate follow-up (`ops.md` action 10), not fixed in this ticket.

**Two notable incidents during deployment prep, both resolved (2026-08-19):**
1. **False alarm on GITIN-1883's deploy state** — while fetching the live VM file, the assistant misread it (a deliberately-stale leading comment led to wrongly concluding `Service`/`Environment`/Sales-unification code was missing from production). It wasn't — confirmed byte-identical to the repo copy. Full writeup in `cloud/events/20260819_gitin1883-config-drift/` (closed, false alarm).
2. **Real secret briefly exposed in a local file** — `vm-live-azure-eventhub-to-graylog.conf` contained the real Event Hub `SharedAccessKey` and storage `AccountKey` in plaintext at one point (file content changed between two reads, cause not established). Confirmed it never reached git (untracked, nothing staged) and never appeared in `gitin-1892.patch`. Redacted immediately. Key rotation flagged as a follow-up (`ops.md` action 9) — full detail in `ops-events.md`.

## Objective

GITIN-1883 (closed 2026-08-18) promoted 4 of the 16 canonical `Properties` fields listed in `cloud/docs/devs-log-structure.md` §9 to top-level Graylog fields for the 6 Event Hub-ingested services (Business, Admin, Platform, Person, Catalog, Orders): `TraceKey`, `TenantId`, `Service`, `Environment` — plus `AppLevel`, which was already flat since GITIN-1835 (not itself a §9 `Properties` key). This ticket promotes the remaining 12 §9 fields, for **both** the 6 Event Hub services and **Sales** (scope expanded 2026-08-19, at explicit user request, from an initial Event-Hub-only draft):

`UserId`, `Component`, `ProcessType`, `Category`, `ErrorCode`, `Operation`, `Recovered`, `Handled`, `AuditAction`, `AuditOutcome`, `RequestId`, `SourceContext`.

## Relevant prior findings (from GITIN-1883, closed 2026-08-18 — do not re-derive)

- The 6 Event Hub services ingest via Azure Diagnostic Settings → Event Hub → Logstash (`azure-eventhub-to-graylog.conf`). `AppServiceConsoleLogs.resultDescription` is a Serilog CLEF JSON **string** (`{"Timestamp":...,"Level":...,"MessageTemplate":...,"Properties":{...}}`) — everything inside `Properties` is unpromoted and unsearchable as a flat field unless explicitly extracted.
- **Sales is NOT already flat for these 12 fields** — this was true before GITIN-1883, but GITIN-1883 itself changed it: to stop GELF's auto-flatten from producing duplicate `Properties_*` fields once `TraceKey`/`TenantId`/`Service`/`Environment` were promoted bare, GITIN-1883's fix **stringifies** Sales' top-level `Properties` field after extracting those 4. Since then, none of the other 12 fields auto-flatten for Sales anymore — they're only reachable inside that stringified blob. First draft of this ticket incorrectly carried forward the pre-GITIN-1883 assumption that Sales didn't need this fix; corrected before deploy (see below) once the user flagged it.
- Pos remains out of scope: emits 0 `AppServiceConsoleLogs` messages (Windows-hosted, same root cause as GITIN-1811) — flag separately if that changes.
- **Fix location:** the same Ruby block in `cloud-graylog/docs/azure-eventhub-to-graylog.conf`, immediately after the `AppLevel` (GITIN-1835) / `TraceKey`+`TenantId`+`Service`+`Environment` (GITIN-1883) extraction, guarded by the existing `if result_desc.strip.start_with?("{")` check.
- **Two versioned copies of the pipeline file exist in this monorepo** and both need the same edit: `cloud-graylog/docs/azure-eventhub-to-graylog.conf` (primary, confirmed in sync with the VM as of GITIN-1883 close) and `bots/settings/prod-sfcloud-monitoreo/etc/logstash/conf.d/azure-eventhub-to-graylog.conf` (a secondary reference copy GITIN-1883 found stale — missing both the GITIN-1835 and GITIN-1883 blocks entirely — and brought up to date manually). That second file also currently has an unexplained uncommitted change on its 2 credential lines (placeholder → literal `"NO"`) that GITIN-1883 left as-is per user direction — not to be touched by this ticket either, unrelated.
- **Deployment pattern:** never copy/scp the whole file (VM has real credentials on 2 lines, repo has placeholders) — generate a scoped `patch` against the real VM file content (`cat` via SSH, not a local reconstruction — GITIN-1883's first patch attempt failed for using a local reconstruction instead), dry-run, apply, `logstash -t --path.settings /etc/logstash`, restart, then verify on live traffic via `_exists_:<field>` through the Views Search API. All SSH/patch/restart commands go through the user (copy-paste) — never run directly, per project rule.
- **3 Graylog Pipeline Rules from GITIN-1835 broke** when GITIN-1883 unified Sales' naming, because they referenced the literal `Properties_Service`/`Properties_Environment` field names. None of the 12 fields in this ticket's scope are currently referenced by name in any known Graylog Pipeline Rule, but worth a quick check before deploy in case something downstream depends on their absence/nesting.
- GITIN-1883 action item #9 (update `cloud/docs/graylog-log-fields.md`'s "Known naming inconsistency" section) is still open — this ticket should fold that update in rather than leave a second stale doc-update item, since both tickets touch the same doc.

## Field-by-field context (`devs-log-structure.md` §3.2/§3.3/§3.5) — not all 12 are universal

The fix needs two different guard strategies, because these fields split into two groups:

| Field | Origin (doc §) | Present whenever the log is HTTP/helper-scoped at all? |
|---|---|---|
| `UserId` | EnrichmentMiddleware scope (§3.2) | Yes — every HTTP-scoped request log |
| `Component` | EnrichmentMiddleware scope (§3.2) | Yes — every HTTP-scoped request log |
| `ProcessType` | EnrichmentMiddleware scope (§3.2) | Yes — every HTTP-scoped request log |
| `Category` | Helper scope (§3.3) | Yes — every helper-emitted log (`Business`/`System`/`Error`/`Security`); absent on raw framework/Kestrel logs |
| `SourceContext` | Automatic MEL (§3.5) | Yes — virtually every log |
| `RequestId` | Automatic MEL (§3.5) | Yes — any log inside the HTTP pipeline (controller or framework) |
| `ErrorCode` | `LogDomainError` only (§3.3) | **No** — only `Category=Error` via that specific helper |
| `Operation` | `LogTransientFailure` / `LogUnrecoverableFailure` (§3.3) | **No** — only those two helpers |
| `Recovered` | `LogTransientFailure` (§3.3) | **No** — only that helper |
| `Handled` | `LogUnrecoverableFailure` (§3.3) | **No** — only that helper |
| `AuditAction` | `LogSecurityAudit` (§3.3) | **No** — only `Category=Security` |
| `AuditOutcome` | `LogSecurityAudit` (§3.3) | **No** — only `Category=Security` |

Implication for the fix: the "always present when scoped" fields can reuse GITIN-1883's exact guard pattern (leave unset if empty string). The conditional fields need a guard against the **key being entirely absent** from the parsed `Properties` hash, not just empty — GITIN-1883 never needed that distinction because `TraceKey`/`TenantId`/`Service`/`Environment` are all always-present-when-scoped fields too.

**Correction from real samples below: `Category` was originally placed in the "always present when scoped" row above based on the doc alone — real data shows it behaves like the conditional group instead** (see Confirmed findings). Table above is theory-only from the doc's §3.2/§3.3, kept as-is for traceability; the actual 2-group split to build the fix from is in "Confirmed findings" and "Open questions" below.

## Confirmed findings (2026-08-19, real messages via `scripts.sh` C1, one plain `AppServiceConsoleLogs` message per service, saved to `field-samples/plain-*.json`)

| Field | Business | Admin | Platform | Person | Catalog | Orders |
|---|---|---|---|---|---|---|
| `Component` | `Api` | `Web` | *(not in this sample)* | *(not in this sample)* | `Api` | `Api` |
| `ProcessType` | `Api` | `Api` | *(not in this sample)* | *(not in this sample)* | `Api` | `Api` |
| `UserId` | present, `""` | present, `""` | present, `""` | present, `""` | present, `""` | present, `""` |
| `SourceContext` | present | present | **absent** | **absent** | present | **absent** |
| `RequestId` | present | present | present | present | present | present |
| `Category` | absent | absent | absent | absent | absent | absent |

- **`Component` doesn't match `devs-log-structure.md`'s documented example.** The doc's §3.2 table shows `Component` as a business-domain name (`"Sales"`) set via the `component` parameter of `UseSmartFranLogEnrichment`. Real values observed are `Api` (5/6 services) and `Web` (Admin) — looks like the app's actual `component` parameter value differs from what the doc's example implies, not a pipeline issue. Flag in the ticket as a discrepancy to confirm with Dev — not assumed root cause.
- **`Category` was absent in all 6 samples.** Consistent with theory: none of the sampled messages went through the 6 canonical `SmartFranLogExtensions` helpers (`LogBusinessEvent` etc.) — they're plain `ILogger` calls (`MessageTemplate` like `"MoneyWarehouseValueRoleServices:GetAllAsync"`, `"RequestHandlingMiddleware: {...}"`). This means `Category` itself — supposedly in the "always present when helper-scoped" group — needs its own targeted sample, same as the 6 conditional fields; it was miscategorized in the original two-group split above. Re-classify: only `UserId`, `ProcessType`, `Component`, `RequestId` are confirmed present regardless of whether a helper fired; `Category` behaves like the conditional group (needs a helper-emitted log to appear at all).
- **`SourceContext` was inconsistent** (3/6 present) on this single-sample-per-service pull — inconclusive with n=1 per service, not yet a confirmed gap.
- These samples also carry a raw `Authorization: Bearer <JWT>` header string and full user-agent/IP metadata inside the *unpromoted* `RequestHandlingMiddleware` message body (nested inside `resultDescription`) — expected (App-side `LogRedactor` only redacts known sensitive property **keys**, and `Headers.Authorization` is logged as a raw dictionary dump by that specific middleware, not through the 6 canonical helpers). Out of scope for this ticket (this ticket only promotes existing canonical `Properties` keys, doesn't touch what the app already logs), but worth flagging as a separate finding for whoever owns `RequestHandlingMiddleware` — full bearer tokens are sitting in `resultDescription` today, before and regardless of this ticket's fix.

## `resultDescription` query methodology (resolved 2026-08-19)

`resultDescription` is a genuine top-level Graylog field (confirmed via a full raw message dump — not just nested inside `event_original`), but it's **keyword-mapped, not analyzed/tokenized**. Debug sequence:

1. Wildcard search (`resultDescription:*ErrorCode*`) failed cluster-wide with `query_shard_exception` on every marker — root cause: this cluster disables leading wildcards (`*`/`?` as the first character), a Lucene `ParseException` OpenSearch reports as a generic "Failed to parse query".
2. A plain unwildcarded term (`resultDescription:TraceKey`) also returned **0 hits** even though `TraceKey` is definitely present (confirmed via a real raw message pasted by the user) — this proved the field isn't tokenized, so no substring term-match is possible at all, wildcards or not.
3. A **regex query** (`resultDescription:/.*TraceKey.*/`) returned real hits (97,306 on Business alone, 7d) — regex isn't subject to the leading-wildcard restriction and works correctly against keyword fields. This is the query form to use going forward for any `resultDescription` substring search.

`scripts.sh` C2 updated to use `resultDescription:/.*${marker}.*/` for the 6 conditional-field markers.

## Additional confirmed sample (2026-08-19, Person + Business, via regex probes)

A `RequestHandlingMiddleware` log from Person (pasted directly by the user) and a repository-class log from Business (from the regex probe) both reconfirm the 4-field always-present group (`UserId`, `ProcessType`, `Component`, `RequestId`) and reinforce that `SourceContext`/`ActionId`/`ActionName` presence is genuinely inconsistent **within the same service**, not just across services: Business's own `RequestHandlingMiddleware` messages lack `SourceContext`, while Business's repository-class messages (`MoneyWarehouseValueRoleServices:GetAllAsync`, etc.) have it. Person's `RequestHandlingMiddleware` sample also lacks it. Confirms `SourceContext` belongs in the key-absent-guard group, not the always-present group — consistent with the correction already made above (`Category` and now `SourceContext` both need the absent-key guard, not just empty-string).

## Decision: conditional-field shapes sourced from `devs-log-structure.md` §3.3/§6, live confirmation deferred to post-deploy

Given the methodology above wasn't resolved until several rounds of debugging, and `devs-log-structure.md` already documents exact worked examples for all 6 conditional fields (§6.3 `LogDomainError`, §6.4 `LogTransientFailure`, §6.6 `LogUnrecoverableFailure`, §6.7 `LogSecurityAudit`), the Ruby fix is drafted from the doc's documented shapes. The key-absent guard pattern means this carries no risk if a field turns out rarer than expected in practice — it simply won't promote when the key isn't there. Live confirmation of `ErrorCode`/`Operation`/`Recovered`/`Handled`/`AuditAction`/`AuditOutcome` (via the now-working regex query) is a **post-deploy verification step**, not a pre-deploy blocker — same as `_exists_:<field>` was used in GITIN-1883.

## Open questions / next steps

- Draft the Ruby block extension: two guard patterns — key-absent guard for `Category`, `SourceContext`, `ErrorCode`, `Operation`, `Recovered`, `Handled`, `AuditAction`, `AuditOutcome`; empty-string guard (GITIN-1883's exact pattern) for `UserId`, `ProcessType`, `Component`, `RequestId`.
- Read the existing Ruby block in `bots/settings/prod-sfcloud-monitoreo/etc/logstash/conf.d/azure-eventhub-to-graylog.conf` (in sync with `cloud-graylog/docs/` and the VM as of GITIN-1883 close) to extend precisely rather than reconstructing from memory.
- Post-deploy: re-run C2 (now regex-based) to confirm real hit counts for the 6 conditional fields, plus `_exists_:Category`/`_exists_:SourceContext`/etc. on live traffic, same as GITIN-1883's C5.
- Apply the same edit to both versioned copies of the pipeline file in the same session (missed once in GITIN-1883).
- Fold GITIN-1883's still-open action #9 (`cloud/docs/graylog-log-fields.md` update) into this ticket's closure.
- Same deployment care as GITIN-1883: diff repo vs. VM first, scoped patch (never full-file copy), `logstash -t`, restart, verify via `_exists_:<field>`.
- Apply the same edit to the secondary copy in `bots/settings/prod-sfcloud-monitoreo/etc/logstash/conf.d/azure-eventhub-to-graylog.conf` in the same session, not as an afterthought (missed once already in GITIN-1883).
- Fold GITIN-1883's still-open action #9 (`cloud/docs/graylog-log-fields.md` update) into this ticket's closure instead of leaving it duplicated across two tickets.
