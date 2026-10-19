# Investigation: SSL MobileAppService High alert open with 17 days remaining

**Status:** closed by the user's decision on 2026-10-18 ("close, leave as is") — no fix applied; the High tier stays open until the certificate is renewed (recovery needs 30). Mechanism measured (script prints 0 on a failed handshake); why the handshake to the MobileAppService endpoint failed around 10:00-12:00 (UTC-3) on 2026-10-15 was not determined. `ops.md` written from this state.
Jira: https://smartit-ar.atlassian.net/browse/GITIN-2249

## Trigger

The user pasted a Zabbix row and said "this alert is wrong":

`2026-10-15 10:04:52  PROBLEM  Zabbix server  SSL MobileAppService a menos de 7 dias de vencer  Triggered: 0 | Actual: 17`

## Measured (data/item-53392-lookup-2026-10-18.txt, read from the Zabbix API on 2026-10-18)

Item `53392` `get_ssl_enddate_mobileappservice`, host Zabbix server (`10084`), key `log[/var/log/zabbix/ssl_mobileappservice.log,,utf-8,,,,,,]`, `delay 15m`, **`value_type 3` (unsigned integer)**, history 90 d, status enabled, state normal. Last value 17 at 2026-10-17 21:04:52 (UTC-3).

History is stored under **history type 3**; types 0, 1, 2 and 4 are empty. (My first pull used type 2 and returned nothing — see `data/item-53392-history-2026-10-14_15.json`, 36 bytes. The empty result was a wrong history type, not a silent item.)

Values, most recent first (UTC-3):

| Time | Days |
|---|---|
| 2026-10-17 21:04:52 | 17 |
| 2026-10-16 21:04:52 | 18 |
| 2026-10-15 21:04:52 | 19 |
| **2026-10-15 13:04:52** | **20** |
| **2026-10-15 10:04:52** | **0** |
| 2026-10-14 21:04:52 | 20 |
| 2026-10-13 21:04:52 | 21 |
| 2026-10-04 … 2026-10-12 21:04:52 | 30 … 22 (one per day, -1 per day) |
| 2026-09-30 21:04:52 | 34 |

- The series falls by one day per day from 34 (09-30) to 17 (10-17) with no renewal in that period: the certificate has not been renewed yet and has 17 days left (as of the last value).
- Normal samples are one per day at 21:04:52. Two extra samples exist on 2026-10-15, at 10:04:52 (**0**) and 13:04:52 (20). The 0 is the alert's `Triggered: 0` and is isolated: the value was 20 the evening before and 20 three hours later.
- All timestamps end in :04:52, so they are poll instants of the 15-minute item; an extra value appears only when the log file received a new line between polls. That means extra lines were written to `ssl_mobileappservice.log` around 10:00 and 13:00 on 2026-10-15 (inference from the polling pattern, not read from the log).

## Reading (inference, not confirmed)

- "<7 días" is the High tier, `triggerid 26284`: problem when value `<{$SSL_CERT_HIGH:LE}` (7), recovery when `>={$SSL_CERT_OK:LE}` (30). `:LE` after the 2026-10-02 review: Warning 15, Average 10, High 7, OK 30 (`operations/events/20261002_zabbix_monthly_alert_review/`, `data/ssl-auto-AFTER.json` shows the expressions with macros unresolved; live macro values not re-read here).
- The single 0 satisfied `<7` (and also `<10` and `<15`), so the trigger opened on a spurious reading. With real values of 17-20 the recovery condition (`>=30`) is not met, so it stays open until the certificate renews. Same stuck-recovery family as `loyalty/events/20260911_ssl_mobileappservice_facturasend_context_bug` (GITIN-2028), but there the cause was a wrong macro context; here the macros are `:LE`.
## Measured: trigger, event and macro state (data/mobi-ssl-triggers-events-2026-10-18.txt, read 2026-10-18)

- Macros confirmed live: `{$SSL_CERT_WARN:LE}`=15, `{$SSL_CERT_AVERAGE:LE}`=10, `{$SSL_CERT_HIGH:LE}`=7, `{$SSL_CERT_OK:LE}`=30 (base 45/30/15, OK 60).
- Only the High tier is open: `26284` value 1, `lastchange` 2026-10-15 10:04:52, one event since 2026-10-14 (`eventid 716831`, no recovery event). Warning `25914` is value 0 with `lastchange` 2026-09-11 10:19:52 (not touched on 10-15) and Average `26282` is value 0 with `lastchange` 0 (never fired). The 10-02 review made Average depend on High and Warning on Average + High; a dependent trigger does not open while its master is in PROBLEM, which would explain why only High shows (reading of the dependency design, not tested).
- Confirmed: the alert's threshold (7) is the real High threshold, and the stuck trigger has no recovery event yet because the value has stayed below 30.

## Measured: the log file on the Zabbix server (data/server-ssl-mobileappservice-log-cron-2026-10-18.txt, host `sf-monitoreo`, read 2026-10-18)

- `/var/log/zabbix/ssl_mobileappservice.log` is 3 bytes, owner `zabbix:root`, modified `Oct 18 15:00` (server clock; timezone not shown), and its whole content is `17`. So the file is rewritten with the current value, not appended: it keeps no history, and the line that carried the 0 on 2026-10-15 is gone from it.
- The search for the feeding cron/timer/script returned nothing, but the command ran as the `ubuntu` user and hid permission errors (`2>/dev/null`) on `/etc/cron*`, `/var/spool/cron` and the script directories, so the empty result does not show that no cron or script exists. Not concluded.

## Measured: where the log comes from (data/server-ssl-feeder-search-2026-10-18.txt, read 2026-10-18; server clock is UTC, item history above is UTC-3)

- The log was created (`Birth`) 2026-09-11 13:12:30 UTC; last `Modify` 2026-10-18 15:00:01.75 UTC, `Change` 15:00:01.78. A write at second :01 of an exact hour points to a scheduled job; the 15:03 `Access` is the agent reading it.
- No crontab for `zabbix` or `root`, nothing matching `ssl` in `/etc/cron.d`, `/etc/cron.hourly`, `/etc/cron.daily`, `/etc/crontab`, no systemd timer with `ssl|cert`. The only files mentioning `ssl_mobileappservice` or `get_ssl_enddate` under `/etc /opt /usr/local /home` are `/home/ubuntu/.bash_history` and `/home/ubuntu/.viminfo`. The feeding script/job itself has not been found (it may use a name or a user not covered: the `ubuntu` crontab and other crontab files were not listed).

## Measured: the feeding job (data/server-ssl-feeder-search2-2026-10-18.txt, read 2026-10-18)

- It is in the `ubuntu` user's crontab (`-rw------- ubuntu crontab 3160 Apr 24 12:37`, file listing of `/var/spool/cron/crontabs`): `0 * * * * /bin/bash /home/ubuntu/scritps/sslenddate/get_enddate.sh mobileservice.clubgrido.com.ar 8043 | sudo tee /var/log/zabbix/ssl_mobileappservice.log; sudo chown zabbix /var/log/zabbix/ssl_mobileappservice.log` — hourly at minute 0 (server time UTC), against port 8043. The same pattern feeds the other SSL logs (ClubSite AR/PY, smartfran, website `:4430`, fs-api, webservicev2 `:8080`, bot-security). The directory is spelled `scritps`.
- `tee` overwrites the log with whatever the script prints each hour, so whatever it prints on a failed connection becomes the next value. The script `get_enddate.sh` has not been read yet, so what it prints (0, empty, an error) when it cannot reach the endpoint is unknown.
- The cron timing matches the item history: runs at 13:00, 14:00 and 15:00 UTC would all write the same value (0), which Zabbix reads once at the first change (10:04:52 UTC-3 = 13:04:52 UTC), and the 16:00 UTC run wrote 20 (read at 13:04:52 UTC-3). Whether the three runs really printed 0 is still inferred from the item history, not read from a log.

## Measured: what the script prints when it cannot read a certificate (data/server-get-enddate-script-2026-10-18.txt; local reproduction in data/test-get_enddate-failure-local-2026-10-18.txt)

- `get_enddate.sh` (server, `-rwxrwxrwx ubuntu`, last modified 2024-08-03; 8 lines): `openssl s_client … 2>/dev/null | openssl x509 -noout -enddate | sed …` inside `date -d "$(…)" +%s`, then prints `enddate/86400 - today/86400` in days. It has no exit-code check, no `set -e`, and hides openssl errors (`2>/dev/null`).
- When the connection yields no certificate, the command substitution is empty and `date -d ""` returns today 00:00, so the script prints **0**. Reproduced locally with GNU date 9.4 (`scripts/test-get_enddate-failure.sh`): empty input → `0`; a certificate 17 days out → `17`. The server's `date` version was not checked (OpenSSL there is 3.0.2). `tee` then writes that 0 into the log and Zabbix reads it as a real reading of "0 days".
- So a failed TLS handshake to `mobileservice.clubgrido.com.ar:8043` (or a DNS/network failure on the Zabbix server) at the 13:00, 14:00 and 15:00 UTC runs on 2026-10-15 would produce exactly the 0 seen. That the handshake did fail in that window is **not yet confirmed**; it is the explanation that fits the script, the cron timing and the item history.

## Measured: the other SSL items on 2026-10-15 (data/ssl-items-history-2026-10-15.txt, history type 3, UTC-3)

- Eight items `get_ssl_enddate_*` on `Zabbix server`. Only MobileAppService (`53392`) shows the extra readings (10:04:52 = 0, 13:04:52 = 20, 21:04:52 = 19). The other seven each have a single reading that day (about 21:07-21:14) and no 0: clubsite_ar 75, clubsite_py 53, fs-api 43, smartfran 68, webservicecg 163, webservicev2 163, website 66.
- All eight are fed by hourly `0 * * * *` cron lines in the same minute, and Zabbix stores a log value only when the file changes, so a 0 from any of them would have appeared as an extra reading. None did. So the Zabbix server could read the other seven endpoints in that window; the failure is specific to `mobileservice.clubgrido.com.ar:8043` (or the path to it from the monitoring server). Why that handshake failed around 10:00-12:00 (UTC-3) is not known.

## Reading of the timing (inference)

The extra item values on 2026-10-15 were at 10:04:52 and 13:04:52 (UTC-3) = 13:04:52 and 16:04:52 UTC, each just after an exact UTC hour at which the job would have rewritten the file. If the job runs hourly at :00:01 UTC (suggested by the 15:00:01 write, not confirmed), the file held 0 from the 13:00 UTC run until a later run wrote 20 (the 16:00 UTC run, seen at 16:04:52), i.e. roughly three hourly runs gave 0, and the ordinary daily change shows at 00:04:52 UTC. What made the check return 0 for those hours is unknown; whether the endpoint or its path was unreachable around 10:00-13:00 (UTC-3) on 10-15 has not been checked.

## Open questions

1. What wrote the 0 to the log at about 10:04 on 2026-10-15: the check script failing and writing 0, a manual run, or something else? Needs `ssl_mobileappservice.log` and the script/cron that feeds it. (The 13:04 extra line with 20 may be a re-run.)
2. Why the certificate is still at 17 days: the runbook says win-acme renews in the last ~30 days of a 90-day certificate (not checked against win-acme settings); the series shows no renewal yet. The 10-02 review noted no real renewal cycle for MobileAppService had been seen.
3. Current state of triggers 25914, 26282 and 26284 and the events since 2026-10-14.

## Next

Read-only `trigger.get` / `event.get` for the three MobileAppService SSL triggers (`scripts/scripts.sh`, step 3). Then, on the Zabbix server, the log file and its feeding script/cron.
