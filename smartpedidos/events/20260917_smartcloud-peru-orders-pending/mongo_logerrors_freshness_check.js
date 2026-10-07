// Sanity check: is platforms-service's logerrors collection actually still
// receiving writes, or is it dead (mongoLogEnabled:false at runtime) as
// prior project memory states? mongoLogEnabled is DB-config-driven
// (index.js reads it from a runtime config doc), not hardcoded, so verify
// fresh rather than trust the source read alone.
print("=== logerrors: most recent document timestamp ===");
db.logerrors.aggregate([
  { $sort: { createdAt: -1 } },
  { $limit: 1 },
  { $project: { createdAt: 1, message: 1, _id: 0 } }
]).forEach(doc => printjson(doc));

print("=== logerrors: count in last 24h (should be 0 if dead) ===");
print(db.logerrors.countDocuments({ createdAt: { $gte: new Date(Date.now() - 24*60*60*1000) } }));
