# Axios 1.16.0 upgrade impact analysis — raw check outputs (2026-09-08)

Consolidated output of the checks run against the local read-only clone
`smartpedidos/repo/dev-src-smartPedidos-concentradorService` and the public npm registry.
Referenced as C1 from `ops.md`.

## 1. Dependency-tree check (npm registry) — who depends on axios

```
mongoose@7.8.7 dependencies: {"ms":"2.1.3","bson":"^5.5.0","sift":"16.0.1","mpath":"0.9.0","kareem":"2.5.1","mquery":"5.0.0","mongodb":"5.9.2"}
mongodb@5.9.2 dependencies: {"bson":"^5.5.0","socks":"^2.7.1","mongodb-connection-string-url":"^2.6.0"}
mquery@5.0.0 dependencies: {"debug":"4.x"}
bson@5.5.0 dependencies: {}
kareem@2.5.1 dependencies: {}
mongodb-connection-string-url@2.6.0 dependencies: {"whatwg-url":"^11.0.0","@types/whatwg-url":"^8.2.1"}
socks@2.7.1 dependencies: {"ip":"^2.0.0","smart-buffer":"^4.2.0"}
=> No axios reference anywhere in the mongoose subtree.

@sendgrid/mail@7.7.0 dependencies: {"@sendgrid/client":"^7.7.0","@sendgrid/helpers":"^7.7.0"}
@sendgrid/client@7.7.0 dependencies: {"axios":"^0.26.0","@sendgrid/helpers":"^7.7.0"}
=> Confirmed: @sendgrid/client pins axios ^0.26.0, matching the 0.26.1 install Trivy flagged.

Remaining direct dependencies checked individually (none declare an axios dependency):
@aws-sdk/client-sqs@3.0.0, @aws-sdk/client-ssm@3.0.0, @babel/core@7.6.0,
@meanie/mongoose-to-json@2.4.0, body-parser@1.18.3, cookie-parser@1.4.3,
core-js@3.2.1, cors@2.8.5, crypto-js@4.2.0, express@4.18.2, express-jwt@8.5.1,
form-data@4.0.2, jsonwebtoken@9.0.3, lodash@4.17.15, moment@2.22.2,
mongoose-unique-validator@4.0.1, morgan@1.9.1, node-cron@2.0.3,
regenerator-runtime@0.13.3, swagger-jsdoc@6.2.8, swagger-ui-express@5.0.0,
uuid@8.0.0, winston@3.2.1, winston-mongodb@5.0.0
```

## 2. Source call-site inventory (`grep -rln "axios" api/src`)

```
api/src/index.js               -> axios.defaults.timeout = 20000 (global default, set once)
api/src/utils/initialData.js   -> unused raw import; real call via httpClient (1 site)
api/src/utils/httpClient.js    -> axios.create() + request/response interceptors (PERF logging)
api/src/controllers/delivery.js -> 1 raw axios.post(url, { delivery }, { headers })
api/src/controllers/thirdParty.js -> unused raw import; real call via httpClient (1 site)
api/src/utils/token.js         -> unused raw import; real call via httpClient (1 site)
api/src/utils/checkUTC.js      -> unused raw import; real calls via httpClient (5 sites, timezonedb.com)
api/src/controllers/branch.js  -> ~85 httpClient.{get,post,put,delete} call sites
                                   + 1 raw axios(config) call (loginCountryUber, FormData/Uber OAuth)
```

`branch.js` httpClient call sites cover: PediGrido login/availability, PedidosYa login,
Rappi enable/disable stores (AR/PR/CL/UR), Uber Eats login/webhooks/availability,
SmartLoyalty (`sml`) order updates, generic branch webhook add/get/delete, and
platform order confirm/reject/dispatch callbacks.

## 3. Config-pattern check (proxy, basic-auth-in-URL, size limits)

```
grep -i "HTTP_PROXY|HTTPS_PROXY|NO_PROXY|proxy:" api/src -> no matches
grep "://[^/]*:[^/@]*@" api/src -> only the MongoDB connection string (not an axios call)
grep "maxContentLength|maxBodyLength|paramsSerializer|transformRequest|withCredentials" api/src -> no matches
```

## 4. axios changelog review (v1.14.0 -> v1.16.0), behavior changes checked against the above

| Change (introduced) | Applicable to this codebase? |
|---|---|
| CRLF header-value rejection (v1.15.0) | Low risk — all header values are static strings or opaque third-party Bearer tokens |
| Fetch adapter maxBodyLength/maxContentLength enforcement (v1.16.0) | Not applicable — Node http adapter only, fetch adapter unused |
| Proxy Host header preservation / NO_PROXY normalization (v1.15.0/v1.16.0) | Not applicable — no proxy config found |
| Basic auth credentials in URL now URL-decoded (v1.16.0) | Not applicable — no axios call uses user:pass@ URLs |
| parseProtocol strictly requires a colon (v1.16.0) | Low risk — all URLs are well-formed absolute URLs already in production use |
| FormData Content-Type removed when no boundary present (v1.15.1) | Not applicable — fetch-adapter-specific; this app's one FormData call uses the Node http adapter |
| CRLF stripping in multipart header values (v1.15.1) | Negligible — the one FormData call's fields are static config strings |
