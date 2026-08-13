# Investigation — 20260728_nuevo-analisis-costos

**Status:** in progress

## Purpose

Split out from [20260720_ocultar-account-id-sqs-urls](../20260720_ocultar-account-id-sqs-urls/20260720_ocultar-account-id-sqs-urls.md) (was ARQ-010). Extends that ticket's original cost analysis (ARQ-007) with the components added during the ARQ-002/ARQ-009 PoC that ARQ-007 never accounted for: the Lambda TOKEN authorizer, Secrets Manager (vault), and CloudWatch Logs. Also re-prices everything against `us-east-1` — ARQ-007 originally priced API Gateway against `us-east-2`, but the 2026-07-27 correction (in the source ticket) established that real production is `us-east-1`.

## Confirmed facts

- ARQ-007 baseline (source ticket, not re-derived here): real June 2026 volume 147,761,190 SQS FIFO requests/month, $73.49/mo actual SQS cost. Option A (REST API native, no Lambda in data path) priced at ~$517.16/mo using `us-east-2` API Gateway REST rates ($3.50/million). Option A' (HTTP API + light Lambda) ~$180.39/mo.
- The Lambda **authorizer** (ARQ-002) is a different cost driver than the Option A' "Lambda in the data path" — its invocation count depends on **unique tokens per 300s cache window**, not total request volume. A branch making many requests within one 5-minute window only triggers one authorizer invocation; the rest are served from the API Gateway authorizer cache. This means authorizer cost scales with (active branch count) × (cache windows per month), not with total SQS request volume — fundamentally different shape than the data-path costs in ARQ-007.

## Current working theory

Full monthly cost = (SQS/API Gateway data-path cost, per ARQ-007's Option A or A', re-priced for `us-east-1`) + (Lambda authorizer invocation + duration cost, driven by branch count not request volume) + (Secrets Manager: flat per-secret fee + per-API-call fee, the latter negligible since the Lambda caches the secret in memory across warm invocations) + (CloudWatch Logs: execution logging for API Gateway + Lambda, ingestion + storage — should be priced assuming `dataTraceEnabled=false` for a production estimate, unlike the PoC's debug configuration).

- **Pricing confirmed 2026-07-28 (`aws pricing get-products`, `us-east-1`):**
  - API Gateway REST: **$3.50/million requests** (0–333M/mo tier) — identical to the `us-east-2` rate ARQ-007 used, so **ARQ-007's Option A figure ($517.16/mo) is unchanged by the region correction**, no recompute needed there.
  - Lambda requests: **$0.20/million** ($0.0000002/request).
  - Lambda duration: **$0.0000166667/GB-second** (tier 1, 0–6B GB-s/mo — nowhere near that volume here).
  - Secrets Manager: **$0.40/secret/month** flat + **$0.05/10,000 API requests** ($0.000005/request).
  - CloudWatch Logs ingestion (standard/custom logs — API Gateway execution logs and Lambda logs fall under this, **not** the "Vended Logs" SKUs which are CloudFront/WAF-specific via Firehose): **$0.50/GB**.
  - CloudWatch Logs storage: **$0.03/GB-month**.
- **Authorizer invocation bounds, computed.** Cache TTL 300s → 8,640 five-minute windows/month. Active branches: 2,162 (confirmed above).
  - **Floor** (continuously-active branches — cache can't do better than 1 invocation per branch per 300s window regardless of how much traffic occurs within it): 2,162 × 8,640 = **18,679,680 invocations/mo**.
  - **Ceiling** (zero cache benefit — every one of the 147,761,190 monthly requests happens to miss cache): **147,761,190 invocations/mo**.
  - Reality check: 147.76M requests ÷ 2,162 branches ≈ 68,340 req/branch/mo ≈ ~95/hour if spread evenly — well under the 300s cache window, so real-world cost is expected to sit close to the **floor**, not the ceiling, assuming traffic isn't heavily concentrated in bursts with long gaps. Not empirically measured in the PoC — this is a reasonable expectation from the aggregate averages, not a confirmed distribution.
- **Lambda authorizer cost (assumed 128MB memory — the `create-function` default, never overridden; assumed 50ms average warm-execution duration — not measured in the PoC, HMAC verification is inherently fast, so this is a conservative-ish placeholder):**
  - Floor: 18,679,680 × $0.0000002 = $3.74 (requests) + 18,679,680 × 0.00625 GB-s × $0.0000166667 = $1.95 (duration) = **~$5.69/mo**.
  - Ceiling: 147,761,190 × $0.0000002 = $29.55 (requests) + 147,761,190 × 0.00625 GB-s × $0.0000166667 = $15.39 (duration) = **~$44.94/mo**.
- **Secrets Manager cost:** $0.40/mo flat (certain) + per-API-call cost that scales with **cold starts only** (the Lambda caches the secret in memory across warm invocations — see `authorizer/index.js`, `cachedSecret`). Cold-start ratio wasn't measured in the PoC. Upper bound if every invocation were a cold start (unrealistic): same invocation counts × $0.000005 = $93.40 (floor) to $738.81 (ceiling) — not a realistic estimate, just a mathematical ceiling. Realistic expectation under sustained traffic is a small fraction of that (typically well under $5/mo), but this needs production monitoring to confirm, not assumed as fact.
- **CloudWatch Logs — the dominant new cost, and a real design choice, not just a number.** Two distinct logging modes exist, and the PoC used the expensive one for debugging purposes:
  - **Full execution logging** (`loggingLevel: INFO`, what the PoC stage has today) — ~8–10 log lines per request (as seen directly in this session's CloudWatch traces). Estimated ~1KB/request → 147,761,190 × 1KB ≈ **140.9 GB/mo** ingestion → **~$70.45/mo**, plus Lambda's own logs (~0.3KB/invocation × floor/ceiling invocation counts) ≈ $2.68–$21.15/mo → **total ~$73–$92/mo**. Storage at 7-day retention adds a few dollars more, minor.
  - **Access logging only** (`aws_api_gateway_stage.access_log_settings` — one structured JSON line per request: requestId, status, latency, etc., no execution trace) — ~0.4KB/request → 147,761,190 × 0.4KB ≈ **56.4 GB/mo** → **~$28.20/mo**. **Recommended for production** — the PoC's full execution logging was deliberately verbose for debugging a brand-new integration; nothing about steady-state production operation needs that level of detail per request.
  - Both estimates use an **assumed** per-line log size (not measured against a real log group) — flagged as an assumption, refinable by checking actual `storedBytes` on the PoC's log group after a period of real traffic.

- **Option A' combined-Lambda (auth + relay) — 14-month cost impact computed 2026-07-29.** Per-request rate: HTTP API $0.000001 + Lambda requests $0.0000002 + Lambda duration (128MB, 100ms assumed — not measured) $0.0000002083 = **$0.0000014083/request**, plus Secrets Manager's $0.40/mo flat fee. Applied to each of the 14 months' real volumes and combined with each month's actual total AWS bill (same replacement methodology as Option A's grand-total table):
  - Grand total, 14 months: actual bills $18,837.81 → Option A' bills **$20,583.45** — **+$1,745.64 (+9.3%)**, versus Option A's +$5,815.06 (+30.9%) piso / +$6,315.62 (+33.5%) techo over the same period.
  - Average monthly increase to the total account bill (12 full months, jul-2025 to jun-2026): **~$133.58/mo** for Option A', versus **~$444.64/mo** for Option A (piso) — roughly **$311/mo cheaper on average**, consistent with the single-point June 2026 estimate (~$320/mo cheaper) already in the ticket.
  - June 2026 specifically: Option A' = $213.35 total cost (matches the earlier point estimate), full-account-replaced bill = $1,556.64 vs. actual $1,418.29 → **+9.8%**, versus Option A's +32.5% (piso).
  - Same caveat as before: **not built or tested end-to-end** — Lambda duration (100ms) is an assumption, not a measurement. The relative comparison (Option A' costs roughly 3x less to the account than Option A across every month in the 14-month window, consistently) is more trustworthy than either absolute number, since both use the same assumption methodology and the ratio is stable.
- **Palette validated for the 3-series chart (Actual / Option A / Option A'):** blue `#2a78d6`/`#3987e5` (Actual), orange `#eb6834`/`#d95926` (Option A'), aqua `#1baf7a`/`#199e70` (Option A) — all checks pass in both light and dark via `validate_palette.js` (categorical, fixed hue order per the dataviz skill's reference palette). One WARN (aqua's contrast vs. light surface, 2.74:1) is satisfied by direct labels/table view, not dismissed.
- **Option A' actually built and tested 2026-07-29** (COST-006, no longer just a design proposal). Code at `smartpedidos/repos/ocultar-accountid-optB/index.js` — single Lambda combining JWT+branchId verification with the SQS relay (SendMessage/ReceiveMessage via `@aws-sdk/client-sqs`, reusing the same queues and Secrets Manager secret from Option A). Infra: HTTP API `1pslobqodi`, integration `q6vd4ck` (AWS_PROXY, payload format 2.0), routes `POST`/`GET /{branchId}`, stage `optb` (deliberately separate from the REST API's `poc` stage — different API Gateway resource entirely, HTTP API vs REST API), role `poc-arq009-optb-combined-role` (merged `secretsmanager:GetSecretValue` + `sqs:SendMessage`/`ReceiveMessage`).
  - **All 7 test scenarios returned the correct status code** — `200`/`200`/`200`/`403`/`401`/`401`/`200`, same authorization behavior as Option A (matching branch → allow, mismatched branch → 403, no/invalid token → 401).
  - **Real latency measured from the Lambda's own CloudWatch REPORT lines** (not client-observed curl time, which is dominated by this shell's network distance to `us-west-2`, unrelated to the AWS-side cost/performance question): warm executions **40-60ms** for the full auth+SQS path (58.38ms, 47.70ms, 38.74ms across 3 samples), **1.67-17.53ms** for auth-only rejections (403/401, no SQS call). **Cold start: 367.30ms Init Duration + 1,127.22ms Duration ≈ 1.49s total** — first invocation only, includes first-time Secrets Manager fetch + AWS SDK client init for both Secrets Manager and SQS clients.
  - **Cost-model implication:** the 100ms duration assumption used for Option A's cost estimate was conservative — real warm duration is 40-60ms, so the true Lambda duration cost is likely somewhat lower than the ~$213/mo figure already in the ticket (small effect — HTTP API request cost dominates that total, not duration).
  - **Latency-risk implication — the actual number to weigh against the ~$320/mo savings:** cold start adds a real, measured **~1.5s** to whatever request triggers it. Sample size is small (1 cold start observed) — not a load test, just confirms the risk is real and roughly this size, not purely hypothetical anymore.

## Ruled out

- **Recomputing ARQ-007's Option A REST-API figure for `us-east-1`** — ruled out as unnecessary. Confirmed the per-million-request rate is identical to `us-east-2` ($3.50/million), so the region correction doesn't change that number.

## Open questions / next steps

- Lambda authorizer average duration and cold-start ratio are assumptions, not measurements — could be refined by pulling real `Duration`/`Init Duration` values from the authorizer's own CloudWatch REPORT log lines after a period of real traffic, if more precision is wanted before a budget decision.
- CloudWatch Logs per-request size is an assumption — could be refined against the PoC's actual log group `storedBytes` after real traffic.
- Combined total written to the main ticket (see `20260728_nuevo-analisis-costos.md`).
- Brief presentation-ready summary published as an Artifact 2026-07-29 (stat tiles, 14-month trend chart now with all three series — Actual/Option A/Option A' — comparison cards, the Secrets Manager recommendation, and curl test commands with placeholder tokens). URL not persisted here since Artifact links aren't guaranteed stable across sessions in the same way as repo files — regenerate from this ticket's data if needed.
