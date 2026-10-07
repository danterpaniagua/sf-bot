# Investigation — Parametrize Sales HTTP request-finished fields in Graylog (GITIN-1940)

**Related, same Jira ticket:** `cloud/events/20260826_appservicehttplogs-stream-split/` — follow-on work under this same GITIN-1940 ticket, splitting `AppServiceHTTPLogs` into dedicated per-app Streams/Index Sets once the field promotion here made that category's verbosity worth addressing. Kept as a separate local investigation file since it's a different technical concern (Graylog stream/index config, not Logstash filter promotion).

**Not an incident.** Task: make the ASP.NET Core "Request finished" hosting-diagnostics log line's fields (`StatusCode`, `Path`, `Method`, `ElapsedMilliseconds`) queryable/structured in Graylog, so patterns like Sales `WsFeAr/CaeRequest` 408s can be found by metrics/field queries instead of full-text search. Same shape as the GITIN-1883/1892 field-promotion tickets, not a root-cause investigation.

## Sample message that prompted this (Sales-PRO, 2026-08-25, pasted by user)

```json
{"Timestamp":"2026-08-25T12:26:27.2611346-03:00","Level":"Information","MessageTemplate":"Request finished HTTP/1.1 POST https://smartfran-cloud-sales-pro.azurewebsites.net/api/v1/WsFeAr/CaeRequest application/json 465 - 408 - application/problem+json;+charset=utf-8 3066.0851ms","Properties":{"ElapsedMilliseconds":3066.0851,"StatusCode":408,"ContentType":"application/problem+json; charset=utf-8","ContentLength":null,"Protocol":"HTTP/1.1","Method":"POST","Scheme":"https","Host":"smartfran-cloud-sales-pro.azurewebsites.net","PathBase":"","Path":"/api/v1/WsFeAr/CaeRequest","QueryString":"","HostingRequestFinishedLog":"...","EventId":{"Id":2},"SourceContext":"Microsoft.AspNetCore.Hosting.Diagnostics","RequestId":"40002bf4-0000-d500-b63f-84710c7967bb","RequestPath":"/api/v1/WsFeAr/CaeRequest","TraceId":"cba1e881098b5ce7df25f8189e15efd9","ParentId":"77bea89e1689db3c","Service":"Sales","Environment":"Production","Version":"1.0.0+e4bc8a455300b2b966d31bc8f6545d5ed7813767","TraceKey":"SFCPOS.POS:250.2026-08-25T15:26:19.7630000+00:00","SpanId":"2bed531ef0bfa60e","TenantId":"org_z72xsKwcFsVLHF3c","ProcessType":"Api","Component":"Sales"}}
```

This is the ASP.NET Core built-in hosting-diagnostics "request finished" log line (`SourceContext: Microsoft.AspNetCore.Hosting.Diagnostics`), not an app-authored log via `SmartFranLogExtensions`.

## Gap found (against `cloud/docs/graylog-log-fields.md`, pre-change)

Confirmed **promoted, bare top-level, structured-queryable** for Sales at the time: `Service`, `Environment`, `TenantId`, `TraceKey`, `Version`, `ProcessType`, `Component`, `RequestId`, `SourceContext`, `AppLevel`.

**Not promoted:** `Path`/`RequestPath`, `StatusCode`, `Method`, `ElapsedMilliseconds`, `ContentType`, `Protocol`, `Host`. Per the doc's Sales pipeline description, Logstash only extracted `TraceKey`/`TenantId`/`Service`/`Environment` (plus GITIN-1892's 13) to bare fields, then stringified the leftover `Properties` — so these HTTP-specific fields were only reachable via full-text search over `message`, not structured queries or metrics aggregation.

## Change made (2026-08-25)

Added a new Logstash filter block to `cloud-graylog/docs/azure-eventhub-to-graylog.conf` (the canonical, kept-in-sync copy of the deployed pipeline config — separate repo, `~/Documentos/git/cloud-graylog/`), promoting 4 fields to bare top-level, same two-branch pattern (Event Hub apps / Sales direct-GELF) as every other block in this pipeline:

| Field | CLEF source key | Type |
|---|---|---|
| `StatusCode` | `Properties.StatusCode` | Integer |
| `Path` | `Properties.Path` (`RequestPath` duplicates it, not separately promoted) | String |
| `Method` | `Properties.Method` | String |
| `ElapsedMilliseconds` | `Properties.ElapsedMilliseconds` | Float |

Scoped to the ASP.NET Core "Request finished" line specifically (framework hosting-diagnostics logging, present on every HTTP request) — not gated on `SourceContext` in the filter itself (same nil-safe pattern as the rest of the pipeline: absent/wrong-type keys simply don't promote), but that `SourceContext` value is what identifies which messages actually carry these keys.

Applied to both source shapes for consistency with how every other field group in this pipeline is promoted (Event Hub apps + Sales), even though the message that prompted this was Sales-specific — the same framework request-logging line is emitted by all ASP.NET Core services (Linux Event Hub apps too), not just Sales.

**Generic, not CaeRequest/408-specific.** The block has no service/endpoint/status-code filter — it promotes these 4 fields for every "Request finished" line that carries them, any status code, any path, any method, across Sales + the 6 Event Hub apps (Pos stays out of scope, same `AppServiceConsoleLogs`-unsupported-on-Windows limitation as the rest of this pipeline, GITIN-1811). `StatusCode:500`, `Path:"/api/v1/Sale/Close"`, `Method:GET`, etc. all become valid structured filters fleet-wide once deployed, not just this one sample.

Also updated `cloud/docs/graylog-log-fields.md`: new tracked-fields section, `_exists_` reference block, changelog header, related-tickets entry — marked **deployed, not yet observed live** pending the post-deploy verification below.

## Deploy — not yet done, pending user action

Per this repo's own convention (`cloud-graylog/CLAUDE.md`, `operations/events/20260701_logstash-deployment/`), Claude never runs deploy/restart commands — copy-paste for the user, run on `sfcloud-monitoreo.smartfran.com`. Script/commands recorded in `scripts.sh` in this folder.

**Deploy method — targeted insert, not full-file overwrite.** The local `cloud-graylog/docs/azure-eventhub-to-graylog.conf` copy has its Event Hub/Storage connection strings redacted to `"NO"` (this repo's own convention, no real secrets committed) — the live file on the VM has the real values substituted in. Scp'ing the local copy over the live file would overwrite those and break ingestion fleet-wide. `scripts.sh` instead has the user paste just the new Ruby block directly into the already-deployed file on the VM (before the GITIN-1924 block), with a backup step first.

## Verification — after deploy

Graylog full-text/field queries, 15-30 min post-restart, general traffic (any service):

```
_exists_:StatusCode
_exists_:Path
_exists_:Method
_exists_:ElapsedMilliseconds
```

Then the original ask — the Sales `WsFeAr/CaeRequest` 408 pattern, now structured-queryable instead of full-text-only:

```
Service:Sales AND Environment:Production AND Path:"/api/v1/WsFeAr/CaeRequest" AND StatusCode:408
```

## Extension (2026-08-26) — same fields, second source shape: AppServiceHTTPLogs

User pointed out a second Azure-native log category carries the same information under different key names — Azure's own `AppServiceHTTPLogs` diagnostic category (infra-level HTTP access log, Windows Event Hub apps only, distinct from the app-level ASP.NET Core "Request finished" line above). Confirmed via a real `SMARTFRAN-CLOUD-PERSON-PRO` sample pasted by the user, 2026-08-26:

```json
{"CsHost":"smartfran-cloud-person-pro.azurewebsites.net","CIp":"20.42.109.76","SPort":"80","CsUriStem":"/api/v1/Person/GetByCloudCode/b274c2341fff4defb20a3de37b7f85d5","CsUriQuery":"","CsMethod":"GET","TimeTaken":11,"ScStatus":"200","Result":"Success",...}
```

nested inside the event's top-level `properties` (lowercase) field — which arrives as a JSON-encoded **string** directly from Azure for this category (confirmed from the sample), not a nested Hash like `AppServiceAppLogs`/`AppServiceConsoleLogs`'s `resultDescription`. No collision with the existing `Properties` (capital P) branches — different field name entirely.

**Added as a third branch to the same GITIN-1940 Ruby block** (not a separate ticket — same 4 field names, unified per the user's explicit ask so cross-category queries work uniformly):

| Unified field | AppServiceHTTPLogs source key | Cast applied | Why |
|---|---|---|---|
| `Method` | `CsMethod` | none (already String) | |
| `Path` | `CsUriStem` | none (already String) | |
| `StatusCode` | `ScStatus` | `.to_i` | Azure emits this as a numeric string (`"200"`), not an Integer like the Request-finished line's `Properties.StatusCode` |
| `ElapsedMilliseconds` | `TimeTaken` | `.to_f` | Azure emits this as an Integer (ms); cast to Float to match the Request-finished line's `Properties.ElapsedMilliseconds` type and avoid a mixed int/float field in OpenSearch |

Not promoted from this source: `CsUriQuery`, `CsHost`, `Protocol`, `Result`, etc. — same "4 fields only" scope as the original block, not every field in `properties`.

**Also added: `ClientIP`** (from `CIp`, same AppServiceHTTPLogs branch). No equivalent in either of the other two branches — the ASP.NET Core "Request finished" CLEF line does not carry a client IP property at all (confirmed against the original Sales sample at the top of this file: no IP-shaped key anywhere in its `Properties`). So `ClientIP` only ever populates for AppServiceHTTPLogs-sourced entries, unlike the other 4 fields which populate from two sources.

**Scope, unconfirmed:** whether Pos emits `AppServiceHTTPLogs` at all hasn't been checked — Pos's known gap is specifically `AppServiceConsoleLogs` (GITIN-1811, unsupported on Windows/.NET), a different diagnostic category. Not assumed in or out of scope here.

Local files updated to reflect this before any deploy happened (nothing had been applied to the live VM yet at this point): `cloud-graylog/docs/azure-eventhub-to-graylog.conf` (third branch added to the GITIN-1940 ruby block), `cloud/docs/graylog-log-fields.md` (table + changelog + header). Deploy patch below regenerated to include this addition in the same single deploy — no second round-trip to the VM.

## TenantId format anomaly (flagged, not investigated — unrelated to this task)

Sample's `TenantId` is `org_z72xsKwcFsVLHF3c` — an Auth0 `org_id`-shaped string. Every other confirmed-live Sales `TenantId` sample in `graylog-log-fields.md` (GITIN-1883, post-deploy) is a 12-char opaque hash (e.g. `d3186bc6d7b2`). Not chased further here — noted for whoever next touches Sales `TenantId` handling.

## Related local investigation (verified on disk, 2026-08-25 — background/motivation only, not re-opened)

`cloud/events/20260823_pos-salesorder-delay-cac/investigation.md` (GITIN-1917, WEISS/Canning) independently measured `WsFeAr/CaeRequest` via `AppRequests` telemetry for 2026-08-22: 374 calls, avg 2,355ms, max 11,228ms — and left "confirm whether this latency is AFIP-side vs. SmartFran's own WSAA/CMS signing step" as an unresolved next step. This ticket doesn't resolve that question — it just makes the 408 pattern (a plausible tail-end symptom of that same latency, not confirmed causally linked) queryable going forward.

## Deploy — done (2026-08-26)

Patch applied via `gitin-1940.patch` (local file, this folder) over non-interactive SSH per `scripts.sh`. `logstash -t` returned `Configuration OK`; `systemctl restart logstash` succeeded; `systemctl status` confirmed `active (running)`, `Event Hub registration complete`, `Event Hub is processing events...` (the `WARN`/`onConnectionError` lines right after restart are normal Azure Event Hubs client reconnection churn on startup, not a crash indicator).

## Post-deploy verification — partial (2026-08-26)

Real live sample pasted by user, `SMARTFRAN-CLOUD-PLATFORM-PRO`, `_id: e90be6d1-a146-11f1-8f28-7c1e52beabec`, 2026-08-26T12:08:55Z:

- **`StatusCode`: 200** — confirmed live, top-level.
- **`ElapsedMilliseconds`: 114.2319** — confirmed live, top-level.

Note: this sample's `SourceContext` is `System.Net.Http.HttpClient.Auth0.LogicalHandler` ("End processing HTTP request..." — an outgoing HttpClient call log), not the ASP.NET Core "Request finished" hosting-diagnostics line that motivated this ticket. It carries the same `Properties.StatusCode`/`Properties.ElapsedMilliseconds` keys, so this confirms the Event Hub apps branch of the block fires correctly on any message with those keys — consistent with the block's designed-generic, not-gated-on-SourceContext scope (see "Change made" section above) — but is not itself a "Request finished" sample.

**`Path`/`Method` confirmed live (2026-08-26)** — Views Search API query `SourceContext:"Microsoft.AspNetCore.Hosting.Diagnostics"`, last 1h, top 5 by timestamp: 788 total matches, all 5 sampled messages carry both fields correctly, e.g. `"Path": "/api/v1/Status/Health"`, `"Method": "GET"` (Sales-PRO `_id: 3c816921-...`, Sales-DEV `_id: 2ff9dc51-...`, Sales-PRO-STG2 `_id: 3c886e01-...`). `StatusCode`/`ElapsedMilliseconds` reconfirmed on these same actual "Request finished" lines too, not just the earlier HttpClient-log proxy sample.

Incidental finding, out of scope for this ticket: a `smartfran-cloud-sales-pro-stg2.azurewebsites.net` host appears in these samples with `source: "unknown-service"` and no `Service`/`Environment`/`Component` fields at all (unlike the regular Sales-PRO/-DEV samples) — an apparently untagged staging instance. Not investigated further here; flagged for whoever next touches Sales service inventory.

**`ClientIP` confirmed live (2026-08-26)** — Views Search API query `category:AppServiceHTTPLogs`, last 1h, top 5 by timestamp: 5770 total matches. All 5 sampled messages (Admin-PRO ×3, Platform-PRO, Orders-PRO) carry `ClientIP` correctly, e.g. `"ClientIP": "13.86.97.224"` matching the source `CIp`. Same samples also reconfirm `StatusCode` (correctly cast Integer from the source's numeric string, e.g. `"ScStatus":"200"` → `"StatusCode": 200`), `Path` (from `CsUriStem`, e.g. `/Health`, `/api/v1/Queue/Heartbeat`), `Method` (from `CsMethod`), and `ElapsedMilliseconds` (correctly cast Float from the source's Integer, e.g. `"TimeTaken":3` → `"ElapsedMilliseconds": 3.0`) — all working as designed on the `AppServiceHTTPLogs` branch, not just the "Request finished" branch.

**All 5 fields (`StatusCode`/`Path`/`Method`/`ElapsedMilliseconds`/`ClientIP`) now confirmed live across both source branches.** GITIN-1940 verification is complete.

Incidental finding, out of scope: the Orders-PRO sample's `/api/v1/Queue/Heartbeat` HTTP call carries `Referer: https://grido.pos.smartfran.com/` — confirms real POS traffic flowing through this endpoint, not investigated further here.

## Next steps

1. Optionally: frequency/tenant-scope check on the `WsFeAr/CaeRequest` 408 pattern now that it's a structured query, to inform whether it also needs a Graylog alert (separate follow-up, not assumed in scope here).
2. Close the Jira ticket once the user confirms no further verification is needed.
