// Event: 20260917_smartcloud-peru-orders-pending (GITIN-2068)
// All orders, all 35 Peru branches, from 14:00 today (Argentina time,
// UTC-3) onward. Outputs directly as CSV lines (header + rows) so the
// redirected file needs no further conversion.

const peruBranches = db.branches.find(
  { "address.country": /per[uú]/i },
  { branchId: 1, name: 1, _id: 0 }
).toArray();
const branchIds = peruBranches.map(b => b.branchId);
const branchNames = {};
peruBranches.forEach(b => branchNames[b.branchId] = b.name);

// 14:00 ART (UTC-3) today = 17:00 UTC today
const cutoff = new Date("2026-09-17T17:00:00.000Z");

const orders = db.orders.find(
  { branchId: { $in: branchIds }, timestamp: { $gte: cutoff } },
  { originalId: 1, branchId: 1, thirdParty: 1, state: 1, timestamp: 1, createdAt: 1, _id: 1 }
).sort({ timestamp: 1 }).toArray();

function csvEscape(v) {
  if (v === undefined || v === null) return "";
  const s = String(v);
  return s.includes(",") ? '"' + s.replace(/"/g, '""') + '"' : s;
}

print("originalId,branchId,branchName,thirdParty,state,timestamp,mongoId");
orders.forEach(o => {
  print([
    csvEscape(o.originalId),
    csvEscape(o.branchId),
    csvEscape(branchNames[o.branchId]),
    csvEscape(o.thirdParty),
    csvEscape(o.state),
    csvEscape(o.timestamp ? o.timestamp.toISOString() : ""),
    csvEscape(o._id ? o._id.toString() : "")
  ].join(","));
});

print("=== total rows: " + orders.length + " ===");
