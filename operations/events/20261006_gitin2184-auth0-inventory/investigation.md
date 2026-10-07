# GITIN-2184 — [OPE] Auth0 inventory (SmartCloud)

- Jira: https://smartit-ar.atlassian.net/browse/GITIN-2184
- Opened: 2026-10-06
- Status: data collected, not yet converged (analysis/ticket pending)
- Tenants: dev `dev-wzt4q1xqoe7cwz0f`, prod `smartfran-cloud` (both `*.us.auth0.com`).

## Method

- `scripts.sh` (APIs, clients, client grants, roles + per-role permissions/members, organizations + per-org members/connections, connections, user metadata) and `scripts-users.sh` (all users via monthly `created_at` windows, v3 search). Read-only Management API calls with an M2M app per tenant (`client_credentials`); outputs in `data/{dev,prod}-*`.
- Clients requested with explicit `fields=` (no `client_secret`). `users-all.jsonl` has no PII; emails are only in `data/*-users-emails.jsonl` (gitignored, mode 600) and are analysed by counts only.
- Pitfalls hit (all fixed in the scripts): `/users` listing is capped at 1000 (prod showed exactly 1000; real count is higher); `search_engine=v3` totals are capped at 1000 too; `fields=enabled_clients` invalid on `/connections`; a `// 0` fallback masked 403s as zero org members (dev org members were 0 until `read:organization_members` was granted); role permissions list is paged at 100.
- Compact summary of the tables below: `data/inventory-summary.txt`.

## Inventory

| Entity | Dev | Prod |
|---|---|---|
| APIs (resource servers) | 9 (1 system) | 3 (1 system) |
| Applications / clients | 57 | 13 |
| Client grants (delegated permissions) | 71 grants, 39 distinct clients | 11 grants, 9 distinct clients |
| Roles | 15 | 8 |
| Organizations | 7 | 4 |
| Users | 89 | 1235 |
| Connections | `google-oauth2`, `Username-Password-Authentication` | same two |

### APIs

- Dev: Management API (273 scopes, system); `SmartFran.Cloud.Catalog.API_{LOCAL,DEV,DEV2,TEST,STG,DEMO}` (107–155 scopes each; the identifiers are the per-environment Catalog App Service URLs / localhost); `SmartFran.Cloud.API Pruebas Locales` (12); `SmartFran.Loyalty.WebServiceCG` (0 scopes, test WebServiceCG URL).
- Prod: Management API (system); `SmartFran.Cloud.API_PROD` (identifier `smartfran-cloud-prod`, 139 scopes); `SmartFran.Loyalty.WebServiceCG` (identifier `webservicecg`, 0 scopes).
- Token lifetime 86400 s on all.

### Applications

- Dev (57): 6 SPA families per environment (`Client.Web_*`, `POS_*`, plus a Delegated Admin SPA); the rest are `non_interactive` (M2M) apps named per service/environment (Business, Catalog, Person, Platform, Sales, SML, Loyalty.WebServiceCG, `Functions.Scheduler`, `SmartPedidos`, `READ_API`, `Auth0.Roles.ReadOnly`, a bot app, Management API/API Explorer/Account Link/Security Administration, `Default App`, `Admin Regular Web Application`). Several are duplicated by name (e.g. two `SmartFran.Cloud.Business.API_LOCAL (Test Application)`).
- Prod (13): SPAs `SFC Manager`, `SFC PoS`; M2M apps `SmartFran.Cloud.API_PROD (Test Application)`, `Business.API_PROD`, `Sales.API_PROD`, `Functions.Scheduler`, `SmartFran.Loyalty.WebServiceCG (Test Application)`, `SmartPedidos`, `READ_API`, a bot app, `Auth0 Management` (the app used by this inventory); plus `Default App` (still has `client_credentials`+`implicit` enabled).
- Exact per-client grants/scopes are in `data/*-client-grants.json`; not yet broken down per client in this file.

### Roles (permissions / members)

- Prod: Collaborator 31/146, Franchisee 55/72, FranchiseeExecutive 2/0, Franchisor 56/1, FranchisorExecutive 5/2, Kitchen 12/2, Owner 107/36, Wholesale 31/2.
- Dev: Collaborator 155/13, Franchisee 313/13, FranchiseeExecutive 13/0, FRANCHISEE TEST 11/2, Franchisor 414/5, FranchisorExecutive 22/0, Kiri 8/0, Kitchen 82/7, Owner 678/12, Test 2/0, Wholesale 129/7, plus four `Delegated Admin - *` roles (1–2 permissions, 1 member each).
- Dev role permission totals are summed across the six Catalog API identifiers, so they are larger than prod's single API.

### Organizations (members; enabled connections)

- Prod: grido 1114, jacinto 19, ultracai 23, weiss 114 — all with `Username-Password-Authentication`.
- Dev: demo 10, grido 80, jacinto 23, mayorista 25, otro 13, subway 1 (no connection enabled), weiss 47 (others with `Username-Password-Authentication`).
- Prod org member sum is 1270 vs 1235 users, so some users are members of more than one organization (not verified which).

### Users

| | Dev | Prod |
|---|---|---|
| Total | 89 | 1235 |
| `Username-Password-Authentication` / `google-oauth2` | 77 / 12 | 1226 / 9 |
| Never logged in | 4 | 99 |
| Email not verified | 8 | 83 |
| Blocked | 0 | 0 |
| Created 2023 / 2024 / 2025 / 2026 | 9 / 29 / 42 / 9 | – / 128 / 566 / 541 |
| Distinct emails (case-insensitive) | 82 | 1230 |

- Internal users (email domain exactly `@smartfran.com`; no other `smartfran` domain variant present): 64 of 89 in dev, 62 of 1235 in prod. Extracted by filtering `data/*-users-emails.jsonl` joined with `users-all.jsonl` into `data/{dev,prod}-smartfran-users-emails.jsonl` (gitignored via the `*-users-emails.jsonl` rule, mode 600; addresses are not reproduced here). Their role/organization membership and dev-vs-prod overlap have not been checked.
- Duplicate emails (7 dev, 5 prod) were not investigated; likely the same person with both connections or repeated sign-ups, unverified.

## Open items

- Per-client breakdown of client grants (which M2M app has which scopes on which API), and whether dev-only/test apps and the `Default App` should be flagged for cleanup — not analysed yet; do not state as findings until reviewed.
- Understand why prod `SmartFran.Cloud.API_PROD` has a "(Test Application)" M2M app and what uses it (unverified).
- Confirm the duplicate emails' cause.
- For the internal (`@smartfran.com`) users: roles and organization membership (needs per-role member calls with user IDs), and which exist in only one tenant.
- Decide ticket structure (`ops.md`) once the user signals convergence.
