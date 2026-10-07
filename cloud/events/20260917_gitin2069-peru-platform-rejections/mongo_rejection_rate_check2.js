// Event: 20260917_gitin2069-peru-platform-rejections (GITIN-2069)
// Corrected: rejection extraData lives in the `news` collection, not
// `orders` (confirmed in platformRejectStrategy.js -- it calls
// news.find()/updateNew(), not the orders model). Requerying against the
// right collection.

const peruBranches = db.branches.find(
  { "address.country": /per[uú]/i },
  { branchId: 1, _id: 0 }
).toArray();
const peruBranchIds = peruBranches.map(b => b.branchId);

const since = new Date(Date.now() - 7*24*60*60*1000);

print("=== news collection: sample doc shape (sanity check field names) ===");
printjson(db.news.findOne({ branchId: { $in: peruBranchIds } }));

function countRejected(branchFilter) {
  const docs = db.news.find(
    { branchId: branchFilter, createdAt: { $gte: since } },
    { branchId: 1, "extraData.rejected": 1, _id: 0 }
  ).toArray();
  let total = docs.length;
  let rejectedByPlatform = docs.filter(d =>
    d.extraData && d.extraData.rejected &&
    (d.extraData.rejected.rejectMessageDescription || "").includes("rechazada por plataforma")
  ).length;
  return { total, rejectedByPlatform, rate: total > 0 ? (rejectedByPlatform / total * 100).toFixed(2) + "%" : "n/a" };
}

print("=== Peru (35 branches), last 7 days, news collection ===");
printjson(countRejected({ $in: peruBranchIds }));

print("=== Breakdown by Peru branch (only branches with >0 rejections) ===");
peruBranchIds.forEach(bId => {
  const r = countRejected(bId);
  if (r.rejectedByPlatform > 0) {
    print("branch " + bId + ": " + JSON.stringify(r));
  }
});
