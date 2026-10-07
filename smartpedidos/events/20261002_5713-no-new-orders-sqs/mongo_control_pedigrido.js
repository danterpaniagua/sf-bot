// Read-only. Two controls:
// (1) Does the collection I assumed for the "closed restaurant" queue actually exist, and does it hold rows at all?
//     (An empty result on a wrongly named collection would look identical to "no rows".)
// (2) Is 5713's PediGrido behaviour different from a working branch (3013)? For the 30 latest PediGrido orders of each
//     branch: order state, and delay between the news record's creation and the POS viewing it (news.viewed).
//     news is joined to the order by branchId + identical createdAt (observed identical to the ms for 5713).
const out = {};
out.collectionsMatchingRejOrClosed = db.getCollectionNames().filter(n => /rej|closed/i.test(n))
  .map(n => ({name: n, count: db.getCollection(n).estimatedDocumentCount()}));

function sample(branchId) {
  const since = new Date(Date.now() - 14*24*3600*1000);
  const states = db.orders.aggregate([
    {$match: {thirdParty: "PediGrido", branchId: branchId, createdAt: {$gte: since}}},
    {$group: {_id: "$state", n: {$sum: 1}, last: {$max: "$createdAt"}}}, {$sort: {n: -1}}
  ]).toArray();
  const rows = db.orders.find({thirdParty: "PediGrido", branchId: branchId}, {state: 1, createdAt: 1, displayId: 1})
    .sort({createdAt: -1}).limit(30).toArray().map(o => {
      const n = db.news.findOne({branchId: branchId, createdAt: o.createdAt}, {typeId: 1, viewed: 1, createdAt: 1, updatedAt: 1});
      return {
        createdAt: o.createdAt, orderState: o.state,
        newsFound: !!n, newsTypeId: n ? n.typeId : null,
        viewedDelaySec: n && n.viewed ? Math.round((n.viewed - n.createdAt) / 1000) : null,
        neverViewed: n ? !n.viewed : null
      };
    });
  const viewed = rows.filter(r => r.viewedDelaySec !== null).map(r => r.viewedDelaySec);
  return {
    statesLast14d: states,
    sampleSize: rows.length, newsMatched: rows.filter(r => r.newsFound).length, viewedCount: viewed.length,
    viewedDelaySecMin: viewed.length ? Math.min(...viewed) : null,
    viewedDelaySecMax: viewed.length ? Math.max(...viewed) : null,
    rows: rows
  };
}
out.branch5713 = sample(5713);
out.branch3013 = sample(3013);
print(EJSON.stringify(out, {relaxed: true}, 2));
