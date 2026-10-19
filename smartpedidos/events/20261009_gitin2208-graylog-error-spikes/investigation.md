# GITIN-2208 — [SP] ERROR en Graylog: error spikes since 9 AM

- Jira: https://smartit-ar.atlassian.net/browse/GITIN-2208
- Opened (this folder): 2026-10-09.
- Status: analysis in progress (2026-10-09). Today's anomaly is a set of three bursts of `openClosedBranchesGrido` timeouts (08:00, 09:00, 09:30) that did not occur yesterday; the half-hourly PedidosYa `enviarEstadoPedidosYa` bursts from 10:00 are the same as yesterday. Root cause of the Grido timeouts not investigated yet.
- Ask (Jira title, pasted by the user): "error spikes in graylog since 9 AM. Filter 'ERROR'". Day and timezone are not stated; assumed today, 2026-10-09, 09:00 UTC-3 (= 12:00 UTC). Which Graylog stack and stream (SmartPedidos platform-service, concentrador, or something else), and whether the spikes are in volume of ERROR messages or in alerts, is not stated.

## Context

- The SmartPedidos/SmartLoyalty Graylog is the older Docker stack on `sf-monitoreo.smartfran.com` (REST API on port 9000, token `$SML_GRAYLOG_API_KEY`; `docs/graylog_infrastructure.md`), single-node OpenSearch with zero replicas. Known issues from GITIN-1827 / GITIN-1854: the Default Stream index (`graylog_299`) and the SmartPedidos platform index (`sp_platform__50`) were at the 1000-field mapping limit, and each OpenSearch restart makes the whole cluster briefly unavailable. Their current state was not re-checked for this ticket. The SmartCloud Graylog is a different host and token.
- SmartPedidos application logs reach Graylog via stdout to Event Hub (the `db.logerrors` MongoDB collection is dead). The structure of `ERROR` messages (field names) is not known yet; the sample message pull will show it.

## Plan

1. `scripts.sh` (read-only): hourly histogram of `ERROR` from yesterday 00:00 to now; per-minute histogram from today 08:00; counts per `source` before and after 09:00; a sample of 50 messages since 09:00 (all fields; review before sharing).
2. From the sample, pick the field(s) that group the errors (message text, service, branch), then count those per window and look at the first affected time.
3. Cross-check with the other signals if the pattern points there: SQS queue age and ECS task health (`ops-aws`), the Graylog cluster health (`GET _cluster/health`, `docker logs opensearch`), and deploys around 09:00.

## Results

### Run 1 (`data/run1-bad-tz/`, superseded)
- The `histogram` and `terms` endpoints do not exist in this Graylog 5.2.12 (HTTP 404); the pull uses only `search/universal/absolute`. Graylog interpreted plain `YYYY-MM-DD HH:MM:SS.000` times as UTC-3, shifting every window 3 hours late; the script now sends ISO times with `Z` (verified: the newest message of the probe is within 3 seconds of the clock).

### Run 3 (corrected: `data/counts-hour.tsv`, `counts-5min.tsv`, `sample-1/2/3-*.json`)
- Hourly `ERROR` counts (local, UTC-3): night baseline about 950 to 1,300 per hour. 2026-10-08: ramp at 10:00 (3,820), daytime 2,700 to 3,400, evening 20:00-23:00 4,184 / 5,813 / 6,905 / 6,384, bursts at 00:00 (2,859) and 03:00 (5,391). 2026-10-09: 04:00-07:00 about 950 to 1,300, then 08:00 4,215, 09:00 6,782, 10:00 4,255, 11:00 4,053. So today's ramp starts at 08:00, two hours earlier than yesterday's, and the 09:00 hour (6,782) matches yesterday evening's peak while yesterday's 09:00 hour was still at baseline (1,220).
- The 5-minute series since 08:00 shows the shape: a steady background of 75 to 340 per 5 minutes with large bursts at the start of every half hour: 08:00 3,253; 09:00 2,076; 09:30 3,249; 10:00 1,263; 10:30 1,201; 11:00 998; 11:30 719 (decreasing through the morning). The spikes are these periodic bursts, not a rising error rate.
- What the bursts are (samples are the newest 2,000 messages of each window, so they cover only part of each hour: 08:02-08:59, 09:33-09:59 and 11:23-11:57): 500 to 600 `Branch OpenClose Error` messages inside one minute from `concentrador-service`, one per branch id (about 500 to 570 distinct ids per burst). At 08:02 and 09:33 they are `PediGrido openClosedBranchesGrido` with error `timeout of 20000ms exceeded` (ECONNABORTED), 500 and 604 messages. At 11:31 they are `PedidosYa enviarEstadoPedidosYa` (533) with HTTP 400 responses (ERR_BAD_REQUEST). So the burst source differs over the morning and the failure differs (timeouts against the Grido side, HTTP 400 on the PedidosYa side). Which half-hour slots run which platform was not established (only parts of the hour were sampled).
- Steady background in all windows: `No authorization token was found` and `Platform Auth Error: TOKEN_MISSING GET /api/branches/news` (equal counts, about 216 per sampled window), MercadoPago token failures (`No token MercadoPago Cloud`, `[INTEGRATION/ERROR] mercadopago_token_fetch failed`, about 108), and `Branch OpenClose Error ... checkOfflinePOS` for PedidosYa (56 to 172 per window, HTTP 400, 409, 404, 401, 500), MercadoPago and Rappi. Whether these were already present before 08:00 was not separated (the night baseline of about 1,000 per hour is consistent with them but was not sampled).
- The free-text filter `ERROR` also matches `[PERF/INFO] http_response platform=unknown action=unknown` lines (about 500 at the 08:02 burst, level INFO, so INFO lines that contain the word) and IIS lines of another system (source 52.234.224.34, 706 lines in the first sample window); a filter on the JSON `level` field would exclude both.

### Run 4: per-type timeline, today vs yesterday (`data/counts-5min-today-*.tsv`, `counts-5min-yesterday-0700-1200-*.tsv`; 5-minute counts of each exact phrase)

- `openClosedBranchesGrido` (the Grido open/close job; error `timeout of 20000ms exceeded`): today 08:00 1,581, 09:00 990, 09:30 1,543 (4,114 in total); zero in every other 5-minute slot, zero from 10:00 until the pull (about 12:10 local), and zero for yesterday 07:00-12:00. This is what is new today. Each failing branch also produces a `[PERF/INFO] http_response` line that matches the free-text `ERROR`, which is why the `ERROR` totals of those slots (3,253 / 2,076 / 3,249) are about double.
- `enviarEstadoPedidosYa` (PedidosYa, HTTP 400): bursts at 10:00, 10:30, 11:00, 11:30 and 12:00 with nearly identical values today (1,123 / 1,052 / 769 / 577 / 308 so far) and yesterday (1,129 / 1,061 / 801 / 604), 3,829 today and 3,595 yesterday in the compared range. A daily recurring pattern, not new; it explains yesterday's 10:00 ramp.
- `No authorization token was found`: a constant 40 per 5-minute slot on both days (2,051 today in the range so far, 2,400 yesterday over 07:00-12:00); constant background.
- `checkOfflinePOS` returned 0 in every slot, which is not credible against the earlier samples (56 to 172 per sampled window): the quoted phrase does not match the real messages (`checkOfflinePOSpeya`, `...mercadopago`, `...rappi`), so that series is invalid; it needs a wildcard (`checkOfflinePOS*`).
- Reading: the spikes the ticket describes are the Grido timeouts of the first morning hours (new today, ended by 10:00 on their own or after something was done; not known which) layered on the daily PedidosYa bursts that begin at 10:00 and a constant token-error background.

- Related finding from GITIN-2209 (SmartCloud Graylog disk): the Cloud Business API logs about 8.8 errors per second of `MpOAuthClient` `invalid_grant` (HTTP 400) on `GET /api/v1/WalletCredentials/{userId}` since 2026-10-07, and 4 of the 5 failing wallet ids match the `user_id` values in the Concentrador's `mercadopago_token_fetch failed` / `mercadopago_token_invalid_response` errors here. Probable common cause (MercadoPago refresh tokens rejected for those accounts); the Concentrador side logs far fewer lines than the Cloud side, so the retry behaviour of the caller is unverified.

### Restart check (`data/restarts/`, pull of 2026-10-09 12:25-12:27 local)
- Messages per minute of `concentrador-service` (all levels, median of the window in parentheses): 07:50-08:10 (12 per minute): never below 8, one minute at 3,192 (08:02, the Grido burst), no gap. 09:00-09:35 (17): bursts at 09:02 (2,571), 09:32 (1,379) and 09:33 (1,734), and **one minute with zero messages at 09:34**, right after the second burst. Control 10:20-10:55 (42): never below 24, one burst at 10:31 (3,434), no gap.
- All 30 searches for startup or shutdown words (`database_connected`, `listening`, `started`, `starting`, `startup`, `SIGTERM`, `SIGINT`, `shutdown`, `graceful`, `bootstrap`, combined with the service name) returned HTTP 500 from Graylog, including plain words, so the startup-message check was not done; the script did not save the error body (it now does). The per-minute queries on the same service name worked.
- Reading: no sign of a restart at 08:00 (no gap) and the single empty minute at 09:34 is the only gap in the three windows; it is consistent with a brief interruption of the service or of its log delivery after the 09:32-09:33 burst, but nothing confirms a restart. ECS task events were not looked at.

## Open items

- Why the Grido calls timed out at 08:00, 09:00 and 09:30 today and not afterwards: the Grido side's availability that morning, any deploy or restart of `concentrador-service` (a restart can re-trigger the job), and what changed against yesterday are not checked.
- Why `enviarEstadoPedidosYa` returns HTTP 400 for about 570 branches every half hour from 10:00 each day (the response body is not in the log message); whether it is known and accepted.
- Re-run the `checkOfflinePOS` series with a wildcard.
- What the job is and why it errors at ~500 branches in one minute: the `concentrador-service` code behind `openClosedBranchesGrido` / `enviarEstadoPedidosYa` / `checkOfflinePOS` was not read; the Grido and PedidosYa side status was not checked.
- Confirm the day, the timezone, and where the "ERROR" filter was applied (stream or saved search); which of the services behind the ticket (concentrador, platforms) is the one that matters.
- Whether the spike is still ongoing and whether any service impact (orders, queues) was reported.
