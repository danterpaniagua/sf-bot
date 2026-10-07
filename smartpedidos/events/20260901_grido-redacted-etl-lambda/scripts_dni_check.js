// Check whether dni is "hiding" in order.observations for platforms where
// order.customer.dni comes back null (2026-09-02) - order.observations was
// already confirmed under GITIN-1873 to sometimes contain DNI/RUC/CI numbers
// as free text billing patterns. Example order.id values from 2026-08-28,
// one set per platform, all with customer.dni confirmed null.
// Run: mongosh "<connection string>" scripts_dni_check.js > data/dni_observations_check.txt

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
