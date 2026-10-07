// Event: 20260917_gitin2069-peru-platform-rejections (GITIN-2069)
// Quantify "too many occurrences of 'Orden rechazada por plataforma' in
// Peru" -- count Peru vs a non-Peru baseline, last 7 days, to see if the
// rate is actually anomalous.

const peruBranches = db.branches.find(
  { "address.country": /per[uú]/i },
  { branchId: 1, _id: 0 }
).toArray();
const peruBranchIds = peruBranches.map(b => b.branchId);

const since = new Date(Date.now() - 7*24*60*60*1000);

function countRejected(branchFilter) {
  const docs = db.orders.find(
    { branchId: branchFilter, timestamp: { $gte: since } },
    { branchId: 1, order: 1, _id: 0 }
  ).toArray();
  let total = docs.length;
  let rejectedByPlatform = 0;
  docs.forEach(d => {
    const s = JSON.stringify(d.order || {});
    if (s.includes("rechazada por plataforma") || s.includes("Orden rechazada")) rejectedByPlatform++;
  });
  return { total, rejectedByPlatform, rate: total > 0 ? (rejectedByPlatform / total * 100).toFixed(2) + "%" : "n/a" };
}

print("=== Peru (35 branches), last 7 days ===");
printjson(countRejected({ $in: peruBranchIds }));

print("=== All branches (fleet-wide baseline), last 7 days ===");
printjson(countRejected({ $exists: true }));

print("=== Breakdown by Peru branch (only branches with >0 rejections) ===");
peruBranchIds.forEach(bId => {
  const r = countRejected(bId);
  if (r.rejectedByPlatform > 0) {
    print("branch " + bId + ": " + JSON.stringify(r));
  }
});
