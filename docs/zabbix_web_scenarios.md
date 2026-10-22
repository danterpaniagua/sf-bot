# Zabbix web scenarios — post-deployment checks

Reference for the web scenarios of the shared Zabbix instance (`sf-monitoreo.smartfran.com`, Zabbix 6.0.32; endpoint and API conventions in `zabbix_observability.md`). Aim: after a deployment, know which scenario to look at, what a pass proves and what it does not.

**Source:** `httptest.get` with full steps, pulled 2026-10-19 10:16 (UTC-3), 16 scenarios, secret-bearing fields masked at pull time (`operations/events/20261019_zabbix-web-scenarios-doc/data/web-scenarios-pull-20261019.txt`). Header, variable and POST values are masked in that file, so statements below about them are about names and presence only. Scenarios change: re-pull before relying on step counts (at least two scenarios changed between 2026-10-15 and 2026-10-19: Loyalty PreProd 9 → 8 steps, API POS / Gestion 1 → 2).

## Reading a scenario after a deployment

- **Items.** `web.test.fail[<scenario>]` is `0` when every step passed, otherwise the number of the failing step (the `#` column below). `web.test.error[<scenario>]` keeps the text of the last error and only gets a value when a step fails, so its age is the age of the last failure.
- **When to read.** Interval (`delay`) is 1 m for every scenario except `[PROD] MobileApp` (30 s); each step has a 15 s timeout and the scenario `retries` is 1. Read the result after at least one full interval following the end of the deploy; a failure recorded while the service was restarting is expected and clears on the next run. The scenarios run from the proxy, so a change to a scenario can take a configuration-sync interval to show (not measured, see `zabbix_observability.md`).
- **Common settings (all 16).** Expected status code 200 on every step, except the Sonarqube login step on `SFCG-TO-01` (no code configured, any response passes). `verify_peer` and `verify_host` are off: **an expired, wrong or untrusted certificate does not fail any of these scenarios**; certificate expiry has its own triggers. No HTTP authentication and no HTTP proxy in the scenario settings; agent string `Zabbix`.
- **Depth used below.** L1 = HTTP 200 only; L2 = also a required text in the response; L3 = exercises a data or authenticated path with a required text.
- **Healthcheck handler on the WebService.** `/healthcheck.ashx` answers HTTP 400 when one 500 ms sample of CPU or of the commit ratio is above 80, so a post-deploy run on a busy host can fail with `400` without the deployment being at fault (`loyalty/CLAUDE.md`, GITIN-2250). The last `API POS / Gestion` failure was a `400`.

## Summary

| Scenario | Host | Steps | Component / environment | Depth |
|---|---|---|---|---|
| `[PROD] MobileApp` | sfcg-monitoreo | 3 | Mobile service (`mobileservice.clubgrido.com.ar:8043`) | L3 |
| `[PROD] Website` | sfcg-monitoreo | 1 | Management site login page (`gestion.clubgrido.com.ar:4430`) | L1 |
| `[PROD] Clubsite AR` | sfcg-monitoreo | 2 | Clubsite Argentina (`www.clubgrido.com.ar`) | L3 on step 2 |
| `[PROD] Clubsite PY` | sfcg-monitoreo | 2 | Clubsite Paraguay (`www.clubgrido.com.py`) | L3 on step 2 |
| `[PROD] API POS / Gestion` | sfcg-monitoreo | 2 | WebService through `webservice.clubgrido.com.ar:8080` | L1 |
| `[PROD] WebServiceV2` | sfcg-monitoreo | 1 | WebServiceV2 (`webservicev2.smartfran.com:8080`) | L1 |
| `[PROD ] Facturasend APP` | sfcg-monitoreo | 3 | FacturaSend auth and API (`fs-auth` / `fs-api.smartfran.com`) | L3 on step 2, L2 on step 3 |
| `Loyalty Test02` | sfcg-monitoreo | 7 | Test02 environment, all components | L1 |
| `Loyalty PreProd` | sfcg-monitoreo | 8 | PreProd environment, all components | L1 |
| `Sonarqube` | sfcg-monitoreo | 1 | SonarQube login page | L1 |
| `Jenkins` | sfcg-monitoreo | 1 | Jenkins login page | L1 |
| `Sonarqube` | SFCG-TO-01 | 2 | SonarQube landing and login | L2 (login step without status code) |
| `[PROD] Clubsite AR Local` / `PY Local` | SFCG-CLUB-01, SFCG-CLUB-02 | 1 each | Same public URL as the Clubsite scenarios, requested from the Clubsite host itself | L1 |

The host `sfcg-monitoreo` is shown in Zabbix with the display name `Zabbix Proxy`. Of the 16 scenarios, 10 appear in the list used as the starting point (Loyalty PreProd, Loyalty Test02, Sonarqube, `[PROD]` API POS / Gestion, Clubsite AR, Clubsite PY, Facturasend APP, MobileApp, WebServiceV2, Website); Jenkins, the SonarQube scenario on `SFCG-TO-01` and the four Clubsite Local scenarios are in the pull but not in that list.

## Production

### `[PROD] MobileApp` (30 s)

| # | Step | URL (path) | Required text | Notes |
|---|---|---|---|---|
| 1 | healthcheck | `:8043/healthcheck.ashx` | none | |
| 2 | POST Account/Login | `:8043/api/Account/Login` | text of the test account's response (not reproduced here) | POST body and `Content-Type` header masked in the pull; step defines variable `{cid}`; follows redirects |
| 3 | AdditionalInformation Puntos LoadBalancer | `:8043/api/AdditionalInformation/GetAddicionalInformation` | `Ok` | query parameters `id`, `code`, `utyp` (values masked) |

- **A pass proves:** the service answers its healthcheck, accepts a login of the monitoring account and returns an additional-information response containing `Ok`.
- **It does not prove:** other endpoints, other accounts, the Mobile hosts one by one (the URL is the public name, so the hit goes to whichever host the balancer chooses), or that step 3 uses the value captured in `{cid}` (the pull masks the values, not checked).
- **After a deploy:** the strongest functional smoke test of the Mobile service. A failure at step 2 or 3 with step 1 passing points to the application or its data, not to IIS being down.

### `[PROD] Website` (1 m)

| # | Step | URL (path) | Required text | Notes |
|---|---|---|---|---|
| 1 | Landing | `:4430/Account/Login?ReturnUrl=%2f` | none | follows redirects |

- **A pass proves:** the site serves its login page with 200.
- **It does not prove:** that anyone can log in. The scenario defines `{username}` and `{password}` variables but the only step has no POST and no variable (the pull masks values, names only).
- **After a deploy:** liveness only.

### `[PROD] Clubsite AR` and `[PROD] Clubsite PY` (1 m)

| # | Step | URL (path) | Required text | AR / PY difference |
|---|---|---|---|---|
| 1 | Landing | `/Home/Index` | none | follows redirects on both |
| 2 | GetAllBenefits | `/Home/GetAllBenefits` (POST, body masked; headers `Content-Type`, `Referer`, `Accept`, `Host` masked) | `Promotion` | AR: explicit `:443`, follows redirects, retrieves body and headers. PY: no port, does not follow redirects, retrieves body only |

- **A pass proves:** the home page answers and the benefits call returns a response containing `Promotion`, which suggests the site reached whatever feeds that list (which layer was not checked).
- **It does not prove:** login, redemption or any other call. The two scenarios are not identical in redirect handling and retrieval mode; whether that is intended was not checked.
- **After a deploy:** step 1 fails = web tier; step 2 fails with step 1 passing = application or data.
- **`... Local` scenarios** (one step, `Home/Index`, no redirects) request the same public URL from `SFCG-CLUB-01` and `SFCG-CLUB-02`; they show whether each Clubsite host sees its own public site (the target is the public name, not a local address).

### `[PROD] API POS / Gestion` (1 m)

| # | Step | URL (path) | Required text | Notes |
|---|---|---|---|---|
| 1 | Healthcheck | `http://webservice.clubgrido.com.ar:8080/healthcheck.ashx` | none | added in GITIN-2250 |
| 2 | Landing | `http://webservice.clubgrido.com.ar:8080/Service/SaleProvider.svc?wsdl` | none | |

- **A pass proves:** the WebService answers the healthcheck handler and returns 200 for the service description. The response content of step 2 is not checked.
- **It does not prove:** a real `SaleProvider` call, or each WEBS host (the URL is the balanced public name; this pull has no scenario per WEBS host).
- **After a deploy:** expect a transient `400` at step 1 if the host answering is above the handler's load limit (see above).

### `[PROD] WebServiceV2` (1 m)

| # | Step | URL (path) | Required text | Notes |
|---|---|---|---|---|
| 1 | Healthcheck | `https://webservicev2.smartfran.com:8080/healthcheck.ashx` | none | follows redirects |

- **A pass proves:** the healthcheck handler of WebServiceV2 returns 200. **It does not prove** any API call.
- **After a deploy:** liveness only.

### `[PROD ] Facturasend APP` (1 m; the name has a space before the closing bracket)

| # | Step | URL (path) | Required text | Notes |
|---|---|---|---|---|
| 1 | Landing | `fs-auth.smartfran.com/` | none | |
| 2 | Test | `fs-api.smartfran.com/<account>/test` | `FacturaSend Funciona.` | `Authorization` header (masked); the account segment of the path is not reproduced |
| 3 | Login | `fs-auth.smartfran.com/auth/` | `Keycloak` | follows redirects |

- **A pass proves:** the authentication site answers, an authenticated call to the API returns its fixed test message, and the login page is the Keycloak one.
- **It does not prove:** that an invoice can be issued. Steps run in the order of the `#` column, not in the order Zabbix lists them.
- **After a deploy:** step 2 is the check for the API and its credentials; step 3 for the identity provider.

## Non-production

### `Loyalty Test02` and `Loyalty PreProd` (1 m)

L1 on every step: HTTP 200, no required text. A pass only shows that each page or description answers.

| Component | Test02 (`#`, port) | PreProd (`#`, port) |
|---|---|---|
| Clubsite AR | 1, `:9443` | 1, default |
| Clubsite PY | 2, `:9443` | 2, default |
| Website | 3, `:9443` login page | 4, `:4430` home |
| Mobile (`/Help`, http) | 4, `:803` | 3, `:8081` |
| WebService (`/service/saleprovider.svc`, http) | 5, `:804` | 5, `:8080` |
| WebServiceV2 (Swagger UI page) | 6, `:802` | 6, `:8082` |
| WebServiceCG (Swagger UI page) | 7, `:805` | not in the scenario |
| WebServiceV2 node 1 / node 2 | not in the scenario | 7 `:8181` / 8 `:8182` |

- **After a deploy:** the Swagger URLs carry a `#!` fragment, which the browser keeps and the HTTP request does not send, so those steps request the Swagger UI page only. `/Help` and the `.svc` URL are help/description pages. None of these steps calls an API.
- Both scenarios timed out (15 s, no bytes received) at 06:01 on 2026-10-19; see the snapshot.

## Tools

- **`Sonarqube` on `sfcg-monitoreo`:** one step, `/sessions/new` with a `return_to` parameter (masked), L1.
- **`Sonarqube` on `SFCG-TO-01`:** 1 Landing (required text `SonarQube`), 2 Login (POST of masked credentials to the root page, no status code configured, no required text). Step 2 cannot fail on the response, so it proves the POST was sent and answered, not that the login worked.
- **`Jenkins` on `sfcg-monitoreo`:** one step, `:8443/login` with a `from` parameter (masked), L1.

## Gaps visible in the configuration

- No scenario has a step that logs into a production site and reads a page behind the login except MobileApp (and the Facturasend API call with its header).
- Required text is configured on 7 of the 37 steps in the pull (MobileApp 2 and 3, Clubsite AR/PY step 2, Facturasend 2 and 3, Sonarqube on `SFCG-TO-01` step 1); the rest only check the status code.
- Certificate validity is not checked by any scenario (peer and host verification off).
- No production scenario addresses a single WEBS, MOBI or Clubsite node except the `... Local` Clubsite ones.

## Snapshot at the pull (2026-10-19 10:16, UTC-3)

All 16 scenarios had `web.test.fail` = 0. Last recorded failure (time of the last value of `web.test.error`; `-` = none recorded):

| Scenario | Last failure | Text |
|---|---|---|
| `[PROD] MobileApp` | 07:52 | response code 500, required 200 |
| `[PROD] Website` | 07:00 | response code 502, required 200 |
| `[PROD] API POS / Gestion` | 10-18 22:37 | response code 400, required 200 |
| `[PROD] Clubsite PY` | 00:04 | timed out after 15000 ms, 0 bytes |
| `[PROD] Clubsite AR Local` (CLUB-02) / `PY Local` (CLUB-02) | 00:04 / 00:04 | timed out, 0 bytes |
| `[PROD] Clubsite PY Local` (CLUB-01) | 00:02 | timed out, 0 bytes |
| `Loyalty Test02` / `Loyalty PreProd` | 06:01 / 06:01 | timed out after 15001 ms, 0 bytes |
| `Sonarqube` (both), `Jenkins`, `[PROD] Clubsite AR`, `[PROD ] Facturasend APP`, `[PROD] WebServiceV2`, `[PROD] Clubsite AR Local` (CLUB-01) | - | |

The times are the last value of the error item, not a check that nothing failed since.
