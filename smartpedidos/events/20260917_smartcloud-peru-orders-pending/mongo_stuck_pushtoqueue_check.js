// Event: 20260917_smartcloud-peru-orders-pending (GITIN-2068)
// Checks whether platforms-service ever logged a pushNewToQueue failure
// (api/src/platforms/provider/aws.js) for any of the 12 stuck Peru orders,
// which would confirm the order never reached AWS SQS at all (as opposed to
// reaching it and retrying forever, or reaching the DLQ — already ruled out
// dead-letter in the previous check).

const stuckOrders = [
  { originalId: '5454662',    branchId: 5491, ts: new Date('2026-09-04T00:45:34.419Z') },
  { originalId: '2260808327', branchId: 5522, ts: new Date('2026-09-05T00:10:10.097Z') },
  { originalId: '2270509683', branchId: 5610, ts: new Date('2026-09-06T03:13:38.572Z') },
  { originalId: '2261092537', branchId: 5522, ts: new Date('2026-09-07T00:53:10.079Z') },
  { originalId: '2275382811', branchId: 5647, ts: new Date('2026-09-09T19:51:29.986Z') },
  { originalId: '2276088336', branchId: 5522, ts: new Date('2026-09-10T02:57:55.119Z') },
  { originalId: '2261439040', branchId: 5491, ts: new Date('2026-09-10T20:31:10.116Z') },
  { originalId: '2279219022', branchId: 5440, ts: new Date('2026-09-12T03:11:41.010Z') },
  { originalId: '2279162694', branchId: 5440, ts: new Date('2026-09-12T03:22:06.336Z') },
  { originalId: '5507077',    branchId: 5396, ts: new Date('2026-09-12T23:29:07.233Z') },
  { originalId: '2280301259', branchId: 5481, ts: new Date('2026-09-12T23:29:20.823Z') },
  { originalId: '2261933306', branchId: 5435, ts: new Date('2026-09-14T22:25:10.091Z') }
];

print("=== logerrors collection: total doc count (sanity check) ===");
print(db.logerrors.countDocuments({}));

print("=== pushNewToQueue failures overall, ever (broad check the log path even fires) ===");
print(db.logerrors.countDocuments({ message: /pushNewToQueue failed/ }));

print("=== pushNewToQueue failures matching our 12 stuck branchIds, +/- 10 min of each order's timestamp ===");
stuckOrders.forEach(o => {
  const windowStart = new Date(o.ts.getTime() - 10*60*1000);
  const windowEnd = new Date(o.ts.getTime() + 10*60*1000);
  const matches = db.logerrors.find({
    message: /pushNewToQueue failed/,
    branch_id: o.branchId,
    createdAt: { $gte: windowStart, $lte: windowEnd }
  }).toArray();
  if (matches.length > 0) {
    print("--- MATCH for order " + o.originalId + " (branch " + o.branchId + ") ---");
    matches.forEach(m => printjson(m));
  } else {
    print("no pushNewToQueue error logged for order " + o.originalId + " (branch " + o.branchId + ") in its +/-10min window");
  }
});

print("=== Any INFRA-category error at all for these branchIds, +/- 10 min of each order (broader net) ===");
stuckOrders.forEach(o => {
  const windowStart = new Date(o.ts.getTime() - 10*60*1000);
  const windowEnd = new Date(o.ts.getTime() + 10*60*1000);
  const matches = db.logerrors.find({
    category: "INFRA",
    branch_id: o.branchId,
    createdAt: { $gte: windowStart, $lte: windowEnd }
  }).toArray();
  if (matches.length > 0) {
    print("--- INFRA error near order " + o.originalId + " (branch " + o.branchId + ") ---");
    matches.forEach(m => printjson(m));
  }
});
