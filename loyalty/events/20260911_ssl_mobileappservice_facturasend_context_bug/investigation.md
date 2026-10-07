# Investigation: SSL MobileAppService trigger stuck via wrong macro context (FACTURASEND)

Jira: https://smartit-ar.atlassian.net/browse/GITIN-2028

## Trigger for this investigation

User pasted two Zabbix "Problem" rows for review:
- `SSL www.smartfran a menos de 45 dias de vencer` (`Triggered: 44 | Actual: 44`, 34m49s old) — asked whether either was anomalous.
- `SSL MobileAppService a menos de 25 dias de vencer` (`Triggered: 0 | Actual: 54`, open since 2026-09-02 22:04:52, still active) — the one that turned out to be a real bug.

## Confirmed: `SSL www.smartfran` alert is NOT anomalous

44 days remaining is genuinely under its 45-day WARN threshold (base `{$SSL_CERT_WARN}=45`), and the alert was only 34 minutes old at the time it was reviewed. Working as intended — no action taken on this one.

## Confirmed root cause: `SSL MobileAppService` triggers use the wrong macro context

All SSL-certificate-expiry monitoring is centralized on the `Zabbix server` host itself (hostid `10084`), one `log[]`-type item per service (e.g. `log[/var/log/zabbix/ssl_mobileappservice.log,,utf-8,,,,,,]`, itemid `53392`), each service having 4 independent tiered triggers (WARN/AVERAGE/HIGH/"no data") — this matches the architecture already documented in `docs/zabbix_observability.md`.

Every other service's SSL triggers (Website, WebServiceV2, Clubsite AR/PY, Smartfran/SmartFran/www.smartfran, Bot-Security) reference the **base** global macros (`{$SSL_CERT_WARN}`, `{$SSL_CERT_AVERAGE}`, `{$SSL_CERT_HIGH}`, `{$SSL_CERT_OK}` — no context suffix). Only **MobileAppService and FacturaSend** used a `:FACTURASEND` context suffix — MobileAppService's triggers were referencing FacturaSend's macro values, almost certainly a clone-and-forget-to-repoint artifact (two unrelated services, no reason to share a threshold profile).

Confirmed global macro values (`data/04_globalmacros_ssl_cert.txt`):

| Macro | Base | `:FACTURASEND` |
|---|---|---|
| `SSL_CERT_WARN` | 45 | 25 |
| `SSL_CERT_AVERAGE` | 30 | 15 |
| `SSL_CERT_HIGH` | 15 | 7 |
| `SSL_CERT_OK` (recovery) | 60 | **80** |

The WARN trigger (`triggerid 25914`) has `recovery_mode: 1` — recovery depends on a *separate* expression, not the negation of the problem condition: `last(item)>{$SSL_CERT_OK:FACTURASEND}` = **item value > 80**. The underlying item (`itemid 53392`) is not stale — `lastclock` was current, `lastvalue: 54` throughout this investigation (`data/03_mobileappservice_triggers_initial.txt`). A healthy, currently-54-days-remaining certificate can never satisfy `>80` unless MobileAppService's actual cert lifecycle produces more than 80 days remaining at some point (unconfirmed either way, but irrelevant now — see fix below) — meanwhile the trigger sits permanently "stuck" in PROBLEM state even though the cert is genuinely fine. **Confirmed false positive**, not a real expiry risk.

`lastchange` on the WARN trigger (`1788397492`) decodes to exactly `2026-09-02 22:04:52 UTC-3` — matches the user's reported alert start time precisely, confirming this is the same problem event.

## Fix applied (2026-09-11, user-directed values)

Per the user: MobileAppService's certificate renewal is already automated, so a short/tight warning window is appropriate (a healthy auto-renewing system should rarely need to alert at all). Requested thresholds: `OK>30` (recovery), `WARN<=15`, `AVERAGE<=10`, `HIGH<=2`, under a new dedicated `:MOBI` context — matching an existing naming convention already used elsewhere in this Zabbix instance for MobileAppService-specific macro overrides (`{$MOBILE_PCOUNT_SPIKE_WARN:MOBI01}`-style, per `docs/zabbix_observability.md`).

**Step 1 — created 4 new global macros** (`usermacro.createglobal`, not `usermacro.create` — global-scoped per the documented API gotcha in `ope-zabbix.md`): `{$SSL_CERT_WARN:MOBI}=15`, `{$SSL_CERT_AVERAGE:MOBI}=10`, `{$SSL_CERT_HIGH:MOBI}=2`, `{$SSL_CERT_OK:MOBI}=30`. Results: `globalmacroids 105-108` (`data/05_usermacro_createglobal_mobi_results.txt`).

**Step 2 — repointed the 3 triggers' `expression`/`recovery_expression` from `:FACTURASEND` to `:MOBI`.** Hit a real API gotcha along the way: the `{funcid}` shorthand form returned by a plain `trigger.get` (e.g. `{37378}<{$SSL_CERT_WARN:FACTURASEND}`) is **not valid input for `trigger.update`** — rejected with "incorrect expression starting from..." (`data/06_trigger_update_expression_attempt1_rejected.txt`). Resolved by re-fetching with `expandExpression: true`, which resolves to the modern `function(/host/key,params)` syntax (`last(/Zabbix server/log[...],#1)<25`) — but this form also resolves macros to their literal current values, so the macro token itself had to be manually reconstructed in place of the literal number (`data/07_trigger_functions_and_expandexpression.txt`). Final working update used `last(/Zabbix server/log[/var/log/zabbix/ssl_mobileappservice.log,,utf-8,,,,,,],#1)<{$SSL_CERT_WARN:MOBI}` etc. — all 3 succeeded (`data/08_trigger_update_final_results.txt`, Step A).

**Step 3 — operator correction (`>` vs `>=`).** Initial recovery expression used `>{$SSL_CERT_OK:MOBI}`, which for `OK:MOBI=30` would require **31+** to recover (not 30 itself). Confirmed via `item.get` that the underlying item is `value_type: 3` (unsigned integer, whole-day counts only, `data/08_trigger_update_final_results.txt` Step B) — so `>` vs `>=` is a real, meaningful one-day difference here, not cosmetic. User wanted 30 itself to count as recovered; corrected all 3 `recovery_expression`s to use `>=` (Step C).

**Step 4 — description field.** The trigger `description` field is a separate hardcoded text field, not derived from `expression` — after Steps 2-3 it still literally read `{$SSL_CERT_WARN:FACTURASEND}` etc., which would have kept displaying the resolved **FACTURASEND** value (25/15/7) in the alert name even though the trigger was now actually evaluating against **MOBI** (15/10/2) — a misleading alert name. Fixed by updating `description` on all 3 to reference `:MOBI` (Step D).

## Final confirmed state (`data/08_trigger_update_final_results.txt`)

All 3 triggers (`25914` WARN, `26282` AVERAGE, `26284` HIGH) now consistently use `:MOBI` in expression, recovery_expression, and description.

## Open item — not yet confirmed

`triggerid 25914` (WARN) still showed `value:"1"` (unrecovered, `lastchange` unchanged from the original 2026-09-02 22:04:52) as of the last check in this session. This is expected — a trigger only re-evaluates when its item gets a fresh check, not on config save — but has **not yet been independently reconfirmed cleared** after that next poll. Follow up: re-check `trigger.get` on `25914` to confirm `value:"0"` once enough time has passed for the item's log-check interval to have run at least once.

## Status

Converged and fixed. One follow-up verification (confirm 25914 actually cleared) still pending, not blocking ticket write-up.
