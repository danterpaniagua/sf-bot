// Event: 20260917_smartcloud-peru-orders-pending (GITIN-2068)
// Definitive, no-cutoff list of ALL Peru orders currently sitting at
// PENDING or with no state field at all, any age -- supersedes the earlier
// 12-order list (which used a >24h-old cutoff and would miss both
// boundary cases and any new order stuck since today's live bug, which
// wouldn't be 24h old yet). Outputs as CSV.

const peruBranches = db.branches.find(
  { "address.country": /per[uú]/i },
  { branchId: 1, name: 1, _id: 0 }
).toArray();
const branchIds = peruBranches.map(b => b.branchId);
const branchNames = {};
peruBranches.forEach(b => branchNames[b.branchId] = b.name);

const stuck = db.orders.find(
  {
    branchId: { $in: branchIds },
    $or: [ { state: "PENDING" }, { state: { $exists: false } }, { state: null } ]
  }
).sort({ timestamp: 1 }).toArray();

function csvEscape(v) {
  if (v === undefined || v === null) return "";
  const s = String(v);
  return s.includes(",") ? '"' + s.replace(/"/g, '""') + '"' : s;
}

print("originalId,branchId,branchName,thirdParty,state,timestamp,ageMinutesNow,mongoId");
const now = Date.now();
stuck.forEach(o => {
  const ageMin = o.timestamp ? Math.round((now - new Date(o.timestamp).getTime()) / 60000) : "";
  print([
    csvEscape(o.originalId),
    csvEscape(o.branchId),
    csvEscape(branchNames[o.branchId]),
    csvEscape(o.thirdParty),
    csvEscape(o.state),
    csvEscape(o.timestamp ? new Date(o.timestamp).toISOString() : ""),
    csvEscape(ageMin),
    csvEscape(o._id ? o._id.toString() : "")
  ].join(","));
});
print("=== TOTAL: " + stuck.length + " ===");
