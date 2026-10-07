// Read-only. Branch 5713: non-secret branch fields, platform entries (ids/flags only), news of the last 7 days by type.
// (This is the script originally run inline with --eval; saved here so it is reproducible.)
const b = db.branches.findOne({branchId: 5713}, {
  branchId:1, name:1, code:1, cloud:1, startDate:1, suspendedDate:1, deletedAt:1,
  lastGetNews:1, isCourierSuspended:1, branchTimeout:1, tzo:1, updatedAt:1,
  "platforms.platform":1, "platforms.isActive":1, "platforms.StateAPI":1,
  "platforms.branchIdReference":1, "smartfran_sw.agent.installedVersion":1
});
const since = new Date(Date.now() - 7*24*3600*1000);
print(EJSON.stringify({
  branch: b,
  newsLast7dByType: db.news.aggregate([
    {$match: {branchId: 5713, createdAt: {$gte: since}}},
    {$group: {_id: "$typeId", n: {$sum: 1}, last: {$max: "$createdAt"}}},
    {$sort: {_id: 1}}
  ]).toArray(),
  newsLast10: db.news.find({branchId: 5713}, {typeId:1, createdAt:1, "order._id":1})
    .sort({createdAt:-1}).limit(10).toArray()
}, {relaxed: true}, 2));
