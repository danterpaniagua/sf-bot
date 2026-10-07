// Event: 20260917_smartcloud-peru-orders-pending (GITIN-2068)
// Non-interactive mongosh script — must explicitly print, no top-level auto-print.
// Run: mongosh "<connection>" mongo_peru_orders_query.js > <event>/data/<name>.txt

print("=== 1. Peru branches (address.country matches Peru/Perú) ===");
const peruBranches = db.branches.find(
  { "address.country": /per[uú]/i },
  { branchId: 1, name: 1, "address.country": 1, "address.city": 1, cloud: 1, deletedAt: 1, _id: 0 }
).toArray();
peruBranches.forEach(doc => printjson(doc));

const branchIds = peruBranches.map(b => b.branchId);
print("=== branchIds found: " + JSON.stringify(branchIds) + " ===");

if (branchIds.length > 0) {
  print("=== 2. Order state counts for these branches, last 7 days ===");
  db.orders.aggregate([
    { $match: {
        branchId: { $in: branchIds },
        timestamp: { $gte: new Date(Date.now() - 7*24*60*60*1000) }
    }},
    { $group: { _id: "$state", count: { $sum: 1 } } },
    { $sort: { count: -1 } }
  ]).forEach(doc => printjson(doc));

  print("=== 3. Most recent 20 orders for these branches ===");
  db.orders.find(
    { branchId: { $in: branchIds } },
    { orderId: 1, branchId: 1, state: 1, thirdParty: 1, timestamp: 1, createdAt: 1, _id: 0 }
  ).sort({ timestamp: -1 }).limit(20).forEach(doc => printjson(doc));
} else {
  print("=== No Peru branches found — nothing to query in steps 2/3 ===");
}
