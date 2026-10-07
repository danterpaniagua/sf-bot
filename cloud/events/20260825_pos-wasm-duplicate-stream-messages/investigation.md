# Investigation — duplicated messages in Default Stream and PROD-Pos-AppServicePlan (GITIN-1933)

**Status:** root cause confirmed, fix applied and verified live on both PROD and DEV against real post-fix traffic. Open items: historical duplicate cleanup (undecided) and Jira reporting (undecided).

## Objective

Ticket reports duplicated messages appearing in both **Default Stream** and **PROD-Pos-AppServicePlan** for `Service:"smartfran-pos-wasm"` traffic. Determine root cause and fix.

Jira: [GITIN-1933](https://smartit-ar.atlassian.net/browse/GITIN-1933)

## Related prior work (same traffic, previous ticket)

`cloud/events/20260824_poswasmrelay-pro-graylog/investigation.md` (GITIN-1924, 2026-08-24) implemented Graylog routing for this exact `Service`/`Environment` traffic:

- Two Pipeline Rules (`route_to_stream()` only, no `remove_from_stream()`), connected to **Default Stream**:
  - `Service=="smartfran-pos-wasm" && Environment=="Development"` → `route_to_stream(name: "DEV")`
  - `Service=="smartfran-pos-wasm" && Environment=="Production"` → `route_to_stream(name: "PROD-Pos-AppServicePlan")`
- That investigation's own evidence already showed dual stream membership and treated it as expected/working, not a defect: a confirmed DEV-routed message (`_id: 82260621-9fd0-11f1-8f28-7c1e52beabec`) carried `streams: ["000000000000000000000001", "6a7a1b8a34e7b9a985f43cbc"]` — i.e. **both** Default Stream (`000000000000000000000001`) and the DEV stream.

## Confirmed against live Graylog (2026-08-25)

Views Search API, `Service:"smartfran-pos-wasm" AND Environment:"Production"`, last 7 days (`total_results: 829`): every sampled `_id` (e.g. `61a211c0-a082-11f1-8f28-7c1e52beabec`) appears **twice** in the result set — identical `streams: ["000000000000000000000001", "6a7cb1884814bcaed30a8744"]` both times, but under two different `index` values: `graylog_4` (Default Stream's index set) and `pos__1` (a dedicated index set, presumably the target stream's — name not yet independently confirmed via `GET /streams/{id}`).

**Root cause, refined from the original theory:** this isn't only dual stream *membership* (cosmetic). Because the second stream (`6a7cb1884814bcaed30a8744`) has its own dedicated index set (`pos__1`) — the same pattern GITIN-1924 confirmed for the DEV stream/`dev__6` — a message that stays in Default Stream *and* gets `route_to_stream()`'d into a stream with its own index set is **physically written twice**, once per index set. An unfiltered search spans both indices and returns both hits sharing the same `_id`, which is what surfaces as "duplicated messages" in the ticket. Same underlying gap as before (`route_to_stream()` without `remove_from_stream()`), but the mechanism is a real double index-write, not just a UI/stream-count artifact.

**Confirmed (2026-08-25):** `6a7cb1884814bcaed30a8744` = stream `PROD-Pos-AppServicePlan`, `index_set_id: 6a7cb1874814bcaed30a873d` — matches expectation exactly, this is the ticket's named target stream.

**Confirmed (2026-08-25):** live pipeline rule text for both GITIN-1924 rules (`6a8c60ae4814bcaed31a5560` DEV, `6a8c60bf4814bcaed31a559d` PROD) matches exactly what the prior investigation recorded — `then` block is `route_to_stream(name: "...")` only, no `remove_from_stream()` call on either rule. Root cause fully confirmed: message stays in Default Stream (index set `graylog_4`) and is additionally routed to `PROD-Pos-AppServicePlan` (index set `6a7cb1874814bcaed30a873d`, `pos__1`), producing the physical double-write observed in C1.

Not yet confirmed:
- Whether the `DEV`/`dev__6` side has the same duplicate-indexing symptom (structurally identical rule, not queried this session — ticket only names Default Stream + `PROD-Pos-AppServicePlan`).

## Fix decided (2026-08-25, not yet applied)

User decided: fix **both** rules (DEV and PROD), not just the PROD one GITIN-1933 reports — same root cause, avoids a near-identical follow-up ticket for DEV. Add `remove_from_stream(id: "000000000000000000000001")` (Default Stream) to both GITIN-1924 rules' `then` block via `PUT /system/pipelines/rule/{id}`, preserving each rule's original `title`/`description` from its GITIN-1924 creation payload. Scoped tightly (`Service` + `Environment` exact match per rule) — no other traffic affected.

## Fix applied — DEV rule (2026-08-25)

`PUT /system/pipelines/rule/6a8c60ae4814bcaed31a5560` confirmed: `modified_at` bumped to `2026-08-25T12:45:44.302Z`, `errors: null`, `source` now includes `remove_from_stream(id: "000000000000000000000001")` after `route_to_stream(name: "DEV")`. DEV side of the fix is live.

## Fix applied — PROD rule (2026-08-25)

`PUT /system/pipelines/rule/6a8c60bf4814bcaed31a559d` confirmed: `modified_at` bumped to `2026-08-25T12:46:28.744Z`, `errors: null`, `source` now includes `remove_from_stream(id: "000000000000000000000001")` after `route_to_stream(name: "PROD-Pos-AppServicePlan")`. Both rules fixed as of 2026-08-25 12:46 UTC.

## Fix verified — PROD side (2026-08-25)

Views Search, `Service:"smartfran-pos-wasm"`, absolute range `2026-08-25T12:46:28.744Z`–`2026-08-26T00:00:00Z` (starts exactly at the PROD rule's fix timestamp): 10 sampled messages (of `total_results: 38` in-window at query time), all `Environment:"Production"`, each with a distinct `_id` appearing **once**, `streams: ["6a7cb1884814bcaed30a8744"]` only (no Default Stream `000000000000000000000001`), `index: "pos__1"` only. Duplication resolved for PROD — confirmed against real post-fix traffic, not just rule text.

## Fix verified — DEV side (2026-08-25 13:04 UTC)

Re-ran C7 once real traffic landed. Views Search, `Service:"smartfran-pos-wasm" AND Environment:"Development"`, same absolute range: `total_results: 32`, 10 sampled messages all with distinct `_id`s appearing once, `streams: ["6a7a1b8a34e7b9a985f43cbc"]` only (DEV stream, no Default Stream `000000000000000000000001`), `index: "dev__6"` only. DEV fix confirmed against real post-fix traffic, same pattern as PROD.

**Both sides of the fix are now fully verified end-to-end.**

## Not yet done

1. Decide whether to re-index/delete the stray `pos__1`/`dev__6`-duplicated documents already written before the fix, or leave historical duplicates as-is and only fix going forward — user call, not yet raised.
2. Update GITIN-1933 (and consider a note on GITIN-1924) reflecting the fix; confirm with user whether/how they want this reported back on the Jira ticket.
