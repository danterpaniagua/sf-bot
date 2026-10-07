// Event: 20260917_smartcloud-peru-orders-pending (GITIN-2068)
// Baseline: for Peru orders that DID move off PENDING, how long did that
// take? Uses (updatedAt - timestamp) as a proxy for "time until last state
// change" (the orders collection only stores current state, not a full
// transition history, so this approximates time-to-last-update rather than
// time-to-first-transition specifically). Lets us quantify how anomalous
// the 2.8-13.7 day age of the genuinely-stuck orders (see
// mongo_peru_stuck_ids.js) really is against normal processing time.

const peruBranches = db.branches.find(
  { "address.country": /per[uú]/i },
  { branchId: 1, _id: 0 }
).toArray();
const branchIds = peruBranches.map(b => b.branchId);

print("=== Orders, Peru branches, last 7 days, state != PENDING/missing (i.e. moved on) ===");
const moved = db.orders.find(
  {
    branchId: { $in: branchIds },
    timestamp: { $gte: new Date(Date.now() - 7*24*60*60*1000) },
    state: { $exists: true, $ne: "PENDING" }
  },
  { branchId: 1, state: 1, thirdParty: 1, timestamp: 1, updatedAt: 1, _id: 0 }
).toArray();

const minutesToChange = moved
  .filter(d => d.updatedAt && d.timestamp)
  .map(d => (new Date(d.updatedAt) - new Date(d.timestamp)) / 60000)
  .sort((a, b) => a - b);

function pct(arr, p) {
  if (arr.length === 0) return null;
  const idx = Math.floor(arr.length * p);
  return arr[Math.min(idx, arr.length - 1)];
}

print("=== Time-to-last-update distribution (minutes), n=" + minutesToChange.length + " ===");
printjson({
  min: minutesToChange[0],
  p50_median: pct(minutesToChange, 0.5),
  p90: pct(minutesToChange, 0.9),
  p95: pct(minutesToChange, 0.95),
  p99: pct(minutesToChange, 0.99),
  max: minutesToChange[minutesToChange.length - 1]
});

print("=== Same breakdown, by final state ===");
const byState = {};
moved.forEach(d => {
  if (!d.updatedAt || !d.timestamp) return;
  const mins = (new Date(d.updatedAt) - new Date(d.timestamp)) / 60000;
  if (!byState[d.state]) byState[d.state] = [];
  byState[d.state].push(mins);
});
Object.keys(byState).forEach(state => {
  const arr = byState[state].sort((a, b) => a - b);
  printjson({
    state: state,
    count: arr.length,
    median_minutes: pct(arr, 0.5),
    p95_minutes: pct(arr, 0.95),
    max_minutes: arr[arr.length - 1]
  });
});

print("=== By platform (thirdParty) ===");
const byPlatform = {};
moved.forEach(d => {
  if (!d.updatedAt || !d.timestamp) return;
  const mins = (new Date(d.updatedAt) - new Date(d.timestamp)) / 60000;
  if (!byPlatform[d.thirdParty]) byPlatform[d.thirdParty] = [];
  byPlatform[d.thirdParty].push(mins);
});
Object.keys(byPlatform).forEach(tp => {
  const arr = byPlatform[tp].sort((a, b) => a - b);
  printjson({
    thirdParty: tp,
    count: arr.length,
    median_minutes: pct(arr, 0.5),
    p95_minutes: pct(arr, 0.95),
    max_minutes: arr[arr.length - 1]
  });
});
