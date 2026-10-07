// Read-only. For the PedidosYa order created 2026-10-03T00:38:35Z on branch 5713 (news 6ac04e8b2476702dafb4c60b),
// show what the platform answered on each state change: top-level key names of `platformResult`, plus only the values of
// keys that look like a status/code/message (truncated to 120 chars). No order body, no customer data, no tokens.
const n = db.news.findOne({_id: ObjectId("6ac04e8b2476702dafb4c60b")});
const wanted = /^(status|statusCode|code|message|error|reason|description|result|success|isValid)$/i;
function brief(pr) {
  if (pr === undefined || pr === null) return pr;
  if (typeof pr !== "object") return String(pr).slice(0, 120);
  const o = {keys: Object.keys(pr).sort()};
  for (const k of Object.keys(pr)) {
    if (wanted.test(k)) {
      const v = pr[k];
      o[k] = (v !== null && typeof v === "object") ? "[object: " + Object.keys(v).sort().join(",") + "]" : String(v).slice(0, 120);
    }
  }
  return o;
}
print(EJSON.stringify({
  now: new Date(),
  traces: (n.traces || []).map(t => ({
    createdAt: t.createdAt, typeId: t.update && t.update.typeId, orderStatusId: t.update && t.update.orderStatusId,
    isValid: t.update && t.update.isValid, platformResult: brief(t.update && t.update.platformResult)
  }))
}, {relaxed: true}, 2));
