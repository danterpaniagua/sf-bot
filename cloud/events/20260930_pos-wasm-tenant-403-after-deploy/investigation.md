# Investigation — 20260930_pos-wasm-tenant-403-after-deploy

**Jira:** [GITIN-2134](https://smartit-ar.atlassian.net/browse/GITIN-2134) "[CLOUD] Error 403 SFC-POSWASMRELAY-PRO" (filed after this folder was created, so the folder name keeps no ticket id per the creation-time-only naming rule). The title names the relay Function App as the subject; the one sample message shows the 403 as a *client-side* log of a call to `/api/Tenant/{id}` forwarded *through* the relay, so whether the relay itself is returning 403s is not established.

**Status (2026-09-30, end of day):** in progress — **cause not confirmed.** Scope known from Graylog: 70 POS 403s in 7 days (69 on `/api/Tenant/d3186bc6d7b2`), first 11:59Z today, none before; other callers of the route get 200; Graylog cannot show the user (`UserId` empty, source logs only failures). Source: the PRO release `v02.46.00` added `[Authorize]` + `[RequiredScope("read:tenant")]` to `GET /api/Tenant/{id}`. PRO Auth0 tenant (`smartfran-cloud`) read: all 8 roles hold `read:tenant`, so roles are not the gap. Open: the PRO POS client's requested scopes/audience (no `_PRO` config in the repo), users without a role or with roles only via Organization, stale pre-release sessions (user hypothesis, untested), and the failing request's `WWW-Authenticate`/token claims. `ops.md` written 2026-09-30 at the user's request (hypothesis labelled, actions proposed); `scripts.sh` = reusable read-only Auth0 check.

## Report (user, 2026-09-30)

SmartCloud: "today we did a deploy and we are having those errors 403 in graylog". Evidence file dropped: `cloud/q1` (copied to `data/graylog_message_403_20260930.json`; the original at `cloud/q1` is untouched, `.json` under `events/` is gitignored, `q1` itself has no extension and is not).

## Confirmed facts (from the single message in `q1`; the Graylog export holds ONE message, not a result set)

- Graylog message timestamp `2026-09-30T16:16:15.723Z`; embedded log `Timestamp` `2026-09-30T16:15:16Z`; `TraceKey: SFCPOS.POS:2.2026-09-30T16:14:46.7760000+00:00`.
- `Service = smartfran-pos-wasm`, `Environment = Production`, `ClientService = SmartFran.Cloud.Pos.Wasm`, `SourceContext = SmartFran.Cloud.Pos.Wasm.Handlers.HttpLoggingHandler`, `AppLevel = Error`, `Version = 1.0.0.0`, `category = FunctionAppLogs`, source Function App **`SFC-POSWASMRELAY-PRO`** (`IngestLogs`), stamp `waws-prod-blu-203`.
- Logged event: `HTTP 'GET' '/api/Tenant/d3186bc6d7b2' responded 403 in 332.5 ms`. So this is the **POS Blazor WASM client's own HTTP call log**, forwarded through the relay (per `cloud/docs/graylog-log-fields.md`, "SFC-PosWasmRelay traffic"); the 403 was returned by whichever backend the client called — **the message does not say which host/API** (no host in the path).
- `d3186bc6d7b2` has the 12-char opaque tenant-hash shape used elsewhere as `TenantId`.
- The `event_original` field (30,052 chars) is a **truncated** Azure diagnostic JSON (cut mid-string), so it can't be parsed with `jq`; it contains additional `IngestLogs` invocations but was not read in full.
- `cloud/docs/graylog-log-fields.md` (GITIN-1924, 2026-08-24) already flagged a `TenantId` format discrepancy on this source: an Auth0 `org_id`-shaped value (`org_...`) vs. the 12-char hash. Not confirmed intentional; **no evidence yet that it relates to this 403**.

## Source review — `cloud/repo/SmartFran.Cloud`, branch `main` (user pulled it; working tree clean, head `d969856fa` "Stg => PRO v02.46.00 30-09-2026", committed 2026-09-30 06:26 local time of the committer's zone)

- Previous PRO release commit: `c6234e09b` (v02.45.04, 2026-09-23). The PRO range `c6234e09b..d969856fa` includes GSFC-1005 (merged to dev 2026-09-16, PR #1866/#1879).
- `GET /api/Tenant/{identifier}` is `TenantController.GetTenant` (`Source/Services/Platform/SmartFran.Cloud.Platform.API/Controllers/v1/TenantController.cs:39`) — the route in the 403 message.
- **Change in that range (diff of `TenantController.cs`, commit `470c93ad4`, GSFC-1005):** the class-level `[Authorize]` — commented out "since the origin" so login could call `/Organization/*` without a token — was **re-enabled**, and `[RequiredScope("read:tenant")]` was **added to `GET {identifier}`** (and `write:tenant` to the write endpoints; the `dashboards` PUT went from anonymously reachable to `write:tenant` + `Owner` role, per its own comment). Organization endpoints are kept `[AllowAnonymous]` individually. `Program.cs` change is comments only (JwtBearer is the auth path).
- Mechanism (from the code and general ASP.NET behaviour, not observed): a caller with a valid token that lacks the `read:tenant` scope is answered with 403; no token would be 401. The sample is a 403, consistent with an authenticated caller missing the scope.
- The Business service's `Proxy.cs:81` was updated in the same release for `read:tenant` (a comment says tenant config now requires it) — the server-to-server caller was addressed.
- **POS WASM client config:** `wwwroot/SmartFran.Cloud.Pos.Wasm_{DEV,STG,TEST}.json` all request `read:tenant` (matched by grep in each). **There is no `_PRO` file in the repo**, so the scopes the PRO POS client requests are not visible from source — set elsewhere (deploy-time config or Auth0), unverified. Last change to that folder: `a7d8a35c8` 2026-09-22 (GSFC-1017).

## Working theory (unconfirmed — hypothesis only)

The v02.46.00 PRO deploy started enforcing `read:tenant` on `GET /api/Tenant/{id}`; the PRO POS WASM client's access tokens may not include that scope (PRO client config not in the repo, or the Auth0 API/role permissions for PRO not updated), so the call returns 403. To confirm: decode (not paste) a PRO POS token's `scope`/`permissions` claim, check the PRO client's requested scopes, and check the Auth0 API permissions granted to the POS client/role in the PRO tenant. Alternative causes not ruled out: a different 403 source (WAF/gateway), or a problem in the relay's own handling.

## Graylog aggregate — last 24 h (2026-09-29T16:40Z → 2026-09-30T16:40Z), 2026-09-30 13:40 local

Query: `Service:smartfran-pos-wasm AND message:"/api/Tenant/"` grouped by `Path`, `StatusCode` (`data/graylog_tenant_calls_by_path_status_20260930.json`; earlier attempts failed with 401 — first token was rejected by the SmartCloud instance, a new one worked). Result, 3 rows only:

| Path | StatusCode | count |
|---|---|---|
| `/api/Tenant/d3186bc6d7b2` | 403 | 69 |
| `/api/Tenant/Organization/org_z72xsKwcFsVLHF3c` | (empty) | 2 |
| (empty) | (empty) | 71 |

- **Only one tenant path appears in the whole 24 h, and all 69 of its calls are 403.** There are **no 200 responses** to any `/api/Tenant/*` call in the window — including the ~17 h before the deploy — so this data shows no unaffected tenant, but it also gives **no pre-deploy baseline** of the route working.
- The 71 rows with empty `Path`/`StatusCode` are messages that contain the phrase but lack the promoted fields; 69 + 2 = 71 suggests these may be the same events logged a second time in raw form, but that was not checked.
- The `Organization/org_…` call (2 rows, no status) is the anonymous endpoint family; its outcome is not visible here.
- Counts are log messages, not users (`UserId` is empty on this source).

## Graylog — 7-day window (2026-09-23T16:40Z → 2026-09-30T16:40Z)

Same query, `range=604800` (`data/graylog_tenant_calls_7d_20260930.json`) and earliest 403 (`data/graylog_first_403_7d_20260930.json`):

- `/api/Tenant/d3186bc6d7b2` 403 = **69 in 7 days = the same 69 as in the last 24 h** → **all 403s are from today**; `total_results = 69`. **First 403: 2026-09-30T11:59:17Z (08:59 in UTC-3).** None in the 6 days before.
- `/api/Tenant/Organization/org_z72xsKwcFsVLHF3c` (no status): 24 messages in 7 days (2 in the last 24 h); empty-field rows: 93.
- Still **no 200 response** to `/api/Tenant/*` in 7 days, so the log shows neither a working baseline for this route nor any unaffected tenant. Not known whether successful calls are logged at all for this source (the 2026-08-24 audit sample was an Information-level HTTP-call log, so they can be); not checked with an all-paths 200 query.
- Source check: the POS client's tenant lookup is not new — `ITenantService` is injected across many POS pages and the tenant/organization services date from 2025-06/2025-08 (`Services/Tenants/OrganizationService.cs`, commit `ed34d748f` 2025-08-13). So the 403 is not explained by a newly added client call.
- Timing note: `d969856fa` "Stg => PRO v02.46.00" carries commit time 2026-09-30 06:26 (committer's local zone, presumably UTC-3 = 09:26Z); the actual PRO deploy time is unknown. First 403 at 11:59Z is after that commit time, consistent with (not proof of) the deploy.

## Graylog — all status codes for `Service:smartfran-pos-wasm`, 7 days (`data/graylog_all_status_7d_20260930.json`, run 13:54)

| StatusCode | count |
|---|---|
| 404 | 4123 |
| 500 | 1012 |
| 408 | 432 |
| 400 | 194 |
| 403 | 70 |

**No 2xx of any kind in 7 days** (and the dominant `AppLevel` of the sample was Error): this source evidently forwards only failed HTTP calls to Graylog, so the log **cannot** answer "which users/tenants work" or give a pre-deploy baseline of successes. 70 total 403s = the 69 on `/api/Tenant/d3186bc6d7b2` + 1 on another path (not identified). The other error volumes (404/500/408/400) were not analysed here.

Next signal needed: the receiving side. `SFC.Platform` (Platform API) serves `/api/Tenant/{id}`; whether its request logs reach this Graylog was not confirmed — `cloud/docs/infrastructure.md` lists Platform among the backend services but the Graylog source docs reviewed here cover the Function apps, Business, Sales and PosWasmRelay.

## Graylog — `/api/Tenant/` across all services, last 24 h (`data/graylog_tenant_by_service_status_20260930.json`, 13:56 local)

| Service | StatusCode | count |
|---|---|---|
| SmartFran.Cloud.Platform.API | 200 | 504 |
| SmartFran.Cloud.Platform.API | (empty) | 13,089 |
| SmartFran.Cloud.Client.Web | 200 | 6,156 |
| SmartFran.Cloud.Client.Web | 401 | 4 |
| SmartFran.Cloud.Client.Web | (empty) | 6,160 |
| smartfran-pos-wasm | 403 | 70 |
| smartfran-pos-wasm | (empty) | 74 |
| SmartFran.Cloud.Business.API | 200 | 8 |
| SmartFran.Cloud.Functions.* (Balance, ScheduledJobs) | (empty) | 4 each |

- **Platform API logs do reach this Graylog**, and **other callers of `/api/Tenant/…` get 200**: Client.Web 6,156 × 200 (+4 × 401), Platform API 504 × 200, Business.API 8 × 200. So the route is not failing for everyone; the 403s are specific to `smartfran-pos-wasm` (70 in the window).
- **The Platform API shows no 403 row** in this window, even though the POS client logged 70 → the server-side rejection (if it is the authorization layer) is not logged with a `StatusCode` on the Platform API side, or sits in the 13,089 messages without a status. Not yet looked at.
- Path breakdown for the 200s was not done (Client.Web/Business may be calling other `/api/Tenant/…` routes, e.g. `Organization/*`, not `GET /api/Tenant/{id}` specifically), and the window mixes pre- and post-deploy time, so "works" here means "worked at some point in the last 24 h", not "works after the deploy".

## Graylog — everything logged under the sample call's TraceKey (`data/graylog_tracekey_sample_20260930.json`, 14:18 local)

`TraceKey:"SFCPOS.POS:2.2026-09-30T16:14:46.7760000+00:00"`, last 24 h → **3 messages**:
1. `16:15:16Z` `smartfran-pos-wasm` — the relay's raw ingestion line for the client log (no status fields).
2. `16:15:53Z` `SmartFran.Cloud.Platform.API`, Warning — `RequestHandlingMiddleware: The setting "LogOriginalRequest" is missing or set to "False". Request info about the PUT, POST and DELETE actions is not being logged.` (embedded timestamp 16:14:46.529Z; a generic configuration warning, no status code, no authorization text).
3. `16:16:15Z` `smartfran-pos-wasm` — the 403 client log already analysed.

- The Platform API logged under the client's TraceKey, so **that request reached the Platform API** (inference from the propagated key; a gateway in front would not have logged it there). It logged **no authorization failure message and no status** for it. So Graylog contains no server-side statement of *why* the 403 was returned.
- Direct, cheap confirmation that does not need logs: the 403 response from `RequiredScope`/JwtBearer normally carries a `WWW-Authenticate: Bearer … error="insufficient_scope"` header (general ASP.NET/JwtBearer behaviour, not yet observed here). The browser DevTools → Network tab on the failing `GET /api/Tenant/{id}` would show it, plus the token's `scope`/`permissions` claims if decoded locally.

## Auth0 Management API read (2026-09-30 14:31 local; `data/auth0_*_20260930.*`)

Credentials: the user's exported `AUTH0_*` variables (values never written anywhere). Token meta (`auth0_token_meta_20260930.json`): scopes `read:client_grants read:clients read:resource_servers read:roles read:role_members`, `expires_in 86400`. **Tenant queried: `dev-wzt4q1xqoe7cwz0f.us.auth0.com`** (the same domain as the Platform API's checked-in `appsettings.json`).

- **Is this the PRO tenant? Not established.** The tenant holds APIs `SmartFran.Cloud.Catalog.API_{LOCAL,DEV,TEST,STG,DEMO,DEV2}` and applications `POS_{LOCAL,DEV,TEST,STG,DEMO,DEV2}`, `Client.Web_*`, `Platform.API_*`, etc. — **nothing labelled PRO**. Either PRO lives in another tenant, or PRO reuses one of these entries under a different name (e.g. the API identifier `https://smartfran-cloud-catalog.azurewebsites.net/` is named `API_TEST`). Needs the PRO `Auth0:Domain`/audience from the PRO App Service configuration.
- **APIs/permissions:** `read:tenant` and `write:tenant` exist on Catalog.API_LOCAL/DEV/TEST/STG (148/148/154/155 permissions; RBAC on, permissions in access token). Two more APIs (DEMO 107, DEV2 113) not checked for these two.
- **Roles (15):** Collaborator, Delegated Admin ×4, Franchisee, FranchiseeExecutive, FRANCHISEE TEST, Franchisor, FranchisorExecutive, Kiri, Kitchen, Owner, Test, Wholesale. `read:tenant` is present in most (e.g. Kitchen 82 perms, FranchiseeExecutive, FranchisorExecutive, Wholesale…). **`write:tenant` appears in none of the roles whose lists were complete.**
- **Data limit:** `permissions?per_page=100` returned exactly **100** for Collaborator (13 users), Franchisee (13), Franchisor (5), Owner (12) and Wholesale (7) → **truncated, read/write:tenant absence for those roles is NOT established** (Wholesale already shows `read:tenant`). Pagination was not done.
- **Client grants** (~40 rows, all M2M-style): none includes `read:tenant`; not informative for the POS SPA, which gets its scopes from the user login (client's requested `Scopes` ∩ the user's role permissions), not from a client grant.

### Auth0 roles — full paginated permissions for the 4 truncated roles (`data/auth0_role_permissions_full_20260930.jsonl`, 14:35 local)

| Role | Permissions | `read:tenant` | `write:tenant` |
|---|---|---|---|
| Collaborator | 155 | yes | no |
| Franchisee | 313 | yes | no |
| Franchisor | 414 | yes | no |
| Owner | 678 | yes | **yes** |

With these, **every one of the 15 roles in tenant `dev-wzt4q1xqoe7cwz0f` carries `read:tenant`** (the other 11 were complete on the first page); `write:tenant` is only on Owner. So, **in this tenant, a missing `read:tenant` on the roles is not the explanation.** This does not clear the PRO setup: the tenant read has no PRO-labelled API/app, and role assignments made per Auth0 *Organization* member (`organizations/{id}/members/{user}/roles`) and users with no role were not queried (only direct role-user counts were).

Remaining candidates, none confirmed: (a) PRO uses a different Auth0 tenant/API whose permissions/roles were not read; (b) the PRO POS client does not request `read:tenant` in its login `Scopes` (no `_PRO` config in the repo); (c) the affected user(s) have no role, or hold it only through an Organization membership not read here; (d) audience mismatch between the PRO POS client and the Platform API. The deciding evidence is the failing request itself: its `WWW-Authenticate` header and the access token's `scope`/`permissions` claims (DevTools, claim names only).

### Hypothesis (user, 2026-09-30): POS sessions left open since the previous version

Source facts (branch `main`, POS Wasm client): `read:tenant` was **added to the POS scopes config in `470c93ad4` (2026-09-11) and `a7d8a35c8` (2026-09-22)** (`git log -S`), i.e. shortly before the PRO release; `Program.cs:269-275` uses `AddOidcAuthentication` with `ResponseType = "code"`, `offline_access` in `Scopes` (refresh tokens), the `audience` parameter and an `organization` login parameter. By standard OAuth behaviour (not observed here), a refresh token renews access tokens with the scopes originally granted and cannot add `read:tenant`; a session (or cached WASM build) started before the client requested it would keep a token without it, and the API now enforcing the scope would answer 403 until a fresh login. **Consistent with** all 403s appearing today from one tenant path (69 messages, first at 11:59Z) and none before; **not proven**: no data yet on the age of the failing sessions, the token's `scope`, or whether a new login fixes it. Decisive, cheap test: have an affected user sign out and in again (and hard-reload the WASM app) and retry `GET /api/Tenant/…`; compare the `scope` claim before/after.

## Auth0 PRO tenant `smartfran-cloud.us.auth0.com` (read 2026-09-30 14:50 local; `data/auth0_prod_*_20260930.*`)

Credentials from the user's `AUTH0_*_PROD` variables (never written). Token scopes granted: `read:client_grants read:clients read:resource_servers read:roles read:role_members read:organizations read:organization_members` (no `read:organization_member_roles`, no `read:logs`). **This is the PRO tenant; the earlier `dev-wzt4q1xqoe7cwz0f` findings do not describe PRO.**

- **API:** `SmartFran.Cloud.API_PROD`, identifier/audience **`smartfran-cloud-prod`**, RS256, RBAC on, permissions in `access_token`, offline access on, 139 permissions including `read:tenant` and `write:tenant`.
- **Applications (SPA):** `SFC PoS`, `SFC Manager`; machine-to-machine: `Business.API_PROD`, `Sales.API_PROD`, `API_PROD (Test Application)`, `Functions.Scheduler`, `SmartPedidos`, `BOT Wise CX`, `SmartFran.Loyalty.WebServiceCG`, `Auth0 Management`, `READ_API`.
- **Organizations (4):** `grido` (`org_z72xsKwcFsVLHF3c`), `jacinto`, `ultracai`, `weiss`. The `org_z72…` id is the `grido` organization id — the same one in the Graylog `/api/Tenant/Organization/org_z72xsKwcFsVLHF3c` path; which organization owns tenant hash `d3186bc6d7b2` was not looked up.
- **Roles (8) with direct role members:** Collaborator 146 (31 perms), Franchisee 72 (55), Franchisor 1 (56), FranchisorExecutive 2 (5), FranchiseeExecutive 0 (2), Kitchen 2 (12), Wholesale 2 (31), Owner 36 (107). **Every role holds `read:tenant` on `smartfran-cloud-prod`; `write:tenant` only Owner.** Lists were fully paged (none near the 100 cap by the script's loop).
- **Conclusion so far:** in the PRO tenant, **no role lacks `read:tenant`**, so a missing role permission is not the explanation for a user who has one of these roles. A **403** (not 401) means the token was accepted (signature/audience OK — Client.Web gets 200 on the same route against the same API), so the gap is the `scope` claim of the POS token. Still open: (a) the PRO POS client's requested `Scopes`/`audience` (no `_PRO` config in the repo; does it include `read:tenant` and audience `smartfran-cloud-prod`?), (b) users with no role, or roles only via Organization membership (`read:organization_member_roles` not granted), (c) sessions started before the client requested `read:tenant`.
- **Role purposes (Auth0 dashboard text pasted by user, `data/auth0_prod_roles_dashboard_20260930.txt`):** Collaborator = "Rol para uso de los colaboradores en el Pos" (**the POS staff role**), Franchisee/Franchisor = admin roles, FranchiseeExecutive/FranchisorExecutive = dashboards, Kitchen, Owner = SmartFran administration, Wholesale = "Mayorista".
- **Collaborator (POS staff) in PRO:** 146 direct members, 31 permissions incl. **`read:tenant`** (no `write:tenant`). The STG POS client config requests 108 scopes; most (e.g. `write:item`, `read:category`, all `delete:*`…) are not granted by Collaborator — with RBAC the token carries requested ∩ granted, so that is expected and unrelated to this 403. The PRO POS request list is unknown.
- **Separate finding, not this ticket's cause:** the code's `RequiredScope` values include 7 that the PRO API lacks: `delete:accountcategory`, `delete:chartofaccountsassignment`, `delete:chartofaccountsconcept`, `delete:chartofaccountsgroup`, `delete:moneywarehouse`, `write:franchisororderrequests`, `write:franchisororderresponses` (those endpoints would return 403 for everyone).

## Not known

- What was deployed today (component, version, time, environment) — user said "a deploy", nothing more.
- How many 403s, since when, which tenants/POS/paths, whether `/api/Tenant/{id}` is the only failing route, and whether 403s existed before the deploy.
- Which service returns the 403 (Cloud API, Function, gateway/WAF, or an auth layer).

## Suggested Graylog checks (user runs; results to `data/`)

1. Count/histogram: `Service:smartfran-pos-wasm AND StatusCode:403` today, by hour, to find the start time vs. the deploy time.
2. Group by `Path`, `TenantId`, `Method`; compare with the same query for yesterday.
3. Same query without `StatusCode` filter, `StatusCode:[400 TO 599]`, to see whether other codes rose too.

## Next steps

1. Ticket URL, deploy details (what/when), and the query results above.
2. Find which backend serves `GET /api/Tenant/{id}` and what auth it requires (source in `cloud/repo/SmartFran.Cloud`; check `origin/main`, the PRO branch, per project convention).
