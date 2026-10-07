// Read-only. Timeline of the latest news of branch 5713 (any platform): state transitions and, if rejected,
// who rejected it (id / description / entity only, never the free-text note, no order body, no customer data).
const out = db.news.find({branchId: 5713}).sort({createdAt: -1}).limit(6).toArray().map(n => ({
  newsId: n._id, typeId: n.typeId, createdAt: n.createdAt, updatedAt: n.updatedAt, viewed: n.viewed,
  platform: n.extraData ? n.extraData.platform : null,
  rejected: n.extraData && n.extraData.rejected ? {
    rejectMessageId: n.extraData.rejected.rejectMessageId,
    rejectMessageDescription: n.extraData.rejected.rejectMessageDescription,
    entity: n.extraData.rejected.entity
  } : null,
  traces: (n.traces || []).map(t => ({
    createdAt: t.createdAt, updateTypeId: t.update && t.update.typeId, orderStatusId: t.update && t.update.orderStatusId,
    updateKeys: t.update ? Object.keys(t.update) : null
  }))
}));
const o = db.orders.find({branchId: 5713}, {thirdParty: 1, state: 1, createdAt: 1, updatedAt: 1, displayId: 1})
  .sort({createdAt: -1}).limit(6).toArray();
print(EJSON.stringify({now: new Date(), latestNews: out, latestOrders: o}, {relaxed: true}, 2));
