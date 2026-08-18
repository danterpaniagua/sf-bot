# Investigation — flatten & unify Properties (TraceKey, AppLevel, TenantId, Service, Environment) across all services (GITIN-1883)

**Status:** Closed 2026-08-18 (GITIN-1883). Final scope grew twice from the original ask, both times at explicit user request: (1) extended from 3 fields to 5 (`+Service`, `+Environment`); (2) extended from "flatten for the 6 Event Hub apps" to "unify naming across ALL services including Sales" — Sales previously had these fields accessible but under a `Properties_`-prefixed name (GELF auto-flatten artifact), not bare like the other 6. Final state: all 5 fields are bare, identically-named, top-level fields on every service. Confirmed on real live traffic post-deploy in Business, Platform, Person (Event Hub path) and Sales (direct-GELF path) — zero `Properties_*` fields remaining anywhere. Achieving Sales' unification required also updating 3 Graylog Pipeline Rules from GITIN-1835 that depended on the literal `Properties_Service`/`Properties_Environment` field names — done in the same change, confirmed no regression to Sales' `source`/`name`/stream-routing. Full detail in `cloud/docs/graylog-log-fields.md` (updated) and `ops.md`.

## Objective

GITIN-1883 ("[CLOUD] Hacer Properties flat"), parent/related GITIN-1811 (closed) and GITIN-1835 (closed). User request: Sales already has a "Properties flat" fix in progress; the other services (Business, Pos, Platform, Person, Admin, Catalog, Orders — everything ingested via the Event Hub / Logstash path, not Sales' direct-GELF path) need `TraceKey`, `AppLevel`, `TenantId` promoted to flat top-level fields. Per the user, these three are currently arriving nested inside a `Properties` field on the other services.

## Relevant prior findings (from GITIN-1835, closed 2026-08-14 — do not re-derive)

- **Sales sends via a direct Serilog→Event-Hub CLEF sink**, bypassing Azure Diagnostic Settings' `records` envelope entirely (confirmed at the infrastructure level via the pipeline's `event_original_guard_skipped` tag). Its raw CLEF shape is `{"Timestamp":...,"Level":...,"MessageTemplate":...,"Properties":{...}}` — GELF auto-flattens any nested `Properties` object into `Properties_<Key>` fields with **no pipeline rule needed** for that flattening itself (confirmed via `_exists_:Properties` returning 0 hits across all 10 streams, 7 days — nothing anywhere keeps an unflattened `Properties` object). GITIN-1835's own rules only fixed `message`/`full_message`/`source`/`name`/`resource_group`/`resource_path`/`subscription`/`type` — not `Properties_*` itself, which was already working.
- **The other services (Event Hub path) go through `cloud-graylog/docs/azure-eventhub-to-graylog.conf`.** Azure's own `properties` field (lowercase — a *different* field from Serilog's `Properties`) gets forced to a JSON **string** near the end of the filter chain (`p.to_json`) specifically to avoid OpenSearch mapping conflicts — this stringification means nothing inside it is searchable as a flat field, unlike Sales' auto-flattened `Properties_*`.
- **`AppLevel` already exists as a flat top-level field for the Event Hub path** (GITIN-1835 "segunda entrega") — but it's sourced from Azure's own outer `record["level"]` (a coarse stream-classification string, e.g. `"Informational"`), captured before the generic `record.each` promotion overwrites Logstash's internal `level`. This is a **different** thing from an application-level `AppLevel` that might live inside a Serilog CLEF payload embedded in `resultDescription` — see open question below.
- For `AppServiceConsoleLogs` specifically, the pipeline already parses `resultDescription` as JSON when it starts with `{` (to extract the real app-level severity for `AppLevel`, since Azure's outer `level` is near-always `"Informational"` for this category) — this is the same shape Sales' CLEF messages have (`Timestamp`/`Level`/`MessageTemplate`/`Properties`/...). **If the other services also write Serilog CLEF to stdout**, `TraceKey`/`TenantId`/a real `AppLevel` most likely live inside `resultDescription`'s parsed `Properties` object — structurally the same data Sales gets via direct GELF auto-flattening, just one JSON-string layer deeper because it arrives through `AppServiceConsoleLogs` instead of a direct CLEF GELF payload.

## Confirmed findings (2026-08-18, real messages via `scripts.sh` C1, one `AppServiceConsoleLogs` message per app, saved to `console-logs-samples/`)

| App | Hits | `AppLevel` (top-level) | CLEF `Level` | `TraceKey` | `TenantId` | `Properties.Service` |
|---|---|---|---|---|---|---|
| Sales | 0 | — | — | — | — | — |
| Pos | 0 | — | — | — | — | — |
| Business | 1 | Warning | Warning | `SFCADMWEB.POS:12.2026-08-18T16:18:13.9750000+00:00` | `d3186bc6d7b2` | Business |
| Admin | 1 | Warning | Warning | `f86b3a85639d9a07601104ede861435e` | *(empty)* | Client |
| Platform | 1 | Warning | Warning | `SFCAPI.15.2026-08-18T17:26:59.7644767+00:00` | *(empty)* | Platform |
| Person | 1 | Warning | Warning | `5d955ed85584a9e1fcf9a8ce282a01ba` | *(empty)* | Person |
| Catalog | 1 | Warning | Warning | `SFCADMWEB.POS:1.2026-08-18T17:03:27.2550000+00:00` | `kt76igzny9ql` | Catalog |
| Orders | 1 | Error | Error | `SFCADMWEB.POS:176.2026-08-18T16:23:35.6080000+00:00` | `d3186bc6d7b2` | Orders |

**Sales and Pos: 0 hits, both Windows-hosted — consistent with GITIN-1811** (`AppServiceConsoleLogs` structurally unsupported for .NET on Windows App Service, Microsoft-confirmed). Neither needs this fix: Sales already gets `Properties_*` for free via its direct-GELF CLEF sink's auto-flattening (GITIN-1835); Pos apparently doesn't emit `AppServiceConsoleLogs` at all, same as Sales before its GITIN-1811 workaround — out of scope here, flag separately if Pos needs the same direct-GELF treatment.

**The other 6 services (Business/Admin/Platform/Person/Catalog/Orders) all share the exact same confirmed shape:**
- `resultDescription` is a Serilog CLEF JSON **string**: `{"Timestamp":...,"Level":...,"MessageTemplate":...,"Properties":{...}}`.
- The pipeline already parses this string to populate the top-level `AppLevel` field (GITIN-1835) — **confirmed correct** in all 6 samples (`AppLevel` matches CLEF `Level` exactly, not Azure's generic outer `level`). No change needed for `AppLevel` — it's already flat and already right.
- `TraceKey` and `TenantId` live inside `resultDescription`'s parsed `Properties` object, **not promoted anywhere** — confirmed present (sometimes as an empty string for `TenantId` on system/background messages with no active tenant, e.g. Admin/Platform/Person — real variability, not a bug) in all 6 samples.
- `event_original` field also confirms `properties` (Azure's own lowercase field, a *different* thing from Serilog's `Properties`) is genuinely absent from `AppServiceConsoleLogs` records — nothing to flatten there; the entire finding is scoped to `resultDescription`'s nested CLEF payload.

## Fix

Extend the existing `resultDescription`-parsing Ruby block in `cloud-graylog/terraform/../docs/azure-eventhub-to-graylog.conf` (`AppLevel` extraction) to also promote `Properties.TraceKey` and `Properties.TenantId` to top-level `TraceKey`/`TenantId` fields — same parse, same `if result_desc.strip.start_with?("{")` guard, no new failure mode introduced. `AppLevel` itself needs no change.

## Next steps

- Draft the Ruby filter addition (see `ops.md` / pipeline edit).
- Validate with `logstash -t` before restart, same deployment care as GITIN-1835 (VM live-file drift, brace-loss corruption pattern already documented there).
- Confirm on live traffic post-deploy: `_exists_:TraceKey` and `_exists_:TenantId` across the 6 affected streams.
