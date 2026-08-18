// Run against smartfran.news (PedidosSmartfran cluster). Paste output back.
// All read-only.

// 1. Volume and date range for Grido-branded news (any platform)
db.news.aggregate([
  { $match: { 'extraData.chain': /grido/i } },
  { $group: { _id: null, total: { $sum: 1 }, from: { $min: '$createdAt' }, to: { $max: '$createdAt' } } }
])

// 2. Breakdown by originating platform
db.news.aggregate([
  { $match: { 'extraData.chain': /grido/i } },
  { $group: { _id: '$extraData.platform', count: { $sum: 1 } } },
  { $sort: { count: -1 } }
])

// 3. Top-level field inventory actually present (catches strict:false ad-hoc keys)
db.news.aggregate([
  { $match: { 'extraData.chain': /grido/i } },
  { $limit: 2000 },
  { $project: { fields: { $objectToArray: '$$ROOT' } } },
  { $unwind: '$fields' },
  { $group: { _id: '$fields.k', count: { $sum: 1 } } },
  { $sort: { count: -1 } }
])

// 4. order.* field inventory (same technique, one level down)
db.news.aggregate([
  { $match: { 'extraData.chain': /grido/i } },
  { $limit: 2000 },
  { $project: { fields: { $objectToArray: '$order' } } },
  { $unwind: '$fields' },
  { $group: { _id: '$fields.k', count: { $sum: 1 } } },
  { $sort: { count: -1 } }
])

// 5. order.customer.* field inventory + non-null population rate for PII fields
db.news.aggregate([
  { $match: { 'extraData.chain': /grido/i } },
  { $limit: 2000 },
  { $project: {
      hasName: { $cond: [{ $ifNull: ['$order.customer.name', false] }, 1, 0] },
      hasPhone: { $cond: [{ $ifNull: ['$order.customer.phone', false] }, 1, 0] },
      hasEmail: { $cond: [{ $ifNull: ['$order.customer.email', false] }, 1, 0] },
      hasAddress: { $cond: [{ $ifNull: ['$order.customer.address', false] }, 1, 0] },
      hasDni: { $cond: [{ $ifNull: ['$order.customer.dni', false] }, 1, 0] },
      hasLoyaltyCard: { $cond: [{ $ifNull: ['$order.customer.numeroTarjetaLoyalty', false] }, 1, 0] }
  }},
  { $group: { _id: null,
      total: { $sum: 1 },
      withName: { $sum: '$hasName' },
      withPhone: { $sum: '$hasPhone' },
      withEmail: { $sum: '$hasEmail' },
      withAddress: { $sum: '$hasAddress' },
      withDni: { $sum: '$hasDni' },
      withLoyaltyCard: { $sum: '$hasLoyaltyCard' }
  }}
])

// 6. One redacted sample document to eyeball full shape (paste with PII manually blacked out before sharing outside this repo)
db.news.findOne({ 'extraData.chain': /grido/i, typeId: { $exists: true } })

// 7. Does traces[] re-embed full order.customer PII on every state transition, or just a diff?
db.news.aggregate([
  { $match: { 'extraData.chain': /grido/i, 'traces.1': { $exists: true } } },
  { $limit: 1 },
  { $project: { traces: 1 } }
])
