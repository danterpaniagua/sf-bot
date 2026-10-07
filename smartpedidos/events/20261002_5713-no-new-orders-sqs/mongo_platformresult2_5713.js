// Read-only. (A) The `state` the platform reported in the typeId 4 trace of the PedidosYa news of 5713
// (6ac04e8b2476702dafb4c60b). (B) Control: platformResult per trace for the 3 latest PedidosYa news of branch 3013,
// to see whether "false" on typeId 11/5 is normal. Only booleans/strings of 1-40 chars and the `state` value are printed.
function brief(pr) {
  if (pr === undefined || pr === null) return pr;
  if (typeof pr !== "object") return String(pr).slice(0, 40);
  return {keys: Object.keys(pr).sort(), state: pr.state === undefined ? undefined : String(pr.state).slice(0, 40)};
}
function lines(n) {
  return (n.traces || []).map(t => ({
    createdAt: t.createdAt, typeId: t.update && t.update.typeId, orderStatusId: t.update && t.update.orderStatusId,
    platformResult: brief(t.update && t.update.platformResult)
  }));
}
const a = db.news.findOne({_id: ObjectId("6ac04e8b2476702dafb4c60b")});
const b = db.news.find({branchId: 3013, "extraData.platform": "PedidosYa"}).sort({createdAt: -1}).limit(3).toArray()
  .map(n => ({newsId: n._id, typeId: n.typeId, createdAt: n.createdAt, traces: lines(n)}));
print(EJSON.stringify({now: new Date(), news5713: {newsId: a._id, traces: lines(a)}, control3013: b}, {relaxed: true}, 2));
