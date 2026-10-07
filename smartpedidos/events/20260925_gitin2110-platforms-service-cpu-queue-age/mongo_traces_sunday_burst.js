// Full traces[] for a sample of orders caught in the 00:06:23-00:06:34 UTC burst
// (21:06:23-21:06:34 ART, Sun 2026-09-27/28) -- to see per-transition timing,
// not just the doc's overall updatedAt.
const sample = db.news.find(
  {
    updatedAt: {
      $gte: ISODate('2026-09-28T00:06:23.000Z'),
      $lte: ISODate('2026-09-28T00:06:34.999Z')
    }
  },
  {
    _id: 1,
    typeId: 1,
    branchId: 1,
    'order.originalId': 1,
    createdAt: 1,
    updatedAt: 1,
    traces: 1
  }
).limit(15).toArray();

sample.forEach(doc => {
  print('=== news _id=' + doc._id + ' order=' + (doc.order && doc.order.originalId) + ' branch=' + doc.branchId + ' typeId=' + doc.typeId + ' ===');
  print('doc createdAt: ' + doc.createdAt + '  doc updatedAt: ' + doc.updatedAt);
  if (Array.isArray(doc.traces)) {
    let prev = doc.createdAt;
    doc.traces.forEach((t, i) => {
      const deltaSec = (t.createdAt - prev) / 1000;
      print('  trace[' + i + '] at ' + t.createdAt + '  (+' + deltaSec + 's since prev)  update=' + JSON.stringify(t.update));
      prev = t.createdAt;
    });
  } else {
    print('  (no traces array)');
  }
});

print('=== sample count ===');
print(sample.length);
