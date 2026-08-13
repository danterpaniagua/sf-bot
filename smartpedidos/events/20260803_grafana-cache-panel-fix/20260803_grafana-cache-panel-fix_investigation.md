# Investigation — 20260803_grafana-cache-panel-fix

**Status:** converged — root cause confirmed and fixed, verified working

## Purpose

Diagnose and fix a Grafana panel ("MongoDB: Cache", dashboard on `monitoreosp.smartfran.com`) failing with a generic `Metric request error` (HTTP 500) when querying WiredTiger cache usage for the `PedidosSmartfran` MongoDB Atlas cluster. Tracked as [GITIN-1748](https://smartit-ar.atlassian.net/browse/GITIN-1748). Surfaced while building monitoring for the M20 downsize rollback criteria (`20260803_mongodb-downsize-m20`, [GITIN-1741](https://smartit-ar.atlassian.net/browse/GITIN-1741)), but is a standalone tooling bug, not part of that ticket's scope.

## Confirmed facts

- Panel used the community Grafana datasource plugin `grafana-mongodb-atlas-datasource` (Valiton GmbH / Christoph Caprano), **v1.0.0, published 2019-04-10, no updates since** — confirmed via `GET /api/frontend/settings` (datasource id `2`, name `SmartFran - MongoDB Atlas `). Built for Grafana 6.x, running on Grafana 7.3.7.
- Ruled out as causes (tested and confirmed working): datasource/API key connectivity, `process_measurements` category selection, `database`/`disk` field presence or absence in the target JSON. `NETWORK_BYTES_IN` on the same hosts via the same plugin/category worked correctly throughout — isolating the fault to the specific dimension string `CACHE_USAGE_USED`.
- The client never receives more than `{"message": "Metric request error"}` — confirmed via Grafana's Query Inspector and by replaying the exact query directly against `POST /api/tsdb/query` with a Grafana API key. The plugin backend discards the real Atlas API error before it reaches any client-visible surface.
- **Root cause, confirmed against source + spec:**
  - Plugin source (`src/types.ts`, GitHub `valiton/grafana-mongodb-atlas-datasource`) hardcodes the dimension dropdown list per metric category. For `process_measurements` it includes `CACHE_USAGE_USED` and `CACHE_USAGE_DIRTY`.
  - MongoDB's official Atlas Admin API OpenAPI spec (`mongodb/openapi`, GitHub, `openapi/v2.json`), for the exact endpoint this plugin calls (`GET /api/atlas/v2/groups/{groupId}/processes/{processId}/measurements`), defines the `m` parameter's valid enum as including `CACHE_USED_BYTES` and `CACHE_DIRTY_BYTES` — **not** `CACHE_USAGE_USED`/`CACHE_USAGE_DIRTY`. Those two entries in the plugin's hardcoded list are simply wrong and always were (everything else in the plugin's list, including `CACHE_BYTES_READ_INTO`/`CACHE_BYTES_WRITTEN_FROM`/`NETWORK_BYTES_IN`, matches the real API correctly).
  - Backend Go code (`pkg/datasource/datasource.go`, `HandleProcessMeasurementsQuery`) forwards `query.Dimension.Value` to the Atlas API's `m` parameter with **no local validation** against the hardcoded list — the dropdown is a frontend-only convenience. This meant the fix didn't require patching or redeploying the plugin: hand-editing the panel's JSON model to set `dimensionId: "CACHE_USED_BYTES"` (a value not present in the broken dropdown at all) was sufficient, since the backend passes it straight through.
- **Fix applied and confirmed working (2026-08-03):** panel JSON edited directly via Grafana's "Panel JSON" editor (More ▸ Panel JSON), all 3 replica targets changed from `dimensionId: "CACHE_USAGE_USED"` to `dimensionId: "CACHE_USED_BYTES"` (`dimensionName` updated to match). User confirmed the panel now renders data.
- **Not yet needed, but same bug exists:** `CACHE_USAGE_DIRTY` should be `CACHE_DIRTY_BYTES` if a Dirty-cache series is ever added to this or another panel using this plugin.

## Current working theory

None outstanding — converged. Root cause is fully explained and the fix is verified.

## Ruled out

- Datasource/API key auth or connectivity issue — ruled out, other dimensions (`NETWORK_BYTES_IN`) on the same datasource/hosts worked throughout.
- Wrong metric category (`database_measurements` vs `process_measurements`) — ruled out, both were tried, same failure either way (confirms the category wasn't the issue, though `process_measurements` was correct in the end).
- Stray `database`/`disk` fields in the target JSON confusing the plugin — ruled out, tested present/absent/empty, no effect on the outcome.
- Grafana-side permission/role issue — ruled out for the panel query itself (only `/api/datasources/{id}` config endpoint hit a genuine Viewer-role permission wall, unrelated to the panel failure).

## Why this took as long as it did

Worth recording plainly: this diagnosis was harder than it should have been specifically **because** of the outdated Grafana (7.3.7, released ~2020) and the plugin (v1.0.0, 2019, zero updates since, built against Grafana 6.x). Concretely:
- The plugin backend swallows the real Atlas API error and returns a static `{"message": "Metric request error"}` in all cases — a newer/maintained plugin would be expected to surface the underlying API error, which would have pointed straight at the invalid `m` parameter instead of requiring source-diffing against MongoDB's own OpenAPI spec to find it.
- The dropdown's dimension list is a hardcoded 2019 snapshot with no drift-detection against Atlas's actual API — two of its ~90 entries (`CACHE_USAGE_USED`, `CACHE_USAGE_DIRTY`) were simply wrong, and there's no way to know how long that's been true or whether other panels elsewhere are silently affected.
- None of this is fixable by configuration — it required reading the plugin's Go/TS source directly off GitHub and cross-referencing it against MongoDB's public OpenAPI spec to get a definitive answer, which isn't a reasonable diagnostic path for a routine dashboard issue.

## Open questions / next steps

- None blocking — resolved and verified working. Follow-up worth deciding (see main ticket's "Hallazgos secundarios" and Acción 2): whether to audit other panels on this datasource for the same wrong-dimension-name pattern, and whether to replace/fork this plugin given it's unmaintained since 2019 and actively hides useful error information.
