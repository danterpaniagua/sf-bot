// Event: 20260917_smartcloud-peru-orders-pending (GITIN-2068)
// Pending / no-state orders for branches 5615 and 5424 specifically, any age.

const branchIds = [5615, 5424];

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

print("originalId,branchId,thirdParty,state,timestamp,ageMinutesNow,mongoId");
const now = Date.now();
stuck.forEach(o => {
  const ageMin = o.timestamp ? Math.round((now - new Date(o.timestamp).getTime()) / 60000) : "";
  print([
    csvEscape(o.originalId),
    csvEscape(o.branchId),
    csvEscape(o.thirdParty),
    csvEscape(o.state),
    csvEscape(o.timestamp ? new Date(o.timestamp).toISOString() : ""),
    csvEscape(ageMin),
    csvEscape(o._id ? o._id.toString() : "")
  ].join(","));
});
print("=== TOTAL: " + stuck.length + " ===");
