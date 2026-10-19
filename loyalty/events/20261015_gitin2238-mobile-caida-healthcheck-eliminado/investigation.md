# Investigation — 20261015_gitin2238-mobile-caida-healthcheck-eliminado

**Jira ticket:** [GITIN-2238](https://smartit-ar.atlassian.net/browse/GITIN-2238) "[SML] Mobile: Alerta Healthcheck" (user, 2026-10-15: its scope is this outage incident). Sub-task [GITIN-2239](https://smartit-ar.atlassian.net/browse/GITIN-2239) "[OPE] Creacion de trigger para healthchecks" covers the triggers (`loyalty/events/20261015_gitin2239-mobile-healthcheck-alerta-zabbix/`).

**Status:** service restored; cause confirmed by the operator and the outage measured at the load balancer (C1); prevention, the earlier episode (06:14-06:55) and the reply to PediGrido pending

## Report
- Grido (customer) reported by WhatsApp on 2026-10-15 12:14 local that calls to `mobileservice.clubgrido.com.ar:8043` (MobileAppService) failed from 09:18 local (12:18 UTC) with 0 successful calls from 09:19, still down at 10:58 local (13:58 UTC); an earlier episode 06:14-06:55 local (09:14-09:55 UTC) recovered by itself. Their breakdown: open circuit 94%, timeouts 6%, connection resets <2%, 19 OK in about 1 h 40 min. Raw text in `data/grido-report-20261015.txt`.
- User (2026-10-15): DevOps deleted the healthcheck file; no alert was configured for this.

## What is known from earlier events (not re-verified today)
- GITIN-1228: `SFCG-MOBI-LB` health probe `healthcheck.ashx` is HTTP, port 8080, path `/healthcheck.ashx`, interval 5 s, `probeThreshold` 1, `numberOfProbes` 1 (`loyalty/events/20260916_gitin1228_lb_healthcheck/data/sfcg-mobi-lb_probe_healthcheck_current.json`; subscription `0190fa7d-...`, resource group `DefaultGroup01`). Before that the probe was TCP 8043.
- A copy of the handler is in `loyalty/events/20260916_gitin1228_lb_healthcheck/healthcheck.ashx`.

## Working hypothesis (not confirmed)
- If the file served on port 8080 was deleted on both `SFCG-MOBI-01` and `SFCG-MOBI-02`, every probe fails (a missing handler answers an error), both backends are marked unhealthy, and the load balancer stops sending traffic to them; to a client this looks like timeouts and connection resets. This fits the pattern Grido describes (hard unavailability, resets, 19 OK) but has not been checked: the LB backend availability metric around 12:18 UTC, the probe result and whether the file exists on each VM are the checks.
- The shorter episode 06:14-06:55 local is not explained by this hypothesis; nothing was found about it yet.

## Checks (read-only, to run)
- C1: LB backend availability (`DipAvailability`) per backend and `VipAvailability` for 2026-10-15 09:00-17:00 UTC, 1-minute granularity: does it fall to 0 near 12:18 UTC and for both backends?
- C2: the current probe definition (path, port, threshold) and the LB rule that uses it.
- C3: on each VM, whether `healthcheck.ashx` exists and what `http://<private-ip>:8080/healthcheck.ashx` answers (run by whoever has access).

## Restoration (user, 2026-10-15, message received about 15:39 UTC)
- The user restored the healthcheck files and the service went back up. The restoration time, which VMs, the path used and the check that showed recovery were not provided. The LB availability metric (C1) and the probe definition (C2) were not run yet (no output files in `data/`), so the link between the deleted file and the outage rests on the user's statement and the pattern of the report, not on LB data. Grido has not confirmed recovery on their side either.

## Follow-up 2026-10-15 (afternoon)
- The trigger work for this incident is tracked in GITIN-2239 (`loyalty/events/20261015_gitin2239-mobile-healthcheck-alerta-zabbix/`): existing Zabbix web scenario `[PROD] MobileApp` (host `Zabbix Proxy`, every 30 s) already had a `healthcheck` step against the public URL `https://mobileservice.clubgrido.com.ar:8043/healthcheck.ashx`, but no trigger on it (WebServiceV2 had two, without tags). The C21-C26 work of GITIN-2222 shows that a trigger can exist and still not notify (macro, permissions); that has to be checked for the healthcheck triggers too.
- Still not run: the LB availability metric (C1) and the probe definition (C2) of this event, so the outage timeline from our side is not measured.

## Timeline and context stated by the user (2026-10-15; names removed; times -03:00)
- Customers informed by WhatsApp (this is how the outage was noticed; no alert existed).
- Operations deployed to production and announced the deployment finished at 09:32 (Operations validating the deployment). QA validated the process and reported "everything is ok in prod" in the QA Google Chat at 10:18.
- Grido's logs show the failure from 09:18 and still failing at 10:58; the user states the Mobile outage lasted about 3 hours. The user states that Operations did not preserve the healthcheck file during the deployment (the file was deleted). The sequence (outage starting at 09:18, before the deployment announcement at 09:32) fits a deletion during the deployment window, but the deletion time was not measured.
- The QA validation of 10:18 did not catch the failure; whether it covered MobileAppService was not stated.
- The user states that creating the healthcheck alert was a pending Operations task that was not done in time (not cross-checked against a ticket; the TCP-only probe was flagged as technical debt in GITIN-1909 and the HTTP probe change is GITIN-1228, per `loyalty/events/20260916_gitin1228_lb_healthcheck/investigation.md`).
- Improvement opportunity named by the user: new alerts for healthchecks (GITIN-2239, created in Zabbix, delivery not yet seen).

## Cause confirmed by the operator (user, 2026-10-15)
- The user states the cause is confirmed: the healthcheck files had been deleted during the deployment, and restoring them brought the service back up (before/after observation by the person who did the restoration; no load-balancer data was read). The mechanism (probe failing, backends removed from rotation) remains an explanation consistent with Grido's symptoms, not measured. The hypothesis section above is kept for that reason.

## Correction (user, 2026-10-15)
- The healthcheck file was part of the deployment process; it was deleted by mistake during the deployment (not "left out of the process"). Earlier wording in the email draft ("not included in the deployment process") was wrong and was corrected. The separate observation that the handler is not in the SmartLoyalty source repository (GITIN-1228 kept it in an event folder and on the VMs) was not discussed again and is not part of this statement.

## Scope of the affected customer (user, 2026-10-15)
- The problem was with PediGrido, not with all of Grido. Grido's report names "Account API / SmartFran" calls to `mobileservice.clubgrido.com.ar:8043`; the user attributes them to PediGrido. Which Grido components use that endpoint, and whether other Grido apps (or the SmartLoyalty mobile app) were affected, was not checked; the email says only what the user stated.

## Earlier episode (06:14-06:55 -03:00): maintenance window (user, 2026-10-15)
- The user states that the hours 06:14-06:55 -03:00 (09:14-09:55 UTC) are used for housekeeping and maintenance, so PediGrido's earlier episode coincides with that window. Not measured: the load balancer read (C1) started at 11:30 UTC and does not cover it; which maintenance task ran and whether it explains the drop was not checked. The customer email says only that the episode "coincides with a window in which we do maintenance tasks".

## Emails sent (user, 2026-10-15): "mail sent"
- The user states the mail was sent. Which draft(s) it refers to (`email_cliente.md` for the customer, `email_internos.md` for the internal stakeholders, or both) was not specified. Not visible from the chat or the folder whether the final text was sent unchanged.

## Open
- Time the file was deleted and who/what deleted it (deployment or manual); time and way of restoration.
- Duration of the outage as seen from our side (needs C1) and whether it matches Grido's 12:18 UTC start.
- Whether Grido's other callers or the app itself (mobile clients) were affected during the same window.

## C1 result: outage measured at the load balancer (`data/c1-run-log-20261015T185020Z.txt`, `SFCG-MOBI-LB`, window 11:30-16:30 UTC, 1-minute data; times below UTC with -03:00 in brackets)
- Health-probe availability per backend: `192.168.50.111` (MOBI-01) at 0 % from **12:19 to 15:25** (187 minutes); `192.168.50.112` (MOBI-02) at 0 % from **12:18 to 15:25** (188 minutes). Frontend availability (`VipAvailability`) at 0 % from 12:20 to 15:31 (192 minutes). In -03:00: backends 09:18 to 12:25, frontend 09:20 to 12:31, about 3 h 7 min at the backends. The start matches PediGrido's 09:18 (-03:00) and the end matches the restoration (the probe runs every 5 s, so the backends return within seconds of the file being back; the exact time of the restoration was not provided).
- Both servers went to 0 % at the same time and stayed there: consistent with both having lost the probed file; the metric shows availability, not the reason a probe fails. The operator's observation (restoring the files brought the service back) is the confirmation of the cause.
- Short drops before the outage: MOBI-02 at 11:47-11:48, 11:50-11:53 (4 minutes), 11:58 and 12:08 UTC (08:47-09:08 -03:00), MOBI-01 at 11:57 (61 %): these precede the outage by about 10-30 minutes; their cause was not investigated. After the outage there are single-minute dips of 60-67 % on MOBI-02 (15:28, 15:38, 15:49) and MOBI-01 (15:30).
- Probes defined on the load balancer now: `SFCG-MOBI-LB-probe02` (TCP 8043, 5 s, threshold 1), `SFCG-MOBI-LB-probe01` (HTTP 8043 `/api/MobileAppService/CheckServiceStatus`, 5 s, threshold 1) and `healthcheck.ashx` (HTTP 8080 `/healthcheck.ashx`, 5 s, threshold 2). Which probe the load-balancing rule uses was not read in this run (the file `healthcheck.ashx` is the probe that depends on the deleted file).
- The window starts at 11:30 UTC, so PediGrido's earlier episode (06:14-06:55 -03:00 = 09:14-09:55 UTC) was not measured.
- The email draft was updated with the measured times (09:18-12:25, frontend back at 12:31) and the pending item about LB metrics was replaced by the review of the earlier episode.

## Update 2026-10-15 19:30 UTC
- Customer email `email_cliente.md` was drafted and then shortened at the user's request (cause stated only as a communication problem with the load balancer; window 09:18-12:25 -03:00; alerts created and updated; the earlier episode "coincides with a maintenance window"). The user reports the mail was sent; which text and recipients was not stated.
- The alerts for this incident (GITIN-2239) exist but their notification delivery is not confirmed (see GITIN-2239 and GITIN-2222 investigations): this matters for the email's statement that alerts were created and updated; it says nothing about them notifying.
- The earlier episode of PediGrido (06:14-06:55 -03:00) has its own folder `loyalty/events/20261015_gitin2241-mobile-episodio-previo-0614-0655/` (nothing measured yet; parked).

## Folder renamed (2026-10-16 11:34 UTC)
- At the user's request the folder was renamed to include the ticket (`20261015_gitin2238-mobile-caida-healthcheck-eliminado`), with `scripts/rename_event_folders.sh` (root `scripts/`; apply log `scripts/rename-events-apply-log-20261016T113438Z.txt`, manifest `scripts/rename-events-manifest-20261016T113438Z.tsv`). Text files outside `data/` that named the old folder were rewritten; `data/` logs were not (they keep the old path in their printed rollback commands), and a symbolic link with the old name points to the new folder so those commands still resolve. Check at the end of the apply: 0 files outside `data/` still name the old folder.
