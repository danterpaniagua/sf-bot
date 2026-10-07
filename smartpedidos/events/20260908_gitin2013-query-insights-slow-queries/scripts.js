print('=== Profiling status (smartfran) ===');
try {
  printjson(db.getProfilingStatus());
} catch (e) {
  print(`getProfilingStatus() error: ${e.codeName || e.message}`);
}

print('\n=== Recent slow entries from system.profile (if profiling enabled) ===');
try {
  db.system.profile.find().sort({ ts: -1 }).limit(50).forEach(op => {
    print(`${op.ts} | ns: ${op.ns} | op: ${op.op} | millis: ${op.millis} | docsExamined: ${op.docsExamined} | nreturned: ${op.nreturned} | command: ${JSON.stringify(op.command || op.query || {})}`);
  });
} catch (e) {
  print(`system.profile query error: ${e.codeName || e.message}`);
}

print('\n=== Currently running operations over 1s (live snapshot, read-only) ===');
try {
  db.currentOp({ "secs_running": { $gt: 1 }, "ns": /^smartfran\./ }).inprog.forEach(op => {
    print(`secs_running: ${op.secs_running} | ns: ${op.ns} | op: ${op.op} | command: ${JSON.stringify(op.command || {})}`);
  });
} catch (e) {
  print(`currentOp() error: ${e.codeName || e.message}`);
}
