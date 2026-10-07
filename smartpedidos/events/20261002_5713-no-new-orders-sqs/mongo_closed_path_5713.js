// Read-only. Did platforms-service take the "restaurant closed -> no SQS push" path for 5713's orders?
// Prints only flags, key names, timestamps. No order body / customer data / secrets.
const news = db.news.find({branchId: 5713}).sort({createdAt: 1}).toArray();
const out = {};
out.newsAndClosedQueue = news.map(n => {
  const rc = db.orderrejcloseds.find({newId: n._id}).toArray();
  const ed = n.extraData || null;
  return {
    newsId: n._id, typeId: n.typeId, createdAt: n.createdAt, updatedAt: n.updatedAt, viewed: n.viewed,
    extraDataKeys: ed ? Object.keys(ed).sort() : null,
    extraDataRejected: ed && ed.rejected ? {
      rejectMessageId: ed.rejected.rejectMessageId,
      rejectMessageDescription: ed.rejected.rejectMessageDescription,
      entity: ed.rejected.entity
    } : null,
    orderRejClosed: rc.map(x => ({timestamp: x.timestamp, send: x.send, reSend: x.reSend, type: x.type, createdAt: x.createdAt, updatedAt: x.updatedAt}))
  };
});
const b = db.branches.findOne({branchId: 5713});
out.branchFlags = {
  isSuspended: b.isSuspended, alreadyClosedPeya: b.alreadyClosedPeya, alreadyClosedRappi: b.alreadyClosedRappi,
  alreadyClosedPediGrido: b.alreadyClosedPediGrido, alreadyClosedMercadoPago: b.alreadyClosedMercadoPago,
  rappiActive: b.rappiActive, autoReplyType: typeof b.autoReply,
  autoReplyKeys: b.autoReply && typeof b.autoReply === "object" ? Object.keys(b.autoReply).sort() : null,
  lastGetNews: b.lastGetNews, now: new Date(),
  pediGridoProgClosed: (b.platforms || []).filter(p => p.progClosed && p.progClosed.length).map(p => ({platform: p.platform, progClosed: p.progClosed}))
};
print(EJSON.stringify(out, {relaxed: true}, 2));
