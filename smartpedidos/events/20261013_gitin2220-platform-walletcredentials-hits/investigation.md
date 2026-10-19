# Investigation — 20261013_gitin2220-platform-walletcredentials-hits

**Status:** open, proposal stage. Jira: GITIN-2220 (https://smartit-ar.atlassian.net/browse/GITIN-2220), title proposed: "[SP] Platform: consultas excesivas a GET WalletCredentials de Cloud (MercadoPago token_fetch)". Nothing was run for this ticket; the evidence is from the sibling events below and from reading `platforms-service` source. No code was changed.

Related Jira: GITIN-2209 (Graylog disk; the Cloud-side failing loop), GITIN-2211 (queue spikes; measured the Platform calls), GITIN-2218 (Graylog charts; Business GET growth), GITIN-2208 (Concentrador MercadoPago token errors).

## Facts

**Measured (other events)**
- GITIN-2211 (SmartPedidos Graylog, 2026-10-11 21:50-22:10 local): `platforms-service` logged `[PERF/INFO] http_response platform=MercadoPago action=token_fetch` about 957 times per minute (16.0 per second); 98% with status 204 (18,776 of 19,141); two `user_id` account for 96% (10,808 and 7,488 of 19,141; 55 distinct ids). Source: `smartpedidos/events/20261013_sqs-spikes-20261011/data/c7-analysis-tokenfetch-gitin2209.txt`.
- GITIN-2218 (Cloud Graylog, Business.API application logs, GET, days in UTC-3): `GET /api/v1/WalletCredentials/{id}` 504,921 on 10-08; 1,898,817 on 10-09; 1,172,153; 1,484,266; 1,512,060 (10-12); 337,399 on 10-13 (partial). Before 10-08 the endpoint does not appear in the top paths. Callers were not traced in that pull, so how much of this is Platform is not established.
- GITIN-2209 (Cloud side): `GET /api/v1/WalletCredentials/{userId}` fails for at least 2 wallet accounts with MercadoPago `invalid_grant` (HTTP 400 on the refresh); on a failed refresh the Cloud code returns null and leaves the credential Active, so each request retries the refresh. The caller identity in the Cloud logs is an Auth0 M2M subject whose `client_id` is configured in both Platform and Concentrador.
- Whether the two `user_id` that dominate the Platform calls are the two failing accounts (credentials 31 and 66) was not checked. How Cloud maps a failed refresh to HTTP 204 was not read.

**Code (`platforms-service`, branch `develop` @ a762c1a, 2026-10-09; working tree after a fast-forward from 373144e; the deployed commit is not known)**
- `api/src/utils/tokensCloud.js` `getTokenMercadoPagoCloud(user_id, tenantId, url)`: GET `<url or STG default>/api/v1/WalletCredentials/{user_id}?applications=Delivery&applications=QR` with a Cloud bearer token from `utils/token.js`, header `TraceKey: '1234'` (hardcoded). On success writes the result to Mongo (`tokenMercadoPagoModel.findOneAndUpdate`, upsert by `tokenMercadoPago.user_id`, line 67). The `[PERF/INFO] ... action=token_fetch` line is written on every non-throwing response (line 25).
- Line 32 checks `tokenMercadoPagoCloud?.response?.status === 204`; a successful axios response has `.status`, not `.response.status`, so that WARN branch cannot run (reading of axios behavior, not tested here). An empty 204 body then reaches `typeof ... !== 'object'` (line 61), throws "Invalid token response from cloud", is logged as `[INTEGRATION/ERROR] token_fetch failed platform=MercadoPago` and returns null. Nothing is stored for a failed call.
- Callers: `controllers/mercadoPago.js:70,102` (per notification element inside a `for` loop; on null it does `continue`; on a cached token plus a 401 it refetches) and `platforms/management/platform/mercadoPago.js:119,161` (receiveOrder, same pattern), plus four more call sites in the same file (lines 265, 294, 365, 400) not read. Every caller only goes to Cloud when Mongo has no token document for the `user_id`.
- No per-`user_id` throttle, negative cache, in-flight de-duplication or backoff was found in the files read.

## Working hypothesis (not confirmed)
For an account whose Cloud refresh fails, Cloud answers 204 (or empty); Platform stores nothing, so every event for that merchant calls Cloud again. That would produce the rate seen in GITIN-2211 (two accounts at 96% of the calls). Test: confirm in the Cloud logs that the calls from Platform for those `user_id` coincide with the `refresh failed` Warnings for credentials 31 and 66, and read the Cloud controller to see the 204 mapping.

## Proposal (Platform, `api/src/utils/tokensCloud.js`; not applied)
1. Negative cache per `user_id`: after an empty answer (204 / no body) or an error, skip the Cloud call until a time-to-live expires.
2. Backoff: the time-to-live doubles on each consecutive failure up to a cap; reset on success.
3. One in-flight request per `user_id`: concurrent callers share a promise.
4. Fix the 204 check (`.status`) and handle it before the "Invalid token response" throw: one WARN, no stack, return null.
5. Log the repeated failure once per window per `user_id`; pass a real `TraceKey` instead of `'1234'`.

Sketch (values are settings to tune; the 5 minute / 1 hour numbers are starting points, not measured):

```js
const NEG_TTL_BASE_MS = Number(process.env.MP_TOKEN_NEG_TTL_MS) || 5 * 60 * 1000;
const NEG_TTL_MAX_MS  = 60 * 60 * 1000;
const negCache = new Map();   // user_id -> { fails, until }
const inflight = new Map();   // user_id -> Promise

const markFailure = (user_id) => {
  const fails = (negCache.get(user_id)?.fails ?? 0) + 1;
  negCache.set(user_id, { fails, until: Date.now() + Math.min(NEG_TTL_BASE_MS * 2 ** (fails - 1), NEG_TTL_MAX_MS) });
};

class tokensCloud {
  static async getTokenMercadoPagoCloud(user_id, tenantId, url = null) {
    user_id = String(user_id);
    const neg = negCache.get(user_id);
    if (neg && neg.until > Date.now()) return null;             // negative cache hit: no call to Cloud
    if (inflight.has(user_id)) return inflight.get(user_id);    // share the request already running
    const p = tokensCloud._fetch(user_id, tenantId, url).finally(() => inflight.delete(user_id));
    inflight.set(user_id, p);
    return p;
  }

  static async _fetch(user_id, tenantId, url) {
    // existing body of getTokenMercadoPagoCloud, with these changes:
    //  - after axios.get: if (res.status === 204 || !res.data) {
    //        Log.save('WARN', null, { message: '[INTEGRATION/WARN] token_fetch empty platform=MercadoPago status=204', category: 'INTEGRATION', user_id, url });
    //        markFailure(user_id); return null; }
    //  - in the catch blocks that return null: markFailure(user_id)
    //  - after the Mongo upsert succeeds: negCache.delete(user_id)
    //  - header TraceKey: the caller's trace key instead of '1234'
  }
}
```

Expected effect (arithmetic on the proposed 5 minute value, not a measurement): two failing accounts would cost about 2 Cloud calls per 5 minutes per task, instead of the 16 per second seen in GITIN-2211 (more with several ECS tasks, since the cache is per process).

## Limits and open items
- The change reduces load on Cloud and on Graylog; it does not give those merchants a token (needs re-authorization or a Cloud-side fix, GITIN-2209).
- The in-memory marker is per task. To share it across ECS tasks it would have to live in Mongo with a TTL index (extra read per call).
- Not read: what `controllers/mercadoPago.js` does with a skipped element (is the notification retried, how often, does the order stay pending). It determines the effect of change 1 on order flow and must be checked before implementing.
- Not read: the other four call sites in `platforms/management/platform/mercadoPago.js`.
- Concentrador: whether it also calls the endpoint and at what rate was not measured.
- Verify any change with the same SmartPedidos Graylog count used in GITIN-2211 and with the Business GET count of GITIN-2218.

## Deployed (user statement, 2026-10-14)
- The user stated that the problem of this ticket was solved and deployed today in SmartPedidos. Not stated: which of P1–P5 was implemented, the commit, or the deployment time; not verified here. The effect is not measured: no data from after the deployment has been read. Measure with the same counts as before (GITIN-2211 `token_fetch` per minute on the SmartPedidos Graylog; Business `api_v1_WalletCredentials` lines per hour on the SmartCloud Graylog, GITIN-2218), and check the two merchants that dominated (10,808 and 7,488 of 19,141 calls) and whether status 204 stops dominating.
- `ops.md` is not changed (written once; the deployment and its result belong in the investigation until the measurement exists).

