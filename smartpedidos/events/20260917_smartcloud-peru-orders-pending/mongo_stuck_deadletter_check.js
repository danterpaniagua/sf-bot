// Event: 20260917_smartcloud-peru-orders-pending (GITIN-2068)
// Checks whether any of the 12 genuinely-stuck Peru orders (see
// mongo_peru_stuck_ids.js output) ever landed in the AWS SQS dead-letter
// capture (concentrador-service's deadLetterModel -> `deadletters`
// collection). A hit here would mean SmartCloud's Orders API consumer
// received the message and failed to process it repeatedly (maxReceiveCount
// exhausted); no hit means it either never reached SQS at all, or is still
// sitting in the live per-branch queue retrying forever (see
// cloud/events/20260917_smartpedidos-peru-orders-pending/investigation.md
// "Failure handling" section).

const stuckOriginalIds = [
  '5454662', '2260808327', '2270509683', '2261092537', '2275382811',
  '2276088336', '2261439040', '2279219022', '2279162694', '5507077',
  '2280301259', '2261933306'
];

print("=== deadletters collection: total doc count (sanity check the collection exists/has data) ===");
print(db.deadletters.countDocuments({}));

print("=== deadletters matching any of the 12 stuck order IDs (searched in body as text) ===");
stuckOriginalIds.forEach(id => {
  const matches = db.deadletters.find({ body: { $regex: id } }).toArray();
  if (matches.length > 0) {
    print("--- MATCH for order id " + id + " ---");
    matches.forEach(m => printjson(m));
  } else {
    print("no match for order id " + id);
  }
});
