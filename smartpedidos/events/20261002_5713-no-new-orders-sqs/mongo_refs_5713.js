// Read-only. Inbound mapping check after the renumbering 5489 -> 5713.
// platforms-service maps an incoming order to a branch by string-matching the platform's order branch code
// against branches.platforms.branchReference (getOrderBranches). Print only whether each platform entry's
// branchReference equals the NEW or the OLD number; never the value itself.
const pname = {};
db.platforms.find({}, {name: 1}).forEach(p => { pname[String(p._id)] = p.name; });
const b = db.branches.findOne({branchId: 5713}, {platforms: 1});
const entries = (b.platforms || []).map(p => ({
  name: pname[String(p.platform)], isActive: p.isActive,
  refType: typeof p.branchReference, refLength: typeof p.branchReference === "string" ? p.branchReference.length : null,
  refEqualsNew5713: String(p.branchReference) === "5713",
  refEqualsOld5489: String(p.branchReference) === "5489"
}));
const stillOld = db.branches.aggregate([
  {$unwind: "$platforms"},
  {$match: {"platforms.branchReference": "5489"}},
  {$project: {_id: 0, branchId: 1, platform: "$platforms.platform", deletedAt: 1}}
]).toArray().map(x => ({branchId: x.branchId, platform: pname[String(x.platform)], deletedAt: x.deletedAt}));
print(EJSON.stringify({now: new Date(), entriesOf5713: entries, anyBranchWithPlatformRefEqualTo5489: stillOld}, {relaxed: true}, 2));
