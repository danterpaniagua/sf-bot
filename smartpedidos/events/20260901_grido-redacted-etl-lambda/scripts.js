// Field-inventory audit for GITIN-1874 (Grido redacted ETL) — run non-interactively:
//   mongosh "<connection string>" scripts.js > data/field_inventory_output.txt
// All read-only. Scoped to extraData.chain: /grido/i (confirmed filter criterion, see investigation.md).

const MATCH = { 'extraData.chain': /grido/i };
const LIMIT = 5000;

function inventory(label, unwindPath, projectPath) {
  print('=== ' + label + ' ===');
  const pipeline = [{ $match: MATCH }, { $limit: LIMIT }];
  if (unwindPath) pipeline.push({ $unwind: unwindPath });
  pipeline.push(
    { $project: { fields: { $objectToArray: projectPath } } },
    { $unwind: '$fields' },
    { $group: { _id: '$fields.k', count: { $sum: 1 } } },
    { $sort: { count: -1 } }
  );
  db.news.aggregate(pipeline).forEach((doc) => printjson(doc));
  print('');
}

inventory('Top-level fields', null, '$$ROOT');
inventory('order.* fields', null, '$order');
inventory('order.customer.* fields', null, '$order.customer');
inventory('order.details[].* fields', '$order.details', '$order.details');
inventory('order.payment.* fields', null, '$order.payment');
inventory('extraData.* fields', null, '$extraData');

// Check whether dni is "hiding" in order.observations for platforms where
// order.customer.dni comes back null (2026-09-02) - order.observations was
// already confirmed under GITIN-1873 to sometimes contain DNI/RUC/CI numbers
// as free text billing patterns. Example order.id values from 2026-08-28,
// one set per platform, all with customer.dni confirmed null.
print('=== dni-null examples: observations check ===');
db.news.find(
  {
    'order.id': { $in: [
      '2258795185', '2258776996', '2258796080',   // PedidosYa
      '2260085722', '478057211', '478063059',      // Rappi
      618629077, 415314436, 406970815,             // UberEats
      883715, 883703, 883690,                       // I+D
      '47881956688', '47881945252', '47881941752',  // MercadoPago
      5414917, 5413034, 5412107,                    // PediGrido (null exceptions)
      '5162743', '5162709'                          // Toque
    ]}
  },
  {
    _id: 0,
    'order.id': 1,
    'extraData.platform': 1,
    'order.customer.dni': 1,
    'order.observations': 1
  }
).forEach((doc) => printjson(doc));
