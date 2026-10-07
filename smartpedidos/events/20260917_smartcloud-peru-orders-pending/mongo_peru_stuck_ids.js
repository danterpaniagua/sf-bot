// Event: 20260917_smartcloud-peru-orders-pending (GITIN-2068)
// Pull real identifiers for the genuinely stuck (>1 day old) Peru orders
// found by mongo_peru_currently_stuck.js, so they can be traced directly
// against Graylog/the SmartCloud Orders API on the cloud side.

const peruBranches = db.branches.find(
  { "address.country": /per[uú]/i },
  { branchId: 1, name: 1, _id: 0 }
).toArray();
const branchIds = peruBranches.map(b => b.branchId);
const branchNames = {};
peruBranches.forEach(b => branchNames[b.branchId] = b.name);

const cutoff = new Date(Date.now() - 24*60*60*1000); // older than 1 day = genuinely stuck per the earlier bimodal split
const stuck = db.orders.find(
  {
    branchId: { $in: branchIds },
    timestamp: { $lt: cutoff },
    $or: [ { state: "PENDING" }, { state: { $exists: false } }, { state: null } ]
  }
).sort({ timestamp: 1 }).toArray();

print("=== Genuinely stuck Peru orders (>24h old), full identifiers ===");
stuck.forEach(doc => {
  printjson({
    _id: doc._id.toString(),
    branchId: doc.branchId,
    branchName: branchNames[doc.branchId],
    thirdParty: doc.thirdParty,
    internalCode: doc.internalCode,
    originalId: doc.originalId,
    displayId: doc.displayId,
    posId: doc.posId,
    state: doc.state,
    orderNestedId: doc.order ? doc.order.id : undefined,
    orderStatusId: doc.order ? doc.order.statusId : undefined,
    timestamp: doc.timestamp,
    ageDays: Math.round((Date.now() - doc.timestamp) / 86400000 * 10) / 10
  });
});
print("=== Total: " + stuck.length + " ===");
