// Read-only. Compare branch 5713 with a reference branch that has recent non-rejected PediGrido
// orders. Prints structure only: key names, booleans, lengths. NO secrets: branchSecret, secret,
// credentials.* and all branchReference values (except PediGrido's, a store id) are never printed.
const since = new Date(Date.now() - 14*24*3600*1000);
const candidates = db.orders.aggregate([
  {$match: {thirdParty: "PediGrido", createdAt: {$gte: since}, branchId: {$ne: 5713},
            state: {$nin: ["REJECTED", "PENDING"]}}},
  {$group: {_id: "$branchId", n: {$sum: 1}, last: {$max: "$createdAt"}}},
  {$sort: {n: -1}}, {$limit: 5}
]).toArray();
const refId = candidates.length ? candidates[0]._id : null;

const pname = {};
db.platforms.find({}, {name: 1}).forEach(p => { pname[String(p._id)] = p.name; });

function summarize(id) {
  const b = db.branches.findOne({branchId: id});
  if (!b) return null;
  return {
    branchId: b.branchId, code: b.code, name: b.name, startDate: b.startDate,
    createdAt: b.createdAt, updatedAt: b.updatedAt, lastGetNews: b.lastGetNews,
    branchTimeout: b.branchTimeout, tzo: b.tzo, cloud: b.cloud,
    isCourierSuspended: b.isCourierSuspended, updaterVersion: b.updaterVersion,
    deletedAt: b.deletedAt, suspendedDate: b.suspendedDate,
    topLevelKeys: Object.keys(b).sort(),
    permissions: b.permissions,
    hasChain: !!b.chain, hasClient: !!b.client,
    address: b.address ? {country: b.address.country, province: b.address.province, city: b.address.city,
                          hasRegion: !!b.address.region, hasCoordinates: !!b.address.coordinates} : null,
    smartfran_sw: b.smartfran_sw ? {
      agentInstalled: b.smartfran_sw.agent && b.smartfran_sw.agent.installedVersion,
      agentNext: b.smartfran_sw.agent && b.smartfran_sw.agent.nextVersionToInstall,
      notificatorInstalled: b.smartfran_sw.notificator && b.smartfran_sw.notificator.installedVersion
    } : null,
    secretsPresent: {
      branchSecret: !!b.branchSecret, secret: !!b.secret,
      aws_id: !!(b.credentials && b.credentials.aws_id), aws_secret: !!(b.credentials && b.credentials.aws_secret)
    },
    deliveries: (b.deliveries || []).map(d => ({delivery: d.delivery, isActive: d.isActive, index: d.index, hasRef: !!d.branchReference})),
    platforms: (b.platforms || []).map(p => {
      const name = pname[String(p.platform)];
      const br = p.branchReference;
      return {
        name: name, isActive: p.isActive, StateAPI: p.StateAPI,
        hasBranchIdReference: !!p.branchIdReference,
        branchReferenceType: br === undefined || br === null ? null : (typeof br),
        branchReferenceLength: typeof br === "string" ? br.length : null,
        pediGridoRef: name === "PediGrido" ? br : undefined,
        pediGridoRefEqualsBranchId: name === "PediGrido" ? String(br) === String(b.branchId) : undefined,
        progClosedCount: (p.progClosed || []).length,
        rulesKeys: p.rules ? Object.keys(p.rules).sort() : null,
        autoBillingDelivered: p.autoBillingDelivered,
        keys: Object.keys(p).sort()
      };
    })
  };
}

const a = summarize(5713);
const r = refId === null ? null : summarize(refId);
const diff = {};
if (a && r) {
  diff.topLevelKeysOnlyIn5713 = a.topLevelKeys.filter(k => !r.topLevelKeys.includes(k));
  diff.topLevelKeysOnlyInRef = r.topLevelKeys.filter(k => !a.topLevelKeys.includes(k));
  diff.permissionsEqual = JSON.stringify(a.permissions) === JSON.stringify(r.permissions);
  diff.platformsByName = {};
  const names = new Set([...a.platforms.map(p => p.name), ...r.platforms.map(p => p.name)]);
  names.forEach(n => {
    const pa = a.platforms.find(p => p.name === n), pr = r.platforms.find(p => p.name === n);
    diff.platformsByName[n] = {in5713: !!pa, inRef: !!pr,
      isActive: [pa && pa.isActive, pr && pr.isActive],
      StateAPI: [pa && pa.StateAPI, pr && pr.StateAPI],
      hasBranchIdReference: [pa && pa.hasBranchIdReference, pr && pr.hasBranchIdReference],
      branchReferenceLength: [pa && pa.branchReferenceLength, pr && pr.branchReferenceLength]};
  });
}
print(EJSON.stringify({referenceBranchId: refId, candidates: candidates, branch5713: a, reference: r, diff: diff}, {relaxed: true}, 2));
