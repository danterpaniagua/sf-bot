// Read-only. Old branch number 5489 vs new 5713 after the renumbering. Structure/flags/timestamps only,
// no secrets, no reference values printed (only which branchIds hold the PedidosYa reference).
const pname = {};
db.platforms.find({}, {name: 1}).forEach(p => { pname[String(p._id)] = p.name; });

function brief(id) {
  const b = db.branches.findOne({branchId: id});
  if (!b) return null;
  return {
    branchId: b.branchId, name: b.name, createdAt: b.createdAt, updatedAt: b.updatedAt, deletedAt: b.deletedAt,
    suspendedDate: b.suspendedDate, isSuspended: b.isSuspended, cloud: b.cloud, lastGetNews: b.lastGetNews,
    agent: b.smartfran_sw && b.smartfran_sw.agent ? {v: b.smartfran_sw.agent.installedVersion, d: b.smartfran_sw.agent.installedDate} : null,
    platforms: (b.platforms || []).map(p => ({name: pname[String(p.platform)], isActive: p.isActive, StateAPI: p.StateAPI, hasBranchIdReference: !!p.branchIdReference}))
  };
}

const since = new Date(Date.now() - 30*24*3600*1000);
const ordersOld = db.orders.aggregate([
  {$match: {branchId: 5489, createdAt: {$gte: since}}},
  {$group: {_id: {thirdParty: "$thirdParty", state: "$state"}, n: {$sum: 1}, last: {$max: "$createdAt"}}},
  {$sort: {last: -1}}
]).toArray();

// Which branches hold the PedidosYa branchIdReference that 5713 has?
const b5713 = db.branches.findOne({branchId: 5713}, {platforms: 1});
const peya = (b5713.platforms || []).find(p => pname[String(p.platform)] === "PedidosYa");
const holders = peya && peya.branchIdReference
  ? db.branches.find({"platforms.branchIdReference": peya.branchIdReference}, {branchId: 1, deletedAt: 1}).toArray() : null;

print(EJSON.stringify({
  now: new Date(),
  branch5489: brief(5489),
  branch5713: brief(5713),
  ordersFor5489Last30d: ordersOld,
  branchesHoldingPedidosYaRefOf5713: holders
}, {relaxed: true}, 2));
