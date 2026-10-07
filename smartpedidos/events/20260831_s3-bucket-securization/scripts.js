// Samples order.observations values matching PII-shaped patterns, to gather
// fresh real-data evidence for the REDACT classification on this field
// (field-classification.md, GITIN-1873) vs. the new export allow-list under
// discussion for GITIN-1880. Read-only, no state change.
db.news.aggregate([
  {
    $match: {
      "order.observations": { $exists: true, $ne: null, $ne: "" },
      $or: [
        { "order.observations": /\d{7,}/ },      // any 7+ digit run — DNI-length (~7-8) or phone-length (~10)
        { "order.observations": /facturar/i },     // billing-note prefix
        { "order.observations": /llam[aá]/i }      // "llamame"/"llama cuando llegues" pattern
      ]
    }
  },
  { $sample: { size: 20 } },
  { $project: { _id: 0, "order.observations": 1 } }
]).forEach(doc => printjson(doc))

// Same check, scoped specifically to order.tenant.name: "grido" — the confirmed
// export scope filter as of 2026-09-01 (reversing an earlier extraData.platform:
// "PediGrido" guess, corrected 2026-09-16 — this query was still on the stale filter).
print("--- order.tenant.name: grido only ---")
db.news.aggregate([
  {
    $match: {
      "order.tenant.name": "grido",
      "order.observations": { $exists: true, $ne: null, $ne: "" }
    }
  },
  { $sample: { size: 20 } },
  { $project: { _id: 0, "order.observations": 1 } }
]).forEach(doc => printjson(doc))
