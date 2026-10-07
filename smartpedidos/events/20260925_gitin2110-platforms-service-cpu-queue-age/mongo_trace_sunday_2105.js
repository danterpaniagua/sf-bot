// Trace candidate orders processed by setNews (i.e. dequeued from PRD_BranchMessages.fifo)
// right at/after the Sun 2026-09-27 21:05 ART queue-age spike (peak 374s).
// Window padded: 2026-09-28T00:02:00Z - 00:14:00Z UTC = 21:02-21:14 ART.
db.news.find(
  {
    updatedAt: {
      $gte: ISODate('2026-09-28T00:02:00Z'),
      $lte: ISODate('2026-09-28T00:14:00Z')
    }
  },
  {
    _id: 1,
    typeId: 1,
    branchId: 1,
    createdAt: 1,
    updatedAt: 1,
    'order.originalId': 1,
    'order.thirdParty': 1,
    'order.id': 1
  }
).sort({ updatedAt: 1 }).forEach(doc => {
  const gapSeconds = (doc.updatedAt - doc.createdAt) / 1000;
  printjson(Object.assign({}, doc, { gapSeconds }));
});

print('=== count in window ===');
print(db.news.countDocuments({
  updatedAt: { $gte: ISODate('2026-09-28T00:02:00Z'), $lte: ISODate('2026-09-28T00:14:00Z') }
}));
