// Read-only. Branch 5713: platform names, branchReference KEY names only, newsTypes map,
// orders last 14d by platform/state, last 5 orders.
const b = db.branches.findOne({branchId: 5713}, {"platforms.platform":1, "platforms.isActive":1, "platforms.branchReference":1});
const ids = b.platforms.map(p => p.platform);
const since = new Date(Date.now() - 14*24*3600*1000);
print(EJSON.stringify({
  platforms: db.platforms.find({_id: {$in: ids}}, {name:1}).toArray(),
  branchReferenceKeysByPlatform: b.platforms.map(p => ({platform: p.platform, isActive: p.isActive, keys: p.branchReference ? Object.keys(p.branchReference) : null})),
  newsTypes: db.newsTypes.find({}, {typeId:1, cod:1, name:1, _id:0}).sort({typeId:1}).toArray(),
  ordersLast14dByPlatformState: db.orders.aggregate([
    {$match: {branchId: 5713, createdAt: {$gte: since}}},
    {$group: {_id: {thirdParty: "$thirdParty", state: "$state"}, n: {$sum: 1}, last: {$max: "$createdAt"}}},
    {$sort: {last: -1}}
  ]).toArray(),
  ordersLast5: db.orders.find({branchId: 5713}, {thirdParty:1, state:1, displayId:1, createdAt:1})
    .sort({createdAt:-1}).limit(5).toArray()
}, {relaxed: true}, 2));
