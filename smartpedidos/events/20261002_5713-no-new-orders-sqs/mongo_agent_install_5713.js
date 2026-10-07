// Read-only. When was the POS agent version installed on 5713 (vs reference 3013)?
// The SQS push in platforms-service is gated on agent installedVersion > 1.24 (or cloud === true).
// Prints versions and dates only. NEVER prints nextVersionUrl (may carry a token) or any secret.
function pick(id) {
  const b = db.branches.findOne({branchId: id}, {branchId: 1, createdAt: 1, updatedAt: 1, updaterVersion: 1,
    "smartfran_sw.agent.installedVersion": 1, "smartfran_sw.agent.installedDate": 1, "smartfran_sw.agent.nextVersionToInstall": 1,
    "smartfran_sw.notificator.installedVersion": 1, "smartfran_sw.notificator.installedDate": 1, "smartfran_sw.notificator.nextVersionToInstall": 1});
  return b;
}
print(EJSON.stringify({
  branch5713: pick(5713),
  branch3013: pick(3013),
  activeSoftware: db.activeSoftwares ? db.activeSoftwares.find({}, {"agent.actualVersion": 1, "agent.releaseDate": 1, "notificator.actualVersion": 1, "notificator.releaseDate": 1, updaterVersion: 1}).toArray() : null
}, {relaxed: true}, 2));
