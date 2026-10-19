["orders", "ordersFaileds", "ordertimes", "orderrejcloseds"].forEach(name => {
  try {
    const s = db.getCollection(name).stats({ scale: 1024 * 1024 });
    print(JSON.stringify({
      coll: name,
      count: s.count,
      dataMB: s.size,
      avgObjBytes: s.avgObjSize,
      storageMB: s.storageSize,
      totalIndexMB: s.totalIndexSize,
      indexMB: s.indexSizes
    }));
  } catch (e) {
    print(JSON.stringify({ coll: name, error: e.message }));
  }
});
print(JSON.stringify({ allCollections: db.getCollectionNames() }));
