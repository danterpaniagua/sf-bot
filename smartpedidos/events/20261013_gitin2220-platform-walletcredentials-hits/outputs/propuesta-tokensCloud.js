// GITIN-2220 — propuesta (boceto, no aplicado) para api/src/utils/tokensCloud.js de platforms-service, rama develop @ a762c1a.
// Los valores de tiempo son puntos de partida a ajustar, no mediciones.
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
