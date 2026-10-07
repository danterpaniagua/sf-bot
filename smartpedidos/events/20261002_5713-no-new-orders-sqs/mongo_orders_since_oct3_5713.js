// Read-only. Orders of branch 5713 since 2026-10-03T00:49Z (the last verified state of the PediGrido entry).
// (1) Count per platform and order state, with first/last createdAt. No order body, no customer data.
// (2) For PediGrido and PedidosYa orders in that range: the news typeId, whether the POS viewed it (and the delay),
//     and the set of trace typeIds (10 = received by the POS, 11 = viewed, 5 = accepted, 4 = platform rejected, 15 = ready).
//     news is joined to the order by branchId + identical createdAt (same join as mongo_control_pedigrido.js).
const since = new Date("2026-10-03T00:49:00Z");
const out = {now: new Date(), since: since};
out.perPlatformState = db.orders.aggregate([
  {$match: {branchId: 5713, createdAt: {$gte: since}}},
  {$group: {_id: {platform: "$thirdParty", state: "$state"}, n: {$sum: 1}, first: {$min: "$createdAt"}, last: {$max: "$createdAt"}}},
  {$sort: {"_id.platform": 1, n: -1}}
]).toArray();
function detail(platform) {
  return db.orders.find({branchId: 5713, thirdParty: platform, createdAt: {$gte: since}}, {state: 1, createdAt: 1, displayId: 1})
    .sort({createdAt: 1}).limit(60).toArray().map(o => {
      const n = db.news.findOne({branchId: 5713, createdAt: o.createdAt}, {typeId: 1, viewed: 1, createdAt: 1, traces: 1});
      return {
        displayId: o.displayId, createdAt: o.createdAt, orderState: o.state,
        newsFound: !!n, newsTypeId: n ? n.typeId : null,
        viewedDelaySec: n && n.viewed ? Math.round((n.viewed - n.createdAt) / 1000) : null,
        neverViewed: n ? !n.viewed : null,
        traceTypeIds: n ? (n.traces || []).map(t => t.update && t.update.typeId) : null
      };
    });
}
out.pedigrido = detail("PediGrido");
out.pedidosya = detail("PedidosYa");
print(EJSON.stringify(out, {relaxed: true}, 2));
