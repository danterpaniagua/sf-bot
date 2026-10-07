# Investigation — route SFC-PosWasmRelay-PRO console logs to Graylog via Event Hub + Graylog stream routing (GITIN-1924)

**Status:** in progress, not closed. Azure Diagnostic Setting live, Graylog Pipeline deployed and DEV routing confirmed live (`streams` field + `dev__6` index write, 2026-08-24 15:28 UTC). `TraceKey`/`SourceContext` promotion fix deployed to the shared Logstash pipeline, syntactically validated, not yet confirmed against live post-deploy traffic. **PROD side has an open, unresolved question, not just an untested one:** user confirmed Production code is not actually deployed yet (only Development) — but this session saw 39 messages tagged `Environment:"Production"` that don't cleanly trace to either environment (see "Correction" section below). Do not treat PROD delivery as confirmed working.

## Objective

Add a Diagnostic Setting for the `SFC-PosWasmRelay-PRO` Function App so its console output reaches Graylog via the existing Event Hub pipeline — same mechanism already applied to:

- `SFC-PosWasmRelay-DEV` (GITIN-1901, parent GITIN-1835) — category `FunctionAppLogs` confirmed valid for this resource type/kind (Function Apps expose a different category set than Web Apps: no `AppServiceConsoleLogs`).
- The 3 PROD Function Apps in GITIN-1914 (`SmartFranCloudBusinessFunPro`, `SmartFranCloudFunctionsScheduledJobs-pro`, `SmartFranCloudTicketProcessAsync-pro`) — confirmed live in subscription **SmartIT Cloud** (`85c76dea-3304-4310-8656-bf21b28e4f4b`), RG `SmartFran.Cloud.PRO`.

## Confirmed against live Azure (2026-08-24)

- **Resource exists:** `SFC-PosWasmRelay-PRO`, subscription **SmartIT Cloud** (`85c76dea-3304-4310-8656-bf21b28e4f4b`), RG `SmartFran.Cloud.PRO`, kind `functionapp,linux`, state `Running`. Matches the GITIN-1914 assumption exactly (`az functionapp list`).
- **No pre-existing Diagnostic Settings** — `az monitor diagnostic-settings list` against the resource ID returned `[]`. No conflict risk.

Note per `20260824_pos-wasm-logging-graylog-review/investigation.md`: the GSFC-839 WASM relay *application code* (`SmartFran.Cloud.Pos.Wasm.Relay` / `IngestLogs`) is still `origin/dev`-only as of 2026-08-24, not yet in `main`. This PRO Function App resource exists and is `Running`, but likely has no deployed code yet — same situation GITIN-1901 documented for `SFC-PosWasmRelay-DEV` at the time its Diagnostic Setting was wired (infra ready ahead of code, category will carry no data until something actually logs). Not independently re-confirmed here via `az functionapp function list`.

## Terraform drafted and applied (2026-08-24)

- `cloud-graylog/terraform/function_app_pro.tf` — appended (not a new file, keeps all PRO-tier Function Apps together per GITIN-1914's existing file scope). New `data "azurerm_linux_function_app" "poswasmrelay_pro"` + `azurerm_monitor_diagnostic_setting.poswasmrelay_pro`, default provider (no alias), `var.resource_group_name`, category `FunctionAppLogs`, name `SmartFran.Cloud.PRO.PosWasmRelay_DiagnosticSettings` — mirrors `poswasmrelay_dev` (`function_app_dev.tf`, GITIN-1901) exactly except tier.
- `terraform plan` scoped via `-target` to only this resource + its data source (repo has known pre-existing unrelated drift: untracked `service_bus.tf`, modified `app_services.tf`/`main.tf`/`network.tf` — none touched this session) — saved to `gitin-1924.tfplan`.
- `terraform apply "gitin-1924.tfplan"` confirmed: `Apply complete! Resources: 1 added, 0 changed, 0 destroyed.` Diagnostic Setting is live.

## Graylog stream routing (per user, 2026-08-24)

Existing stream rules keyed on `Service` + `Environment` fields (not the `.*-DEV`/`.*-PRO` `name`-field regex used for the Diagnostic-Settings-sourced App Services/Function Apps in GITIN-1794/1901/1914):

- `Service:"smartfran-pos-wasm"` AND `Environment:"Development"` → Stream `DEV`
- `Service:"smartfran-pos-wasm"` AND `Environment:"Production"` → Stream `PROD-Pos-AppServicePlan`

Not yet independently verified in Graylog's stream/pipeline config by this session (stated by the user, not confirmed via Graylog API/UI).

**`Service`/`Environment` field enrichment confirmed against `origin/dev` source (2026-08-24, after `git pull --ff-only`):**

- Relay process-level baseline (`SerilogBootstrap.ApplyProcessEnrichers`, shared by all APIs/Functions, called from `Pos.Wasm.Relay/Program.cs` with `serviceName: "SmartFran.Cloud.Pos.Wasm.Relay"`): `Service = "SmartFran.Cloud.Pos.Wasm.Relay"`, `Environment = ASPNETCORE_ENVIRONMENT env var ?? "Production"` — this is the relay's own identity for its own operational logs (middleware errors, unhandled exceptions), not the forwarded POS entries.
- Per-forwarded-entry override (`IngestLogs.cs:128`): `LogContext.PushProperty("Service", batch.SourceKey ?? "smartfran-pos-wasm")` — Serilog `LogContext` scope wins over the static process-level enricher, so each POS-forwarded log line is re-tagged `Service:"smartfran-pos-wasm"` specifically (`batch.SourceKey` traces to client-side `WasmLoggingOptions.SourceKey`, default `"smartfran-pos-wasm"` — matches the rule's literal value, no override needed). `Environment` is **not** overridden per-entry — it stays whatever the relay process set at boot.

**Net:** forwarded POS entries land as `Service:"smartfran-pos-wasm"` + `Environment:<relay's own ASPNETCORE_ENVIRONMENT>`. For `SFC-PosWasmRelay-PRO` to route to `PROD-Pos-AppServicePlan`, that app setting must actually be `Production` (or unset, since the code defaults to `"Production"` on a missing var) — **not yet confirmed live against the Azure resource**, only inferred from source defaults.

## Correction — end-to-end delivery already confirmed working (2026-08-24, contradicts earlier assumption)

Graylog Views Search API (`Service:"smartfran-pos-wasm"`, last 30 days, pivoted by `Environment`): **39 messages tagged `Environment:"Production"`, 7 tagged `Environment:"Development"`** (46 total). This contradicts the assumption carried in this file's earlier sections and in `20260824_pos-wasm-logging-graylog-review/investigation.md` that GSFC-839 is `dev`-only with zero code deployed to `SFC-PosWasmRelay-PRO`.

**Confirmed via full-field message fetch** (`_id: c23310a3-9fcb-11f1-8f28-7c1e52beabec`): the message carries `ProcessType:"PosWasm"`, `Component:"Pos"` — an exact match to what `IngestLogs.cs:129-130` stamps on every entry the relay forwards. These are genuinely POS WASM client HTTP-call logs relayed through *some* `SFC-PosWasmRelay-*` instance's `IngestLogs` pipeline. **Which instance, and therefore whether this is real PROD delivery, is now unresolved — see correction below.**

**Correction (2026-08-24, later same session): user confirmed Production code is NOT deployed — only Development.** This contradicts the `Environment:"Production"` tag on the 39 messages above, and directly contradicts a re-check: `az functionapp config appsettings list` against `SFC-PosWasmRelay-DEV` confirms `ASPNETCORE_ENVIRONMENT = Development` (not `SlotSetting`). Per the enrichment trace earlier in this file, `IngestLogs.cs` never overrides `Environment` per-request — it falls through to the relay process's own value — so if these messages came through the DEV relay, they should read `Environment:"Development"`, not `"Production"`. They don't. Also unexplained: the full message sample's own `Uri` field pointed to a `-dev` backend (`smartfran-cloud-business-dev.azurewebsites.net`) despite `Environment:"Production"` — flagged at the time, not chased down.

**Net: root cause of the "Production"-tagged traffic is unresolved.** Not claiming it's actually DEV traffic mistagged, and not claiming it's genuinely PROD — both are contradicted by some piece of evidence. Genuine `Environment:"Development"`-tagged traffic was also observed separately (the burst that confirmed DEV stream routing), so this isn't simply "Environment is always wrong" either. **Do not cite "confirmed PROD end-to-end delivery" as fact anywhere until this is actually resolved** — retracting that claim from this file's earlier framing.

Message content itself: `HTTP "GET" "/api/v1/TypesAllocationFranchise/GetAll" responded 200 in 385.9 ms` — this is the POS Blazor client's own outbound HTTP-call logging (its calls to Sale/Financials/Business-domain APIs), captured by its Serilog HttpClient logging and forwarded via `WasmForwardingSink` → `IngestLogs` → Graylog. Not the `LogBody`/business-log path (Path 1, `ProcessLogger`) — this is operational/HTTP-call telemetry via the GSFC-839 pipeline, exactly this ticket's subject matter.

**Current stream membership confirmed:** `streams: ["000000000000000000000001"]` (Graylog's Default Stream) — none of this traffic is routed anywhere yet. Clean baseline for the routing work below; no pre-existing rule to account for.

## Graylog routing implemented (2026-08-24) — Pipeline Rules, not plain Stream Rules

Scope pivoted to Graylog-side routing itself (Azure Diagnostic Settings plumbing was already done; this is the "check messages and create Streams" phase). Both target streams (`DEV`, `PROD-Pos-AppServicePlan`) already exist as dedicated single-app streams (regex/exact match on `name` field) — since the relay's traffic doesn't share their `name`-based rule value, and Graylog Stream Rules can't express "(existing rule) OR (Service AND Environment)" in one stream (only uniform AND-all or OR-any across all rules), used **Pipeline Rules** (`route_to_stream()`) instead — additive, doesn't touch either stream's existing rules/matching_type.

- Rule `6a8c60ae4814bcaed31a5560` — "GITIN-1924: smartfran-pos-wasm to DEV": `Service=="smartfran-pos-wasm" && Environment=="Development"` → `route_to_stream(name: "DEV")`.
- Rule `6a8c60bf4814bcaed31a559d` — "GITIN-1924: smartfran-pos-wasm to PROD-Pos-AppServicePlan": same condition with `Environment=="Production"` → `route_to_stream(name: "PROD-Pos-AppServicePlan")`.
- Pipeline `6a8c612d4814bcaed31a570b` — "GITIN-1924: POS WASM Service/Environment routing", stage 0, `match: EITHER`, both rules above.
- Connected to Default Stream (`000000000000000000000001`) — the stream all 46 confirmed messages currently land in — via `POST /system/pipelines/connections/to_stream`.

**Connection API quirks hit and resolved:**
- `PUT` on `/system/pipelines/connections/to_stream` → `405 Method Not Allowed`; the correct verb is `POST` despite being a "set full list" operation, not a create.
- First `POST` attempt (including all pre-existing pipeline IDs on Default Stream, to avoid clobbering them) → `"Cannot modify connections for immutable pipeline"`. Default Stream had 2 pre-existing pipelines: `6a452a0d18ebc987b1ca004b` ("Default Routing", `_scope: GRAYLOG_IMMUTABLE_SCOPE` — built-in) and `6a7f29c54814bcaed30c7f9b` ("GITIN-1835 Sales CLEF formatting", `_scope: DEFAULT`, mutable). Fix: **omit immutable-scope pipelines from the payload entirely** — the endpoint only manages mutable pipelines; the immutable one stays connected/active regardless of not being listed. Final successful payload: `["6a7f29c54814bcaed30c7f9b", "6a8c612d4814bcaed31a570b"]`.
- New quirk for this project, not documented anywhere before this ticket — worth remembering for any future pipeline-connection work on this Graylog instance.

## Not yet done

1. ~~Confirm real messages reach Graylog~~ — **done**, confirmed above.
2. **DEV routing confirmed live (2026-08-24 15:28 UTC):** fresh `Environment:"Development"` messages (e.g. `_id: 82260621-9fd0-11f1-8f28-7c1e52beabec`) show `streams: ["000000000000000000000001", "6a7a1b8a34e7b9a985f43cbc"]` (Default + DEV, `6a7a1b8a34e7b9a985f43cbc` confirmed via `GET /streams/{id}` to be titled `DEV`) and are indexed into `dev__6` (DEV's dedicated index prefix, GITIN-1794) alongside the original `graylog_4`. Pipeline rule logic confirmed working end-to-end for the DEV case.
3. **PROD routing/delivery status is genuinely unresolved, not just untested.** User confirmed Production code isn't deployed. `SFC-PosWasmRelay-DEV`'s `ASPNETCORE_ENVIRONMENT` is confirmed `Development` via live `az functionapp config appsettings list` — so the earlier 39 `Environment:"Production"`-tagged messages don't cleanly trace to the DEV relay either (their `Environment` should have read `Development` per the enrichment trace, and didn't). Root cause not identified. Do not check "PROD routing confirmed" off this list until the source of that traffic is actually explained.
4. Confirm the `ASPNETCORE_ENVIRONMENT` app setting on the live `SFC-PosWasmRelay-PRO` resource itself (not the DEV one, already checked in item 3) — not yet independently checked.
5. Correct the stale "GSFC-839 is `dev`-only, zero PRO code" claim in `20260824_pos-wasm-logging-graylog-review/investigation.md` — out of scope for this file to edit directly (separate investigation), flag to the user.

## Promoted fields audit — SFC-PosWasmRelay traffic (2026-08-24)

Full detail written to `cloud/docs/graylog-log-fields.md` (new "`SFC-PosWasmRelay-PRO`/`-DEV` traffic" section) — summary: `Service`/`Environment`/`TenantId`/`ProcessType`/`Component`/`Version`/`AppLevel` are already promoted to bare top-level Graylog fields, with zero pipeline changes, because the relay's raw shape incidentally matches Sales' direct-GELF shape (`Properties` as a live top-level Hash) rather than the Event Hub apps' `resultDescription`-nested shape — confirmed by reading the actual deployed Logstash filter (see below). `TraceKey`/`SourceContext` are **not** promoted — they're nested one level deeper, under `Properties.EntryProperties`, which the existing Sales-branch guard doesn't reach. Fixing that needs a real Logstash filter change (new `EntryProperties` fallback) or a Graylog-side Pipeline Rule parsing the stringified `Properties`/`event_original` field — not attempted, flagged as an open follow-up. Also found: `TenantId` on this traffic is an Auth0 `org_id`-shaped string (`org_g4qPlLbxcJZx5e7U`), not the 12-char opaque hash every other service uses — not yet raised with dev.

**Local reference copy of the Logstash config was stale — re-synced from production (2026-08-24).** `cloud-graylog/docs/azure-eventhub-to-graylog.conf` was out of date against the actual deployed `/etc/logstash/conf.d/azure-eventhub-to-graylog.conf` on `smartfran-graylog-pro` (fetched via SSH, user ran `gadmin@sfcloud-monitoreo.smartfran.com:5689`). Two anomalies found in the live file, unrelated to this ticket's core scope, not investigated further this session:

1. ~~`event_hub_connections`/`storage_connection` are literally `"NO"` in the on-disk live file~~ — **resolved, not an anomaly.** Per the user (2026-08-24): they substituted `"NO"` for the real values themselves while fetching the file into this repo, specifically to comply with `bots/CLAUDE.md`'s rule against writing real secrets into any repo file. The actual live file on the VM retains the real values — confirmed indirectly by this session's own Logstash restart (C16) working cleanly and real traffic continuing to flow immediately after, which wouldn't happen if the live input block actually held `"NO"`. Only the local reference copy is redacted, correctly and intentionally.
2. ~~The `AppLevel`/GITIN-1883/GITIN-1892 blocks exist twice~~ — **retracted, was a misread.** Re-reading the full synced file end-to-end: each block appears exactly once. The `git diff --stat` showing `-2/+185` reflected the *old local reference copy* having a truncated/stub version of that section, not the live file having a duplicate. No actual drift here beyond the local copy being stale (now fixed by the sync).

Anomaly 1 (`"NO"` connection strings) resolved — see correction above.

## TraceKey/SourceContext promotion fix drafted (2026-08-24, GITIN-1924)

Added a new dedicated Ruby filter block to `cloud-graylog/docs/azure-eventhub-to-graylog.conf` (local reference copy, inserted before the final `properties`-normalization block) — a pure fallback that reads `Properties.EntryProperties.TraceKey`/`.SourceContext` only when the existing GITIN-1883/1892 logic left those fields unset, strips a literal wrapping `"` character the WASM client's serialization leaves on each `EntryProperties` value, and no-ops for every other service (none have an `EntryProperties` key).

**Deployed 2026-08-24 15:54 UTC.** Applied via a scoped unified diff (`patch -p1`, single hunk, zero deletions — confirmed pure insertion, input section with the live `event_hub_connections`/`storage_connection` values left byte-for-byte untouched) rather than a whole-file overwrite, specifically to avoid the `"NO"`-placeholder risk above. Sequence: `patch --dry-run` (clean) → real `patch` → `logstash -t` (`Configuration OK`) → `systemctl restart logstash` → `systemctl status` confirmed `active (running)`, fresh start matching the restart time. **Not yet confirmed against live post-restart traffic.** Checked twice (5-min and the full ~1h43m window since restart, up to 17:37 UTC): zero `Service:"smartfran-pos-wasm"` messages either way. Ruled out a restart regression — a `Service`-pivoted count of the last 5 min shows Logstash healthy overall (8,857 messages across Sales/Orders/Business/Platform/Person/Catalog/Client), just none tagged `smartfran-pos-wasm` in that window. Consistent with the relay's known bursty pattern (sporadic POS activity vs. the backend APIs' constant traffic), not a sign anything broke. **Re-check on the next real burst** — same query pattern as before, now also requesting `TraceKey`/`SourceContext` in the fields list.

Jira: `GITIN-1924`
