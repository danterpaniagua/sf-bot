// Read-only. What reached platforms-service for 5713 in the last 6h (tests after the re-integration), and is
// PedidosYa / PediGrido traffic arriving for ANY branch in that window (control). Flags/timestamps only, no order bodies.
const since = new Date(Date.now() - 6*3600*1000);
const mine = db.orders.find({branchId: 5713, createdAt: {$gte: since}}, {thirdParty: 1, state: 1, displayId: 1, createdAt: 1})
  .sort({createdAt: 1}).toArray().map(o => {
    const n = db.news.findOne({branchId: 5713, createdAt: o.createdAt}, {typeId: 1, viewed: 1, createdAt: 1, updatedAt: 1});
    return {createdAt: o.createdAt, thirdParty: o.thirdParty, state: o.state, newsTypeId: n ? n.typeId : null,
            viewedDelaySec: n && n.viewed ? Math.round((n.viewed - n.createdAt) / 1000) : null, neverViewed: n ? !n.viewed : null};
  });
const byPlatformAllBranches = db.orders.aggregate([
  {$match: {thirdParty: {$in: ["PedidosYa", "PediGrido", "MercadoPago"]}, createdAt: {$gte: since}}},
  {$group: {_id: "$thirdParty", orders: {$sum: 1}, branches: {$addToSet: "$branchId"}, last: {$max: "$createdAt"}}},
  {$project: {orders: 1, distinctBranches: {$size: "$branches"}, last: 1}}
]).toArray();
const b = db.branches.findOne({branchId: 5713}, {lastGetNews: 1, "smartfran_sw.agent.installedVersion": 1, "smartfran_sw.agent.installedDate": 1});
print(EJSON.stringify({now: new Date(), since: since, branch: b, ordersFor5713Last6h: mine, byPlatformAllBranchesLast6h: byPlatformAllBranches}, {relaxed: true}, 2));
