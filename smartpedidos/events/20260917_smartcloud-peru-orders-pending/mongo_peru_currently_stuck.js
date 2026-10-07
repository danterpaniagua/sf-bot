// Event: 20260917_smartcloud-peru-orders-pending (GITIN-2068)
// Checks the claim "all Peru orders are stuck" directly: every order
// currently sitting at PENDING (or with no state at all) across all 35 Peru
// branches, right now, with its real age — not a 7-day historical aggregate.
// Non-interactive mongosh script, must explicitly print.

const peruBranches = db.branches.find(
  { "address.country": /per[uú]/i },
  { branchId: 1, _id: 0 }
).toArray();
const branchIds = peruBranches.map(b => b.branchId);
print("=== Peru branchIds: " + JSON.stringify(branchIds) + " ===");

print("=== ALL currently-open orders (PENDING or missing state) for Peru branches, any age ===");
const stuck = db.orders.find(
  {
    branchId: { $in: branchIds },
    $or: [ { state: "PENDING" }, { state: { $exists: false } }, { state: null } ]
  },
  { orderId: 1, branchId: 1, state: 1, thirdParty: 1, timestamp: 1, createdAt: 1, _id: 0 }
).sort({ timestamp: 1 }).toArray();

print("=== Total currently stuck/no-state orders: " + stuck.length + " ===");
const now = new Date();
stuck.forEach(doc => {
  const ageMin = Math.round((now - new Date(doc.timestamp)) / 60000);
  printjson(Object.assign({}, doc, { ageMinutes: ageMin }));
});

print("=== Breakdown by thirdParty ===");
const byPlatform = {};
stuck.forEach(doc => {
  byPlatform[doc.thirdParty] = (byPlatform[doc.thirdParty] || 0) + 1;
});
printjson(byPlatform);

print("=== Total orders (any state) for Peru branches, last 24h, for context ===");
print(db.orders.countDocuments({
  branchId: { $in: branchIds },
  timestamp: { $gte: new Date(Date.now() - 24*60*60*1000) }
}));
