// Volume of `news` docs received per platform, hourly, over :267's full in-service window
// (2026-09-26T00:30Z fri-night deploy -> 2026-09-28T11:20Z when :268 rollout started).
db.news.aggregate([
  {
    $match: {
      createdAt: {
        $gte: ISODate('2026-09-26T00:30:00Z'),
        $lte: ISODate('2026-09-28T11:20:00Z')
      }
    }
  },
  {
    $group: {
      _id: {
        hour: { $dateToString: { format: '%Y-%m-%dT%H:00', date: '$createdAt' } },
        thirdParty: '$thirdParty'
      },
      count: { $sum: 1 }
    }
  },
  { $sort: { '_id.hour': 1, '_id.thirdParty': 1 } }
]).forEach(doc => printjson(doc));

print('=== total news in window ===');
print(db.news.countDocuments({
  createdAt: { $gte: ISODate('2026-09-26T00:30:00Z'), $lte: ISODate('2026-09-28T11:20:00Z') }
}));
