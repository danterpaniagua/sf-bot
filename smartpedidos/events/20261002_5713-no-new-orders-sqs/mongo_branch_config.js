// Read-only. Usage: BID=<branchId> sfmongosh --quiet --file <this file> > out.json
// Prints non-secret configuration of one branch. Never prints branchSecret/secret/credentials/nextVersionUrl or any
// platform reference value (only booleans, lengths, key names). PediGrido: latest orders' state + POS-receipt delay.
const BID = Number(process.env.BID);
if (!BID) { print(JSON.stringify({error: "set BID=<branchId> in the environment"})); quit(1); }
const pname = {};
db.platforms.find({}, {name: 1}).forEach(p => { pname[String(p._id)] = p.name; });
const b = db.branches.findOne({branchId: BID});
if (!b) { print(JSON.stringify({branchId: BID, found: false})); quit(0); }

const platforms = (b.platforms || []).map(p => ({
  name: pname[String(p.platform)], isActive: p.isActive, StateAPI: p.StateAPI,
  hasBranchIdReference: !!p.branchIdReference,
  refType: typeof p.branchReference, refLength: typeof p.branchReference === "string" ? p.branchReference.length : null,
  refEqualsBranchId: String(p.branchReference) === String(b.branchId),
  progClosedCount: (p.progClosed || []).length, keys: Object.keys(p).sort()
}));

const since = new Date(Date.now() - 14*24*3600*1000);
const states = db.orders.aggregate([
  {$match: {branchId: BID, createdAt: {$gte: since}}},
  {$group: {_id: {thirdParty: "$thirdParty", state: "$state"}, n: {$sum: 1}, last: {$max: "$createdAt"}}},
  {$sort: {"_id.thirdParty": 1, n: -1}}
]).toArray();

// POS receipt = first trace with typeId 10; delay from news creation
function receiptDelaySec(n) {
  const t = (n.traces || []).find(x => x.update && x.update.typeId === 10);
  return t ? Math.round((t.createdAt - n.createdAt) / 1000) : null;
}
const pgLatest = db.orders.find({branchId: BID, thirdParty: "PediGrido"}, {createdAt: 1, state: 1}).sort({createdAt: -1}).limit(10).toArray()
  .map(o => {
    const n = db.news.findOne({branchId: BID, createdAt: o.createdAt}, {typeId: 1, createdAt: 1, traces: 1});
    return {createdAt: o.createdAt, orderState: o.state, newsFound: !!n, receiptDelaySec: n ? receiptDelaySec(n) : null};
  });

print(EJSON.stringify({
  now: new Date(), branchId: b.branchId, name: b.name, createdAt: b.createdAt, startDate: b.startDate,
  deletedAt: b.deletedAt, suspendedDate: b.suspendedDate, isSuspended: b.isSuspended, cloud: b.cloud,
  lastGetNews: b.lastGetNews, branchTimeout: b.branchTimeout, tzo: b.tzo, updaterVersion: b.updaterVersion,
  agent: b.smartfran_sw && b.smartfran_sw.agent ? {installed: b.smartfran_sw.agent.installedVersion, installedDate: b.smartfran_sw.agent.installedDate, next: b.smartfran_sw.agent.nextVersionToInstall} : null,
  hasChain: !!b.chain, hasClient: !!b.client, topLevelKeys: Object.keys(b).sort(),
  platforms: platforms, ordersLast14dByPlatformState: states, pediGridoLatest10: pgLatest
}, {relaxed: true}, 2));
