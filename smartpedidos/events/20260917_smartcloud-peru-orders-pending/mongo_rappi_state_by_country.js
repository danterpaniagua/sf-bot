// Event: 20260917_smartcloud-peru-orders-pending (GITIN-2068)
// Checks whether the missing-orders.state gap found for Rappi/Peru also
// occurs for Rappi orders in other countries — i.e. whether the bug traced
// in platform.js/saveNewOrders() is Peru-specific or global to the Rappi
// integration. Non-interactive mongosh script, must explicitly print.

print("=== Rappi order state presence, by branch country, last 7 days ===");
db.orders.aggregate([
  { $match: {
      thirdParty: "Rappi",
      timestamp: { $gte: new Date(Date.now() - 7*24*60*60*1000) }
  }},
  { $lookup: {
      from: "branches",
      localField: "branchId",
      foreignField: "branchId",
      as: "branch"
  }},
  { $unwind: { path: "$branch", preserveNullAndEmptyArrays: true } },
  { $group: {
      _id: {
        country: { $ifNull: ["$branch.address.country", "UNKNOWN_BRANCH"] },
        hasState: { $cond: [ { $ifNull: ["$state", false] }, "has_state", "NO_STATE" ] }
      },
      count: { $sum: 1 }
  }},
  { $sort: { "_id.country": 1, "_id.hasState": 1 } }
]).forEach(doc => printjson(doc));

print("=== Same breakdown, ALL platforms (not just Rappi), for comparison ===");
db.orders.aggregate([
  { $match: {
      timestamp: { $gte: new Date(Date.now() - 7*24*60*60*1000) }
  }},
  { $lookup: {
      from: "branches",
      localField: "branchId",
      foreignField: "branchId",
      as: "branch"
  }},
  { $unwind: { path: "$branch", preserveNullAndEmptyArrays: true } },
  { $group: {
      _id: {
        country: { $ifNull: ["$branch.address.country", "UNKNOWN_BRANCH"] },
        thirdParty: "$thirdParty",
        hasState: { $cond: [ { $ifNull: ["$state", false] }, "has_state", "NO_STATE" ] }
      },
      count: { $sum: 1 }
  }},
  { $match: { "_id.hasState": "NO_STATE" } },
  { $sort: { "_id.country": 1, count: -1 } }
]).forEach(doc => printjson(doc));
