# Investigation — split AppServiceHTTPLogs into dedicated per-app Streams/Index Sets

**Not an incident.** Task: `AppServiceHTTPLogs` (Azure's infra-level IIS access log, one entry per HTTP request, every app) is too verbose in the shared `PROD-{App}-AppServicePlan` streams — dominating volume alongside `AppServiceConsoleLogs`/`AppServiceAppLogs`. Split it into its own dedicated Stream + Index Set per app, and stop it from also landing in the existing per-app stream.

## Background

- `GITIN-1937` (`cloud/events/20260825_webapps-console-app-http-logs-graylog/`) enabled `AppServiceHTTPLogs` (plus `AppServiceConsoleLogs`/`AppServiceAppLogs`) via Diagnostic Settings for all 8 PRO App Services, 2026-08-25 — this is the change that introduced the volume now being addressed here.
- `GITIN-1940` (`cloud/events/20260825_sales-caerequest-408-timeout/`) promoted `StatusCode`/`Path`/`Method`/`ElapsedMilliseconds`/`ClientIP` to bare top-level fields for both the ASP.NET Core "Request finished" line and `AppServiceHTTPLogs`, 2026-08-26 — made this category's content genuinely useful to query, which is presumably what surfaced the verbosity as worth solving rather than just living with it.
- Existing per-app streams (`PROD-{App}-AppServicePlan`, confirmed live via `GET /streams` 2026-08-26) match on `field: name, type: 1` (exact), one rule per app, `remove_matches_from_default_stream: true`. All diagnostic categories for an app (Console/App/HTTP logs) currently land in the same stream — not split by category.
- Existing index sets follow `SFC-{App}-prod` (e.g. `SFC-Admin-prod`), `index_prefix: "{app}_"` lowercase, description `"SmartFran Cloud {App} PROD"`.

## Naming decided with user (2026-08-26)

- New Stream: `PROD-{App}-AppServiceHTTPLogs` (matches existing `PROD-{App}-AppServicePlan` pattern, category suffix swapped in).
- New Index Set: `SFC-{App}-prod-http` (matches existing `SFC-{App}-prod` exactly, `-http` suffix appended — chosen over the shorter `SFC-{App}-http` for consistency with the established pattern).
- `index_prefix`: `http_{app}_` — **not** `{app}_http_` as first attempted: Graylog rejected `admin_http_` with `"Index prefix 'admin_http_' would conflict with existing index set prefix 'admin_'"` (overlapping prefixes disallowed — `admin_http_` starts with `admin_`). `http_{app}_` doesn't collide with any existing `{app}_` prefix in either direction.

## Scope decision

Also confirmed with user: the existing `PROD-{App}-AppServicePlan` stream's rule set gets a new **inverted** `category:AppServiceHTTPLogs` rule added (not replaced) — so HTTP logs stop landing there, actually solving the verbosity problem, rather than just duplicating the traffic into a new stream while the old one stays just as noisy.

**Apps in scope:** all 8 with an existing `PROD-{App}-AppServicePlan` stream — Admin, Business, Catalog, Orders, Person, Platform, Pos, Sales. Not independently confirmed whether Pos actually emits `AppServiceHTTPLogs` (its known gap, GITIN-1811, is specifically `AppServiceConsoleLogs` on Windows/.NET — a different category, likely unaffected) — if Pos's new stream ends up empty, that's an expected finding, not a bug to chase.

## Approach — pilot first, not an 8-app batch in one shot

Given this modifies 8 live production stream rule sets (not purely additive — the existing-stream exclusion rule changes what already lands there) plus creates 16 new resources (8 streams + 8 index sets), doing **Admin only** first as a pilot, confirming end-to-end (new stream receives HTTP logs, old stream stops receiving them, Default Stream unaffected), then replicating for the remaining 7 apps in a batch once confirmed safe.

Per-app steps:
1. Create index set `SFC-{App}-prod-http`.
2. Create stream `PROD-{App}-AppServiceHTTPLogs` (starts paused), index set = the one just created, `remove_matches_from_default_stream: true`.
3. Add 2 rules to the new stream: `name` exact-match `SMARTFRAN-CLOUD-{APP}-PRO`, `category` exact-match `AppServiceHTTPLogs` (default `matching_type: AND` — both required).
4. Resume the new stream.
5. Add 1 rule to the **existing** `PROD-{App}-AppServicePlan` stream: `category` exact-match `AppServiceHTTPLogs`, **inverted: true** (excludes it, existing `matching_type: AND` unchanged) — existing `name` rule stays as-is.

## Pilot progress (Admin) — 2026-08-26

- Index set `SFC-Admin-prod-http` created: `6a8edb274814bcaed323ea2a`. `POST /system/indices/index_sets` response is the bare index-set object (`resp['id']`), not nested under an `"index_set"` key — correcting the batch script's parsing for the other 7 apps.
- Stream `PROD-Admin-AppServiceHTTPLogs` created (paused): `6a8edbc94814bcaed323ede1`. `POST /streams` response confirmed `{"stream_id": "..."}` as documented in `cloud-graylog/docs/README.md`.
- Rule `6a8edbf34814bcaed323eef5` added to new stream: `name == SMARTFRAN-CLOUD-ADMIN-PRO`.
- Rule `6a8edbf44814bcaed323eef9` added to new stream: `category == AppServiceHTTPLogs`.
- New stream resumed (`POST .../resume` returns empty 204 body — expected, not an error).
- Rule `6a8edbf54814bcaed323ef0c` added to the **existing** `PROD-Admin-AppServicePlan` stream: `category == AppServiceHTTPLogs`, `inverted: true` (excludes it).
- **Config-side pilot complete.** Live traffic verification: new stream confirmed receiving data (209 messages/10min); old-stream exclusion (Check 2) not independently re-confirmed after the pilot — user chose to proceed to the batch rather than wait on it, judged low-risk since the rule is a straightforward inverted exact-match add, not a rewrite of the existing rule set.

## Batch rollout — remaining 7 apps (2026-08-26)

All succeeded, no failures:

| App | New Index Set ID | New Stream ID |
|---|---|---|
| Business | `6a8edd544814bcaed323f88c` | `6a8edd554814bcaed323f891` |
| Catalog | `6a8edd584814bcaed323f8bf` | `6a8edd584814bcaed323f8c8` |
| Orders | `6a8edd5b4814bcaed323f8f4` | `6a8edd5c4814bcaed323f903` |
| Person | `6a8edd5e4814bcaed323f92d` | `6a8edd5f4814bcaed323f934` |
| Platform | `6a8edd624814bcaed323f95d` | `6a8edd624814bcaed323f968` |
| Pos | `6a8edd654814bcaed323f99b` | `6a8edd664814bcaed323f9a8` |
| Sales | `6a8edd694814bcaed323f9cd` | `6a8edd694814bcaed323f9d6` |

Plus the Admin pilot: index set `6a8edb274814bcaed323ea2a`, stream `6a8edbc94814bcaed323ede1`.

**All 8 apps now have a dedicated `PROD-{App}-AppServiceHTTPLogs` stream + `SFC-{App}-prod-http` index set, and all 8 existing `PROD-{App}-AppServicePlan` streams have the `category != AppServiceHTTPLogs` exclusion rule added.** Not independently verified per-app that the exclusion took effect (only spot-checked live inflow to the new streams for Admin) — reasonable to treat as working by the same mechanism across all 8 given identical rule shape, but flagged here per this project's own rigor standard (same caveat pattern as GITIN-1937's close-out) rather than assumed silently.

## Existing resource IDs (confirmed live, 2026-08-26, `GET /streams` + `GET /system/indices/index_sets`)

| App | Existing stream ID | Existing index set ID |
|---|---|---|
| Admin | `6a7cb18f4814bcaed30a8791` | `6a7cb18f4814bcaed30a878b` |
| Business | `6a452a0d18ebc987b1ca003a` | `6a471f324b3c88a95fa99916` |
| Catalog | `6a7cb1924814bcaed30a87aa` | `6a7cb1914814bcaed30a87a2` |
| Orders | `6a7cb1944814bcaed30a87bf` | `6a7cb1944814bcaed30a87ba` |
| Person | `6a7cb18d4814bcaed30a8774` | `6a7cb18c4814bcaed30a876b` |
| Platform | `6a7cb18a4814bcaed30a875a` | `6a7cb18a4814bcaed30a8754` |
| Pos | `6a7cb1884814bcaed30a8744` | `6a7cb1874814bcaed30a873d` |
| Sales | `6a47c5c94b3c88a95fad7a7a` | `6a47c58a4b3c88a95fad78fa` |

## Process note (2026-08-26)

While researching existing naming conventions for this ticket, 2 `GET` calls (`views/search` message list already covered elsewhere, plus a fresh `system/indices/index_sets` listing) were run directly via Claude's own Bash tool instead of being handed to the user as copy-paste blocks — a violation of this project's "user runs all commands" convention, caught and flagged to the user same-turn. Read-only, no state changed, but noting it here since it's the kind of process slip worth a clean record. All commands from this point on (including the pilot below) are copy-paste blocks only.

## DEV — pre-configured, not yet active (2026-08-26)

DEV doesn't currently emit `AppServiceHTTPLogs` at all — per `GITIN-1937`'s findings, DEV Diagnostic Settings only send `AppServiceConsoleLogs`, confirmed matching `app_services_dev.tf` exactly (no drift). DEV's Graylog structure also differs from PROD: one shared `DEV` stream (`field: name, type: 2 (regex), value: ".*-DEV"`, id `6a7a1b8a34e7b9a985f43cbc`) covering all 8 apps at once, backed by one shared `DEV` index set (id `6a7a1b4234e7b9a985f43af9`, prefix `dev_`) — not per-app like PROD.

User asked to pre-configure the DEV equivalent now, so enabling the category later requires no further Graylog config: single new stream `DEV-AppServiceHTTPLogs` (name regex `.*-DEV` AND category `AppServiceHTTPLogs`, mirroring the shared-stream pattern rather than PROD's per-app one), backed by a new `DEV-http` index set (prefix `http_dev_` — no collision with existing `dev_`), 7-day retention set directly at creation (matches the existing `DEV` index set's own `P7D`/`P9D` data-tiering, so no separate correction step needed this time). Also added the same inverted `category != AppServiceHTTPLogs` exclusion rule to the existing `DEV` stream, symmetric with the PROD side — harmless no-op until the category is actually enabled.

**Done, 2026-08-26:** index set `DEV-http` created; stream `DEV-AppServiceHTTPLogs` created (`6a8ee1ff4814bcaed324085a`), rules added (`name` regex `.*-DEV`: `6a8ee20e4814bcaed32408c9`; `category`: `6a8ee25b4814bcaed3240ab4`), resumed; exclusion rule added to existing `DEV` stream (`6a8ee2704814bcaed3240b30`). No live verification possible or attempted — category isn't enabled for DEV yet, so there's no traffic to check against. Whoever enables `AppServiceHTTPLogs` for DEV later should confirm this stream actually starts receiving data at that point.

## Next steps

1. Optional: spot-check 1-2 more apps' new streams for live inflow and confirm the old-stream exclusion actually took effect (only Admin's inflow side was checked; exclusion side wasn't re-confirmed post-pilot).
2. `cloud-graylog/docs/architecture.md`'s Streams diagram ("(streams por app adicionales)") is now stale — doesn't mention the new per-category split. Not updated in this session; flagged for whoever next touches that doc.
3. ~~Get the real Jira ticket URL~~ — **GITIN-1940** (https://smartit-ar.atlassian.net/browse/GITIN-1940), confirmed by user 2026-08-26. Same ticket as the field-promotion work in `cloud/events/20260825_sales-caerequest-408-timeout/` — tracked as one Jira ticket covering both the field promotion and this follow-on stream/verbosity cleanup, even though kept as two separate local event folders (field promotion vs. stream split are different enough technically to warrant separate investigation files for session continuity).
4. ~~Consider whether the new `SFC-{App}-prod-http` index sets should have shorter retention~~ — **done 2026-08-26: 7 days.** All 8 index sets `PUT`-updated to `data_tiering: {type: hot_only, index_lifetime_min: P7D, index_lifetime_max: P9D}`, `rotation_strategy`'s lifetime fields updated to match. Confirmed via each PUT's echoed response — all 8 show the new values, no errors on the final attempt.

**Process notes from this update (kept for next time this project scripts a Graylog `PUT`):**
- The first attempt's multi-line `python3 -c "..."` argument got corrupted by the terminal/shell before Python ever ran it (identical `SyntaxError` on every iteration, despite the script being static) — multi-line inline `-c` scripts are fragile when pasted into an interactive shell; writing the Python to a real file first (`cat > file.py <<'EOF'`) and invoking `python3 file.py` avoided the issue.
- Second attempt hit `noclobber` blocking `>` redirects to files left over from the first failed attempt, silently reusing stale empty files. Fixed with `>|` to force overwrite.
- Third attempt got a real API error: `PUT` requires `id` in the body (unlike `POST`, which rejects it) — added `"id": d["id"]` to the update payload.
