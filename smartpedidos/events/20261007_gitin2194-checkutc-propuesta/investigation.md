# GITIN-2194 — [SP] Propuesta checkUTC

- Jira: https://smartit-ar.atlassian.net/browse/GITIN-2194
- Opened: 2026-10-07
- Status: in progress (proposal drafted, not converged)

## What is known

- Source read: Concentrador clone (`smartpedidos/repo/dev-src-smartPedidos-concentradorService`), branch `ope`, working tree (HEAD `594c0869`, plus uncommitted README edits unrelated to this). Not diffed against `develop`/`main`.
- The alert "Concentrador: informacion cambios UTC en entorno production" comes from `api/src/utils/checkUTC.js`. It compares the `tzo` (UTC offset, string) stored per country in MongoDB (`countries`) against `gmtOffset/3600` returned by the external API `timezonedb.com` (`list-time-zone`) for five zones (Argentina/Buenos_Aires, Lima, Montevideo, Asuncion, Santiago), with a 2 s delay between calls, and sends an email through SendGrid (`settings.mail`) when anything differs.
- Triggers: cron `0 7 * * *` registered in `controllers/branch.js` (`syncCheckUTC`, production only) and a call at startup in `index.js` (production only). Whether several production tasks each register the cron (duplicate emails) was not checked.
- `tzo` is also what the branch open/close crons use to convert local to UTC (`toUTC`/`toUTCv2` in `branch.js`), so the check guards a configuration value, not the system clock.
- The `timezonedb` API key is hardcoded in `checkUTC.js` (belongs to the hardcoded-credentials sweep, GITIN-2169; value not reproduced anywhere).
- Code paths that can email without a real offset difference: any failed API call adds an "ERROR" row and sends the email; a response without `zones[0]` makes the offset `NaN`, which never equals the stored value; a response without `zones` throws and triggers the second "Error al actualizar zonas horarias" email. These are candidates read from code, not confirmed as the cause of the observed emails.
- One real email was provided: only Chile differed, stored `-3` vs `timezonedb` `-4`. The send date of that email is unknown. IANA data (Node `Intl`, `longOffset`) on 2026-10-07 gives Chile `-3`, Argentina `-3`, Uruguay `-3`, Paraguay `-3`, Peru `-5` (`data/tzdata-offsets-check.txt`, local Node 18.19.1, tzdata 2023c — older than Paraguay's 2024 change, so that run can't speak for Paraguay in the winter months). Whether the Chile mismatch was an API error or a legitimate winter-time change depends on the unknown date.
- The production base image `node:20.20-alpine` (Node 20.20.2) ships tzdata 2025c (`data/tzdata-container-check.txt`), which includes Paraguay's permanent UTC-3 (2024b+). Tz data only changes when the image is rebuilt on a newer Node patch; changes published after 2025c would not appear until then.
- NTP (`pool.ntp.org`) was considered and ruled out for this check: an NTP reply carries UTC time only, not a country's UTC offset or DST rules, so it can't replace the offset comparison. A container shares the host kernel clock and cannot run its own NTP; this check isn't about clock drift.
- Graylog evidence (SmartPedidos/SmartLoyalty stack, API `http://sf-monitoreo.smartfran.com:9000`, reachable directly from the workstation with a token; HTTPS 443 times out; `/api/search/universal/relative` requires the `fields` parameter and returns CSV whose `message` column is the raw JSON log line; `data/graylog-*.csv|json`, summaries in `data/graylog-checkutc-summary.txt` and `data/graylog-timezonedb-summary.txt`). Window 2026-09-08 → 2026-10-07 (30 days):
  - 43 `Ejecución de checkUTC` lines from `concentrador-service` (level ERROR is just how `Log.saveError` tags them): 24 `Scheduled` (07:00 UTC cron) and 19 startup runs without the `ejecution` tag. Startup runs cluster around 06:31–06:36 UTC about every second day, plus some around 12:xx UTC, which suggests frequent service restarts (cause not investigated).
  - The 07:00 `Scheduled` run is absent on 6 days (2026-09-13, 09-25, 09-27, 09-29, 10-03, 10-05), days that only have a startup run. A possible explanation is that the cron is registered only after some code path runs (`syncCheckUTC` is called from `branch.js` line ~2928), not verified.
  - No day has two `Scheduled` runs, but Graylog shows a single `source` (`aws-kinesis-raw-logs`), so it cannot tell tasks apart; duplicate crons across tasks are neither confirmed nor ruled out.
  - A search for `timezonedb` returns exactly the same 43 execution lines: no `Error al consultar API timezonedb ...` line was logged in the 30-day window. Inference: API call failures (the "ERROR" rows) are not the source of the emails in this window; the `Log.saveError` call that writes them uses the same path as the execution line that does arrive, but that was not verified separately.
  - Consequence: the emails seen are more likely mismatches reported by `timezonedb` itself (e.g. the Chile `-4` vs stored `-3` email) than API failures. Whether `timezonedb` returned a wrong/stale value or the stored `tzo` was stale at that time still depends on the unknown send date of that email.

## Proposal

Replace the `timezonedb` calls with a local computation of the expected offset from the tz database bundled in Node (`Intl.DateTimeFormat` with `timeZoneName: 'longOffset'`, Node 18+), keeping the same cron, comparison against `tzo` and email. Removes the API key from source, the external call, the 2 s delays and API-failure emails. Example code was drafted in conversation; no file in the Concentrador repo has been changed. Email to Operations drafted in `email_ops.md`.

## Open items

- Date of the Chile `-3`/`-4` email, to classify it as API returning a wrong/stale value or a legitimate change (Graylog shows no API failures in the 30-day window).
- Whether several production tasks each run the cron (Graylog can't distinguish tasks), why the 07:00 run is missing on some days, and why the service restarts so often.
- Whether to drop the startup run in `index.js`.
- Implementation and review of the change on the Concentrador `ope` branch (not started).
