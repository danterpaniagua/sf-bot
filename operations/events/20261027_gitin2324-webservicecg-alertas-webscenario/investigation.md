# Investigation — [GITIN-2324](https://smartit-ar.atlassian.net/browse/GITIN-2324): [OPE] WebServiceCG: Alertas y WebScenario

Status: open. Times UTC-3.

## Scope (from the user, 2026-10-27)

- Web scenario for WebServiceCG in PROD, Test02 and PreProd, all on host `sfcg-monitoreo` (10610):
  - PROD: new scenario `[PROD] WebServiceCG`, `https://bot-security.smartfran.com/swagger/ui/index`.
  - Test02: add to the existing scenario `Loyalty Test02` (httptestid 8), `https://azsl-webservicecg-test02.smartfran.com:805/swagger/ui/index`.
  - PreProd: add to the existing scenario `Loyalty PreProd` (httptestid 9), `https://azsl-webservicecg-preprod.smartfran.com:8185/swagger/ui/index`.
- Alerts: a non-200 result is `Information` with `env:DEV` for Test02 and PreProd; `High` with `env:PROD` for PROD.
- The user works through the Zabbix frontend (links `httpconf.php?form=update&hostid=10610&httptestid=8|9`), so changes are a manual walkthrough, not API calls.

## Scripts (in `scripts/`)

| # | Script | Purpose | Run |
|---|---|---|---|
| 1 | `webscenario-apply.sh` | Create 3 scenarios + 3 triggers through the API. Superseded for scenarios 8 and 9 (steps are added in the UI); not applied. | dry run 2026-10-27 11:48 (`data/dryrun-20261027.txt`) |
| 4 | `triggers-create.sh` | Create the 3 triggers (guards on the 6 items, skips existing) | 12:07 created PROD only, then API error (key quoting); 12:08 created Test02 and PreProd (`data/triggers-create-20261027.txt`, `-2.txt`) |
| 5 | `triggers-rollback.sh` | Delete the triggers listed in a create output (prepared, not run) | - |
| 3 | `webscenario-check.sh` | Read-only check after the UI changes: scenarios, web items, triggers, action filters | 2026-10-27 11:54 (`data/check-after-ui-20261027.txt`) |
| 2 | `webscenario-read.sh` | Read-only: live steps of scenarios 8 and 9, triggers on their web items | 2026-10-27 11:51 (`data/read-scenarios-8-9-20261027.txt`) |

## Findings (read of 2026-10-27 11:51)

- `Loyalty Test02` (8) has 7 steps. Step 7 `WebServiceCG` (httpstepid 35) points to `https://azsl-webservicev2-test02.smartfran.com:805/swagger/ui/index`: the host is `azsl-webservicev2-test02`, not `azsl-webservicecg-test02` as in the ticket URL. Same port and path. Also `follow_redirects` 0 and `retrieve_mode` 2 (headers only), unlike most other steps. Whether the `webservicev2` host is a mistake or an alias is not known.
- `Loyalty PreProd` (9) has 8 steps (last is `WebServiceV2-02`); none is for WebServiceCG.
- No trigger hangs on any web item of either scenario (the filtered item list came back empty), so nothing alerts on these scenarios today.
- `web.test.fail` holds the number of the first failing step and later steps do not run, so a trigger `=7` (Test02) or `=9` (PreProd) is hidden when an earlier step fails.

## Check after the UI changes (2026-10-27 11:54)

- None of the intended changes was visible on host 10610: no scenario `[PROD] WebServiceCG`, `Loyalty Test02` still 7 steps with step 7 on `azsl-webservicev2-test02.smartfran.com:805`, `Loyalty PreProd` still 8 steps, no trigger with WebServiceCG in its name. The check ran 3 minutes after the previous read; whether the user had saved the changes by then is not known.
- Step 7 of Test02 answers: `web.test.rspcode[Loyalty Test02,WebServiceCG]` = 200 at 11:53:59 (response time 0.028 s, headers only). So the `webservicev2` host at port 805 does serve that path; it is not shown whether it is the same service as `azsl-webservicecg-test02`.
- `web.test.fail` = 0 for Test02 and PreProd; last `web.test.error` for both is a 15 s timeout at 06:01:14.
- Routing (live, read now): action 12 `Notify OPERACIONES env PROD (Chat + Telegram)` is enabled (`status` 0) with the single condition `env = PROD`. No other trigger action has a condition on the `env` tag, so a trigger tagged `env:DEV` matches no action. Action 3 is `status` 1 (disabled), consistent with 0 = enabled.

- Second check 11:56:03: same state as 11:54. Search over all hosts at 11:57:33 (`data/search-all-hosts-20261027-2.txt`, raw response `error` null, `count` 0): no scenario with WebServiceCG in its name on any host, so `[PROD] WebServiceCG` does not exist anywhere at that time. The search is by scenario name, so it says nothing about the steps added inside `Loyalty Test02` / `Loyalty PreProd`; those were read at 11:56:03 and were unchanged.

- Check 12:05:32 (`data/check-after-ui-20261027-3.txt`; the same file name as the 11:58 run, so that earlier output was overwritten): `[PROD] WebServiceCG` exists (httptestid 21, 1 step); `Loyalty PreProd` has 9 steps, step 9 `WebServiceCG` (httpstepid 44) on `azsl-webservicecg-preprod.smartfran.com:8185`; `Loyalty Test02` still has step 7 on the `azsl-webservicev2-test02` host. No trigger yet.
- The PROD step is named lowercase `swagger` (item keys `web.test.rspcode["[PROD] WebServiceCG",swagger]`); keys are case sensitive, so the PROD trigger must say `swagger`, not `Swagger`. The check script's step filter (`WebServiceCG|Swagger`) is case sensitive and printed no PROD step for that reason.
- New items of PROD and PreProd have last value 0 at clock 1969-12-31 (never collected yet at 12:05); not a failure, consistent with the proxy sync lag. Test02 collects (rspcode 200 at 12:05:01).

## Triggers created (2026-10-27 12:07-12:08)

- Created through `triggers-create.sh`: 27069 PROD (High, `env:PROD`), 27070 Test02 (Information, `env:DEV`), 27071 PreProd (Information, `env:DEV`). Read-back at 12:08:57 shows the expressions, `opdata` `HTTP code: {ITEM.LASTVALUE1}`, tags and `status` 0, `value` 0, `state` 0 for the three.
- The first run failed on Test02 with `Incorrect item key "web.test.rspcode[\"Loyalty Test02\",WebServiceCG]"`: Zabbix matches the key text, and that item is stored unquoted (`web.test.rspcode[Loyalty Test02,WebServiceCG]`) while the PROD one is stored quoted. The expressions now use each item's stored key. That first run had already created the PROD trigger (27069).
- Not tested: that any of the three fires on a real non-200 or timeout. `value` 0 only shows the state at 12:08:57; the PROD and PreProd items had not collected a value at 12:05.

## Check 12:15:14 (`data/check-after-ui-20261027-3.txt`, same file name reused again: the 12:05 output was overwritten)

- Test02 collects (rspcode 200 at 12:15:03). `web.test.fail[Loyalty PreProd]` updates (12:14:29) but the step 9 items (`rspcode`, `time`, `bps`) and all PROD items still have last clock 1969-12-31: never collected, about 15 minutes after the PreProd step was saved. The PROD scenario existed by 12:05.
- Trigger 27071 (PreProd) shows `state` 1 (unknown: it cannot be evaluated without data in its rspcode item); 27070 and 27069 show `state` 0. Not understood why the PROD one is 0 with an item that has no data; not investigated.
- Hypothesis, not checked: the proxy (`sfcg-monitoreo`, proxyid 10609) has not yet received the new configuration, so it still runs `Loyalty PreProd` with 8 steps and does not run `[PROD] WebServiceCG`. The proxy's config sync interval was not read. Until the items collect, the PROD trigger monitors nothing.

## Check 12:20:15 (`data/check-after-ui-20261027-3.txt`, overwritten again)

- All three scenarios collect: PROD `rspcode` 200 / `fail` 0 / response 0.026 s (12:19:54); PreProd step 9 `rspcode` 200 / 0.038 s (12:19:34); Test02 as before. Triggers 27069, 27070, 27071 all `value` 0, `state` 0.
- The items had no data at 12:15 and had data at 12:19-12:20. The cause (proxy picking up the new configuration) was a hypothesis and was not checked.
- Still not tested: that a trigger fires on a real failure. Test02 step 7 still uses the `azsl-webservicev2-test02` host (decision pending).

## Proposed triggers (superseded by the section above where the keys differ) (not created; user decision pending)

- User decision 2026-10-27: the alert is "response code not 200 for the endpoint", so each trigger reads the step's HTTP code item and also the scenario fail item (a timeout or connection error stores no new response code, so the code item alone would keep its last value 200).
- PROD: `min(/sfcg-monitoreo/web.test.rspcode["[PROD] WebServiceCG",swagger],#2)<>200 or min(/sfcg-monitoreo/web.test.fail["[PROD] WebServiceCG"],#2)<>0`, High, tag `env:PROD` (action 12 matches `env = PROD`, read live 2026-10-27).
- Test02: `min(/sfcg-monitoreo/web.test.rspcode["Loyalty Test02",WebServiceCG],#2)<>200 or min(/sfcg-monitoreo/web.test.fail["Loyalty Test02"],#2)=7`, Information, tag `env:DEV`.
- PreProd: `min(/sfcg-monitoreo/web.test.rspcode["Loyalty PreProd",WebServiceCG],#2)<>200 or min(/sfcg-monitoreo/web.test.fail["Loyalty PreProd"],#2)=9`, Information, tag `env:DEV`.
- Operational data on all three: `HTTP code: {ITEM.LASTVALUE1}`.
- All carry `service_group:LOYALTY` and `SVC_FRIENDLYNAME` as the MOBI triggers do (assumption, not confirmed for this service).
- Scenario SSL verification stays off, as in the other 16 scenarios.

## Open

- Whether the UI changes (new PROD scenario, Test02 step fix, PreProd step 9, three triggers) were made: not confirmed.
- Correct Test02 host for step 7.
