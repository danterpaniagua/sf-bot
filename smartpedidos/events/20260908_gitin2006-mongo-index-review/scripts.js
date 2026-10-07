['branches', 'ordertimes'].forEach(name => {
  print(`\n=== ${name} ===`);
  db.getCollection(name).getIndexes().forEach(idx => {
    print(`  ${idx.name} | key: ${JSON.stringify(idx.key)}`);
  });
});
