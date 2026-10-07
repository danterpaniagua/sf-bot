# Investigation — route SFC-CodeGenerator-PRO / SFC-ScheduledJobs-PRO / SFC-TicketProcessAsync-PRO console logs to Graylog (GITIN-1946)

**Status:** Terraform applied 2026-08-26 (`gitin-1946.tfplan`, scoped `-target` apply — "Apply complete! Resources: 3 added, 0 changed, 0 destroyed."). Diagnostic Settings live and correctly configured for all 3 targets — **the infra side of this ticket is done and correct.** Not closed, but the blocker is no longer infra: none of the 3 apps' actual code emits data the pipeline can turn into a Graylog message (see "Root cause found" below) — this needs a dev-side fix (or a decision to build Function-App-specific Logstash parsing for whatever they do emit), not further Terraform/pipeline work.

## Objective

Add Diagnostic Settings so three PROD Function Apps' console output reaches Graylog via the existing Event Hub pipeline: `SFC-CodeGenerator-PRO`, `SFC-ScheduledJobs-PRO`, `SFC-TicketProcessAsync-PRO`. Same mechanism already applied to the App Service APIs and to `SFC-PosWasmRelay-PRO`/`-DEV`.

## Key finding — these replace GITIN-1914's Function Apps, not duplicate them

The user's initial ask named these three apps; two of the three names are close to, but not identical to, apps already onboarded under GITIN-1914 (`SmartFranCloudFunctionsScheduledJobs-pro`, `SmartFranCloudTicketProcessAsync-pro`; `SmartFranCloudBusinessFunPro` has no SFC-named counterpart at all). Given this repo's real precedent of naming-assumption incidents (GITIN-1834's full-replace Diagnostic Settings overwrite), names were not assumed — confirmed via `az functionapp list` filtered to `CodeGenerator`/`ScheduledJobs`/`TicketProcess` (2026-08-26, RG `SmartFran.Cloud.PRO`, subscription `85c76dea-3304-4310-8656-bf21b28e4f4b`):

| App | Kind | State |
|---|---|---|
| `SmartFranCloudFunctionsScheduledJobs-pro` (GITIN-1914) | functionapp,linux | **Stopped** |
| `SmartFranCloudTicketProcessAsync-pro` (GITIN-1914) | functionapp,linux | **Stopped** |
| `SFC-ScheduledJobs-PRO` | functionapp,linux | Running |
| `SFC-TicketProcessAsync-PRO` | functionapp,linux | Running |
| `SFC-CodeGenerator-PRO` | functionapp,linux | Running |

**Conclusion:** the two old-style apps have been stopped and replaced by SFC-named apps now carrying real traffic. GITIN-1914's existing Diagnostic Settings on the stopped apps are pointed at dead resources — harmless but stale. The apps actually receiving traffic today had **zero** Diagnostic Settings until this ticket — a real coverage gap, not a duplication. `SFC-CodeGenerator-PRO` has no old-style predecessor at all; genuinely new.

Confirmed no pre-existing Diagnostic Settings on any of the three (`az monitor diagnostic-settings list`, empty for all) before applying — nothing to conflict with.

## Terraform

`cloud-graylog/terraform/function_app_pro.tf` (appended, not a new file — keeps PROD-tier Function Apps together per the file's existing scope) — 3 new resources (`codegenerator_pro`, `scheduledjobs_pro`, `ticketprocessasync_pro_sfc`), default provider (no alias), `var.resource_group_name`, category `FunctionAppLogs` (reused from prior confirmed value for this resource kind — not independently re-verified via Portal for these three specifically).

**Plan drift encountered:** an unscoped `terraform plan` returned `4 to add, 23 to change` — not the expected `3 to add, 0 to change, 0 to destroy`. Traced to pre-existing, unrelated drift already sitting in the working tree (per `20260821_functionapps-prod-to-graylog`'s own flagged-but-unresolved note: 16 uncommitted `metric` block diffs across `app_services.tf`/`app_services_dev.tf`, plus an untracked `service_bus_grido` resource in `service_bus.tf` — not confirmed as the exact 23, `git status` shows further modifications to `main.tf`/`network.tf`/`variables.tf` since that note was written, so the drift set may have grown). Not investigated further or touched this session — applying it was out of scope for GITIN-1946. Resolved by re-planning with `-target` on just the 3 new resources: `3 to add, 0 to change, 0 to destroy`, applied clean.

**`terraform apply "gitin-1946.tfplan"` confirmed:** `Apply complete! Resources: 3 added, 0 changed, 0 destroyed.`

## Resolved — `FunctionAppLogs` does NOT carry `devs-log-structure.md`'s Serilog contract (carried from GITIN-1901, answered 2026-08-26)

Confirmed via `az webapp log tail` against `SFC-CodeGenerator-PRO` while real production traffic was hitting it (85 real invocations/hour, per `FunctionExecutionCount` metric — not artificially triggered). The underlying log source for the `FunctionAppLogs` diagnostic category is Azure's own internal Functions-host event, `MS_FUNCTION_AZURE_MONITOR_EVENT` — a CSV row whose payload is a **Python-dict-style, single-quoted string** (not valid JSON): `appName` (lowercase, e.g. `sfc-codegenerator-pro` — does not match the resource's actual mixed-case name), `roleInstance`, `message` (plain unstructured text — `"Pool: SmartFran-Grido-..."`, `"Executed Functions.X (Succeeded, Id=..., Duration=...ms)"`), `category` (host-level grouping, `Function.<name>.User` vs `Function.<name>` — **not** the app's own `Category` field from `SmartFranLogExtensions`), `functionInvocationId`, `functionName`, `level`, `levelId`, `eventId`, `eventName`.

None of `devs-log-structure.md`'s canonical fields (`Service`, `Environment`, `TraceKey`, `TenantId`, `Category`/`_error_code`/etc. from the 6 helpers) appear anywhere. This function calls plain `ILogger` methods directly, not `SmartFranLogExtensions` — and even if it did, this diagnostic category doesn't carry that schema at all. Caveat: this was confirmed via Kudu's own log-streaming endpoint (`log tail`), a different pipe than Diagnostic Settings → Event Hub — treated as strong evidence for what Diagnostic Settings' `FunctionAppLogs` category forwards (Azure documents this category as sourcing from these same function-execution events), not a byte-for-byte confirmation of the Event Hub payload.

**Not a single "Function App shape" project-wide:** this is now the third distinct raw shape observed across Function Apps in this project — `SFC-PosWasmRelay`'s own relay code produces a custom top-level `Properties` JSON hash (`docs/graylog-log-fields.md`), this is Azure's native Functions-host CSV+pseudo-dict format, and the old GITIN-1914 apps' shape was never confirmed at all (delivery was flagged unverified, and those apps are now `Stopped`). Each Function App's actual output depends entirely on what's calling the logger, not the `FunctionAppLogs` category itself.

**Practical implication:** the existing Logstash pipeline (`azure-eventhub-to-graylog.conf`) was built for the App Service shape (`records[].resultDescription`, valid nested JSON). A single-quoted non-JSON payload very likely fails to parse under that logic.

**Confirmed 2026-08-26 — the literal marker string `MS_FUNCTION_AZURE_MONITOR_EVENT` returns 0 hits in Graylog** (full-text, quoted, 1h and 24h windows, `used_indices: []` both times) — this data isn't reaching Graylog in any form, parsed or raw. Ruled out as causes: (1) Diagnostic Setting misconfiguration — re-verified via full JSON, `FunctionAppLogs: enabled: true`, correct `eventHubName`/`eventHubAuthorizationRuleId`. (2) Logstash consumer stalled — `GET /_node/stats/pipelines` on the Graylog VM shows the `azure_event_hubs` input actively processing (`events.in: 26200`, throughput ~5-6/sec, matching known live traffic; `events.out` for the pipeline exceeds `events.in`, consistent with fan-out to multiple outputs, not drops). (3) Logstash exceptions — `journalctl -u logstash` over the relevant window shows no errors.

## Root cause found — this app never emits the CLEF JSON the pipeline expects, independent of any delivery issue

User hypothesized the devs might be sending logs directly to Graylog, bypassing the Event Hub pipeline. Checked against `cloud/repo/SmartFran.Cloud` (`origin/dev`, pulled fresh 2026-08-26) — **the opposite is true**:

- No active direct-to-Graylog sink. `SerilogStateLoggerSettings` (`Provider.Logger.Serilog`) has `GraylogHost`/`GraylogPort`/`GraylogFacility`/`GraylogUdpEnabled` fields, explicitly commented **"Reservados para uso futuro si se reactiva el sink GELF/UDP"** — present in code, not active. `SerilogStateLogger`'s own constructor comment states the intended path explicitly: `"Console JSON CLEF → stdout → AppServiceConsoleLogs → EventHub → consumer → Graylog"` — same architecture as every other service.
- **This Function App's Serilog pipeline is never invoked for its own business logging at all.** Traced `Program.cs` (`SmartFran.Cloud.Functions.Business.CodeGenerator.LiteEditionV2`): the only logger wired in `ConfigureServices` is `services.AddBusinessLogger(config)` — which, for *this specific project*, has nothing to do with Serilog/console output. It wires `IBusinessLoggerProvider` → `CosmosBusinessLogger` (a business-audit-trail concern writing to Cosmos DB, config-gated). The actual Serilog CLEF pipeline is only reachable via a separate, also config-gated `AddStateLogger`/`IStateLoggerProvider` path — and `Program.cs` never calls `AddStateLogger`. No `.ConfigureLogging(...AddSerilog...)` appears anywhere in the `HostBuilder` chain either.
- Consequence: the plain `ILogger<T>` calls inside `CodeGeneratorGetNextCodeWithLockAsync` (`"Pool: ..."`, `"Lock atómico adquirido..."`, etc.) never touch Serilog. They go through the isolated-worker model's default logging path (gRPC to the Functions host) — which is exactly what produces the `MS_FUNCTION_AZURE_MONITOR_EVENT` shape captured via `log tail`.

**This changes the framing of GITIN-1946 entirely.** It's not a pipeline delivery bug to fix — this app was never wired to emit the CLEF JSON the Diagnostic-Settings→Event-Hub→Logstash→Graylog architecture assumes. Two independent gaps stack here: (1) even if the app emitted CLEF JSON, the Logstash pipeline's JSON-parsing logic is built for the App Service `records[].resultDescription` shape, not whatever a Function App would produce; (2) this app doesn't emit CLEF JSON in the first place. **Confirmed 2026-08-26 — same gap in all three, not specific to CodeGenerator.** Checked `SmartFran.Cloud.Functions.ScheduledJobs` and `SmartFran.Cloud.Functions.Sales.TicketProcessAsync`'s `Program.cs` + `BusinessLoggerExtension.cs`:

- Both call `AddBusinessLogger` (ScheduledJobs: no-arg overload; TicketProcessAsync: same `IConfiguration`-gated overload as CodeGenerator) — in both projects this is the same unrelated `IBusinessLoggerProvider` → `CosmosBusinessLogger` audit-trail concern, not Serilog/console output.
- Neither project calls `AddStateLogger`/`UseSerilog`/`AddSerilog` anywhere (`grep -rn` across each project tree, zero matches for either).

So all 3 GITIN-1946 apps share the identical architectural gap: it's the shared Functions scaffolding pattern (likely copy-pasted across these Function App projects), not a one-off in CodeGenerator specifically.

## Diagnostic Settings configuration re-verified (2026-08-27)

`az monitor diagnostic-settings list` against all 3 targets confirms configuration is correct and
identical across all three: `FunctionAppLogs: enabled: true`, `eventHubName: "app-logs"`,
`eventHubAuthorizationRuleId` pointing to `smartfran-graylog-evhns-pro/.../diagnostic-settings-send`
— matches the Terraform pattern exactly, no drift. All other log/metric categories correctly
disabled. **This confirms the setting exists and is well-formed, not that it's producing anything
useful** — the root-cause finding above (these apps never emit CLEF JSON; `ILogger` calls go through
the isolated-worker gRPC path, not Serilog) still stands and is unaffected by this check.

## Not yet done

1. ~~Confirm the Diagnostic Setting itself is correctly configured~~ — **done, confirmed above (2026-08-27).**
2. Confirm real messages from the 3 new targets actually reach Graylog **in a usable/parsed form** —
   given the root-cause finding, expect either zero messages, or raw unparsed `MS_FUNCTION_AZURE_MONITOR_EVENT`-shaped
   payloads that the current Logstash logic can't turn into a structured message. A correct Diagnostic
   Setting does not resolve this; per the "Graylog Pipeline Mitigations" validation rule, a live
   `_exists_`/doc-count check against Graylog itself is required before this can be called delivering,
   not just a settings-level check.
2. Once real traffic exists, audit one real message per app against `docs/devs-log-structure.md`'s schema — same audit done for PosWasmRelay in `docs/graylog-log-fields.md` — to answer the open structural question above and to know what's actually promotable to top-level Graylog fields.
3. Whether messages land in an existing PRO stream/index or need routing rules of their own — not yet checked.
4. Cleanup candidate, not part of this ticket: GITIN-1914's Diagnostic Settings on the now-`Stopped` `SmartFranCloudFunctionsScheduledJobs-pro`/`SmartFranCloudTicketProcessAsync-pro` are pointed at dead resources. Harmless, but a follow-up ticket could remove them once the new apps are confirmed flowing.
5. The 23-change unscoped drift remains unaddressed — flagged, not touched, decision on whether/when to reconcile it is the user's.

Jira: `https://smartit-ar.atlassian.net/browse/GITIN-1946`
