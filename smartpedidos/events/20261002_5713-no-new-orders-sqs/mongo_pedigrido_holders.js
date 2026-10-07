// Read-only. Does any branch hold a PediGrido entry with branchReference "5713" or "5489"? (re-adding the entry on 5713
// would hit the unique index platform+branchReference+branchIdReference if one does). Also: does 5713 have a PediGrido entry now?
const pg = db.platforms.findOne({name: "PediGrido"}, {name: 1, internalCode: 1});
const holders = db.branches.aggregate([
  {$unwind: "$platforms"},
  {$match: {"platforms.platform": pg._id, "platforms.branchReference": {$in: ["5713", "5489"]}}},
  {$project: {_id: 0, branchId: 1, deletedAt: 1, reference: "$platforms.branchReference", isActive: "$platforms.isActive"}}
]).toArray();
const b = db.branches.findOne({branchId: 5713}, {platforms: 1});
const has = (b.platforms || []).some(p => String(p.platform) === String(pg._id));
print(EJSON.stringify({now: new Date(), pediGridoPlatformId: pg._id, pediGridoInternalCode: pg.internalCode,
  branchesHoldingPediGridoRef5713or5489: holders, branch5713HasPediGridoEntry: has}, {relaxed: true}, 2));
