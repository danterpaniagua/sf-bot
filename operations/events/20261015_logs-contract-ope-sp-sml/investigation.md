# Investigation — 20261015_logs-contract-ope-sp-sml

**Status:** in progress (evidence gathering for a proposal; nothing written to the teams yet)

## Request
User (2026-10-15): "Proposal: OPE <-> SP, OPE <-> SML Logs contract proposal. What we need for observability." Follow-up: "SML its the hard one". No Jira ticket yet for this proposal (ask the user; related: GITIN-1477 "[SP] Mejora Continua Logs", GITIN-2222, GITIN-2229, GITIN-1961).

## What Ops needs from application logs (derived from real cases; SP side measured, SML side partly unknown)
1. One stable service identity field. SP today logs `ServiceName=PlatformService` and `msg_service=platforms-service` (GITIN-2229, C4); an alert filter on the wrong one returned 0.
2. A queryable application level. In SP's Graylog the application level is `msg_level`; Graylog's own `level` is not it (GITIN-2229, C3: `level:FATAL` returned 0 with 62 FATAL lines).
3. FATAL means one thing and every process exit leaves a line before it (GITIN-2222: platform exits via `process.exit(1)` after a FATAL line; concentrador logs none, GITIN-2229 C7).
4. Logging never throws and never changes control flow (GITIN-2222: 63 FATAL lines in 14 h come from errors thrown inside the logging code; the sp-logs scope already forbids log changes that affect control flow).
5. Alertable messages: `[CATEGORY/LEVEL] action` in English with variables in fields (already in `smartfran/sp-logs/docs/logging-standards.md`).
6. Correlation fields (order/branch/platform ids, trace id) and the image tag or task-definition revision on each line to link incidents to deploys (the `:271` link in GITIN-2222 was an inference from dates).
7. Bounded field names (SP's default stream and `sp_platform__50` are at the 1000-field limit, `docs/graylog_infrastructure.md`).
8. No secrets or PII in log lines (SP `10-07-2026_credenciales-expuestas-logs`; SML `.svclog` sample with a customer email and national id, `loyalty/events/20260828_wscg01_zabbix_graylog_onboarding/`).

## SP side (measured)
- Structured JSON on stdout -> Kinesis/Event Hub path -> Graylog `sp_platform__50`; fields `ServiceName`, `msg_service`, `msg_level`, `msg_category`, `msg_message`, `msg_error`, `msg_error_stack`, `msg_timestamp` (GITIN-2229 C3, C4). Standard and levels: `sp-logs/docs/logging-standards.md`. Known gaps: two service-name fields, concentrador has no FATAL line, serialization and sanitizer defects (GITIN-1477 investigation, GITIN-2222).

## SML side (the hard one; code read 2026-10-15 in `loyalty/repo/dev-src-sol-smartloyalty`, branch `main`, HEAD `d38f4fe24`, working tree)
- No logging framework of the usual kind (no log4net/NLog/Serilog references in the `.csproj`/`packages.config` greps). All logging goes through the in-house `SmartFran.Seed.Logging` library (`LoggerFactory.MainLogger`, not in this repo) via the wrapper `Extend/Diagnostic/Common/Logg.cs`: `BeginProcess/EndProcess`, `Info`, `Verbose`, `Warning`, `Error` with an `IDictionary<string,string>` of data. There is no Fatal level in the wrapper, and the wrapper does nothing if `MainLogger` is null.
- Business-rule exceptions are logged at Warning with a free-text message (`BusinessRule-<type>: <message>`); operation names go in a second Info line `[OP] <code>: <name>`. Levels and messages therefore do not follow the SP `[CATEGORY/LEVEL]` convention.
- Sinks are configured per service by `system.diagnostics` trace sources and Unity templates (`Default-Template/SystemDiagnostics-Template.config`, `Unity-Template.config`): `SegmentedXmlTraceListener` writing `.svclog` XML (and, where configured, a delimited-list CSV listener).
- Shipping (GITIN-1961, `loyalty/events/20260828_wscg01_zabbix_graylog_onboarding/investigation.md`): IIS access logs go through NXLog to Graylog; app-level logs on MOBI-01 were shipped from the CSV listener; on WSCG-01 the CSV listener and `svclog.conf` were added and confirmed live on 2026-09-05; the raw `.svclog` XML path on MOBI-01 is a commented-out dead route. The CSV lines arrive in Graylog as separate, uncorrelated messages (a structured-data line with `ErrorId`/`Email`/`UidType`/`UidId`/`Usuario`/`Endpoint` and a separate header line); blank lines were dropped in `svclog.conf`.
- The Graylog server accepts SML text on UDP 1514 through a shared JSON extractor (hMailServer/SMTPRL, ClubSite/IIS) (`docs/graylog_infrastructure.md`).
- Windows Task Operator (`Front/TaskOperatorService`) logs `Logg.Info("Starting Service")` style lines; its scheduling/job outcomes also live in SQL tables (`Sch.Task`), not only in logs (GITIN-2223/2224 context).
- Consequences for a contract: SML cannot be asked for the SP field names without changing a shared library that is outside this repo; fields would have to be produced at the shipping layer (NXLog extractors) or by a small adapter around `Logg`. Whether the `Seed` library source is available to the team was not checked.

## SML in Graylog, measured (C1, `data/c1-run-log-20261015T144043Z.txt`, `data/c1/sml-sample.txt`; 2026-10-15 14:40 UTC, last hour, samples of 500 and 200 messages; only field names, counts and metadata values were read)
- Streams: All events, All system events, Default Stream, `SML_MobileApp`, `SML_WebService`, `SP_Concentrador`, `SP_Lambdas`, `SP_Platform`, `SP_WAFV2`. There is no stream for ClubSite.
- Query `NOT _exists_:msg_service` is not "everything that is not SmartPedidos": 187,828 of its ~242,888 messages in the hour come from source `aws-kinesis-raw-logs` with `ServiceName` PlatformService/ConcentradorService and the fields `http_code`, `http_method`, `http_uri`, `http_elapsed` but no `msg_*` fields. Those are HTTP-style lines from SP, not structured application logs. (Totals were read at slightly different moments; they are not additive.)
- SML senders (`source` is the sender's public IP, not a host name): `4.236.140.206` (7,997 messages/h, `ServiceName=SF-WEBSITE`, `cs-host` the ClubSite management site), `52.234.224.34` (31,649, `SF-CLUBS`), `20.157.109.70` (25,155, `SF-WEBSERVICE`) and `52.186.168.27` (2,771, `SF-WSV2`). Host identity is available only through the IIS field `s-computername` and `s-ip`.
- What SML lines are: IIS W3C access records shipped by NXLog (`SourceModuleName=iis_w3c_mobile`, `SourceModuleType=im_file`; fields `c-ip`, `cs-*`, `sc-*`, `time-taken`, `EventTime`, `s-computername`...) plus a minority from the app trace (`SourceModuleName=svclog_input`, `ServiceType=ServiceLogs`: about 7% of the 200 from `20.157.109.70` and about 6% from `52.186.168.27`) with business fields (`Action`, `BranchOffice`, `BranchOfficeId`, `CloudSaleId`, `LoyaltySaleId`, `ElapsedMS`, `ExecutionTime`, `TotalElapsedMs`, `CacheElapsedMs`, `TimeZoneElapsedMs`, `KeyString`, `BOKeyString`).
- None of the four SML sources has a level, category, version or build field. `ServiceName` is the only identity field; it exists in SML (values `SF-*`) and in SP (`PlatformService`), with different naming styles. `ServiceType` (IIS / ServiceLogs) tells the origin of the line.
- Routing: ClubSite lines (`SF-WEBSITE`, `SF-CLUBS`) land only in the Default Stream (200 of 200 in each sample); `SF-WEBSERVICE` and `SF-WSV2` lines go to `SML_WebService` (111 of 200 and 200 of 200), except the lines that failed processing.
- `gl2_processing_error` is present in 44% of the 200 sampled messages from `20.157.109.70` (89 messages, 89 distinct values; those messages are in the Default Stream, not `SML_WebService`). The cause was not examined (the error values were not read).
- Personal-data-like fields are present in the access-log lines: client IP `c-ip`, `X-Forwarded-For`, geo-enrichment (`src_ip_geo_*`), cookie flags (`csCookie`, `cs_cookie_present`), a `Code` field (81% of the ClubSite sample, 69 distinct values, meaning not checked) and `cs-uri-query`. Values were not read.
- One message in the sample has `msg_level=error` (lowercase): SP's level values may not be uniformly upper case (one occurrence; not investigated).
- Consequence for the contract: today an SML line cannot be filtered by application level or alerted on severity; only HTTP status (`sc-status`), response time (`time-taken`) and the text of the app-trace lines are available. A level/category/version for SML needs either the application (the `Seed` library) or a mapping at the NXLog/Graylog layer.

## The contract already exists: the sp-logs axioms (user, 2026-10-15; read the same day)
- `smartfran/sp-logs/docs/logging-axioms-portable.md` (+ `-spa` Spanish version): 19 stack-agnostic axioms with detect-by-grep and bad -> good examples, a priority order and a validation checklist. Companions: `logging-axioms-dotnet-appendix.md` (.NET Core / `ILogger` evidence from `SmartFran.Cloud`) and `logging-axioms-architecture.md` (ingestion pipeline: one shared channel, service identity as metadata, checkpointed shipper, a default view plus per-service views). Generalised from `docs/logging-standards.md` (SUB-000..SUB-011).
- The axioms: 1 no credentials, 2 no decoded tokens, 3 always a level, 4 always a category, 5 English only, 6 errors include the stack, 7 never log the same failure twice, 8 level matches severity (FATAL only for system-wide failure), 9 PERF always INFO, 10 tracing ids with an `unknown` fallback, 11 the emitting service is injected by the logging layer, 12 no bare console/print, 13 structured message, 14 no file carrying disproportionate logging, 15 normalise non-Error throws, 16 every catch logs, 17 risky code is wrapped in try/catch, 18 no framework-default logging as production signal, 19 no silent fallback.
- They are a producer-side (code) contract: each rule is verified by reading code. They match items 1, 3-5, 8 of the Ops needs above.

## Gaps between the axioms and what GITIN-2222 / GITIN-2229 showed (candidate additions, not yet agreed)
| Ops need | In the axioms? | Evidence |
|---|---|---|
| Logging layer never throws and never changes control flow (safe serialization, correct use of helpers like the sanitizer) | Partly: axiom 15 covers non-Error throws only; the sp-logs scope states "log changes must never affect control flow" but it is not an axiom | `JSON.stringify` circular error and the class called as a function inside the `Log.saveError` arguments (GITIN-2222) |
| Process-level handlers (`unhandledRejection`, `uncaughtException`, service stop) log a FATAL line before any exit, and the exit policy is explicit | No: axioms 16-17 cover try/catch, not process-level handlers; axiom 8 defines FATAL in general | Platform exits via `process.exit(1)` after a FATAL line; concentrador's handlers log nothing and one has a mistyped event name (GITIN-2229 C7) |
| Version/build identifier on each line (image tag, task definition revision, assembly version) | No | the `:271` link in GITIN-2222 was inferred from dates |
| Central-store field contract: one canonical service field, a queryable application level that does not collide with the platform's own `level` (syslog number), bounded field names | Only in the architecture appendix as query examples (`level:<=4` is the syslog level); axiom 11 says the service is injected but not its field name | `ServiceName` vs `msg_service`; `level:FATAL` returned 0 with 62 FATAL lines (GITIN-2229 C3, C4); 1000-field limit (GITIN-1827) |
| Ops-side verification: a Graylog report per field and level instead of reading code | No: every "Detect" is a grep on source | GITIN-2229 C4/C7 are examples of the checks |
| SML: a Fatal level and the use of the same level names | Axiom 3 requires an explicit level among five; `SmartFran.Seed.Logging` via `Logg.cs` has Info/Verbose/Warning/Error and no Fatal | `loyalty/repo/dev-src-sol-smartloyalty`, `Extend/Diagnostic/Common/Logg.cs` |

## Contract design (draft, for discussion with the user)
- Base: the 19 axioms as written (they already have a Spanish version and a validation checklist), not a new document.
- Ops annex ("what must land in the central store"), covering the gaps above: canonical service field, application-level field and the FATAL semantics at process level, version identifier, field-name bounds, and the Graylog-side checks Ops runs.
- Product notes: SP (what the axioms already require + the defects found), SML (the in-house `Seed` logging and the NXLog mapping that would be needed until the library changes), and the SmartCloud stack for reference (`.NET` appendix exists).
- Who owns each change and how often Ops reports compliance.

## Open questions
- Jira ticket and audience (devs, PMs, team leads) for the proposal; whether it belongs to GITIN-1477. The axioms are already the contract; the proposal is the Ops annex that adds what the axioms lack (table above).
- SML: is the source of `SmartFran.Seed.Logging` available and who maintains it? Measured senders in the last hour: ClubSite (SF-WEBSITE, SF-CLUBS), WebService (SF-WEBSERVICE) and WebServiceV2 (SF-WSV2); no sample from the MobileAppService or WebServiceCG senders appeared (not checked why: they may have been outside the 500-message sample). Does SML have a process-level handler policy (service crashes, IIS app pool recycles)?
- Why 44% of one sender's messages show `gl2_processing_error`, and whether the ClubSite lines should go to their own stream.
- Whether the personal-data-like fields in the IIS lines (client IP, `Code`, geo, cookie flags) are an accepted part of the access log or must be excluded by the contract.
- Cloud (SmartCloud / .NET Serilog CLEF schema, `cloud/docs/devs-log-structure.md`) already has a designed schema; whether the contract should adopt it as the base for SML was not decided.
