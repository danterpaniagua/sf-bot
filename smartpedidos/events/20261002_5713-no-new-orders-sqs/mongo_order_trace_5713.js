// Read-only. Branch 5713: state timeline of the 2026-10-01 PENDING PediGrido order (5637871)
// vs a 2026-09-29 REJECTED one (5629406), plus dead letters. No order body / customer data printed:
// only top-level key names, states and timestamps.
const targets = [
  {label: "pending_20261001", orderId: "6abe983b82a284f3e59e33fe", newsId: "6abe983b82a284f3e59e33ff"},
  {label: "rejected_20260929", orderId: "6abc2da282a284f3e5e357d3", newsId: "6abc2da282a284f3e5e357d5"}
];
const out = {};
for (const t of targets) {
  const o = db.orders.findOne({_id: ObjectId(t.orderId)});
  const n = db.news.findOne({_id: ObjectId(t.newsId)});
  out[t.label] = {
    order: o && {
      topLevelKeys: Object.keys(o), state: o.state, thirdParty: o.thirdParty, displayId: o.displayId,
      createdAt: o.createdAt, updatedAt: o.updatedAt, internalCode: o.internalCode
    },
    news: n && {
      typeId: n.typeId, branchId: n.branchId, createdAt: n.createdAt, updatedAt: n.updatedAt,
      viewed: n.viewed, orderPickedUp: n.orderPickedUp, orderDelivered: n.orderDelivered,
      rejectedMessageId: n.rejectedMessageId,
      traces: (n.traces || []).map(x => ({createdAt: x.createdAt, updateTypeId: x.update && x.update.typeId, updateKeys: x.update ? Object.keys(x.update) : null}))
    },
    deadLetters: db.deadletters.find(
      {$or: [{"bodyParsed.id": t.orderId}, {"bodyParsed.id": t.newsId}]},
      {type: 1, fechaGuardado: 1}
    ).toArray()
  };
}
out.deadLettersLast3dByType = db.deadletters.aggregate([
  {$match: {fechaGuardado: {$gte: new Date(Date.now() - 3*24*3600*1000)}}},
  {$group: {_id: "$type", n: {$sum: 1}, last: {$max: "$fechaGuardado"}}}
]).toArray();
print(EJSON.stringify(out, {relaxed: true}, 2));
