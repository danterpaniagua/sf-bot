# Investigation — 20260831_mobi_lb_config_review

**Status:** open — proactive review, ticket GITIN-1967 (empty on Jira, no description yet; parent GITIN-1965 per user, 2026-08-31)

## Scope

Review `SFCG-MOBI-LB` (Azure Standard Load Balancer fronting `SFCG-MOBI-01`/`SFCG-MOBI-02`, MobileAppService) configuration. Not incident-driven.

## Confirmed facts (inherited from GITIN-1909, `loyalty/events/20260821_mobileappservice_loadtest_503/`, re-verify before reuse — 10 days old)

- SKU: Standard. Frontend: single public config `SFCG-MOBI-LB-frontendconfig01`, public IP `SFCG-MOBI-LB-publicip` = `20.121.19.174` (static).
- Single rule: `SFCG-MOBI-LB-lbrule02` — TCP 8043→8043, `idleTimeoutInMinutes=15`, backend pool `SFCG-MOBI-LB-backendpool01`, probe `SFCG-MOBI-LB-probe02`, floating IP disabled.
- Backend pool contains both `sfcg-mobi-01421` and `sfcg-mobi-02639` NICs — both hosts confirmed live in rotation.
- **Active probe** `SFCG-MOBI-LB-probe02`: plain TCP, port 8043, 5s interval, `numberOfProbes=1` — flagged in GITIN-1909 as unusually aggressive vs. Azure's typical ≥2 recommendation.
- **Two orphaned probes exist, referenced by no current rule:** `SFCG-MOBI-LB-probe01` (HTTP GET `/api/MobileAppService/CheckServiceStatus`, 5s interval, `numberOfProbes=2` — already correctly configured for an app-aware health check, just not wired to the rule), and an HTTPS `/healthcheck.ashx` probe (5s interval, `numberOfProbes=1`).
- **Confirmed real-world impact of the TCP-only probe (2026-08-21):** when Mobi02 booted, the TCP-only probe marked it healthy as soon as port 8043 accepted connections — before IIS/the app pool was actually able to serve requests. The LB (no grace period, `numberOfProbes=1`) routed live traffic into that gap, producing 9 real HTTP `503`s + connection resets from a WAS restart. GITIN-1909's root cause for the *original* incident was unrelated (`connectionTimeout=15s`), but this probe issue was a real, separate, confirmed-impact finding — explicitly marked out-of-scope for that ticket and deferred as tech debt.
- No WAF/L7 device in front of MobileAppService — path is NSG (one-to-one source-IP allow-list, not subnet-based) → `SFCG-MOBI-LB` (L4) → IIS.
- Not yet reviewed in either ticket: outbound rules/SNAT configuration (Standard LB requires explicit outbound rules or a NAT Gateway — no default outbound like Basic SKU), load-balancing distribution mode (5-tuple vs. 2-tuple/3-tuple session affinity), zone redundancy of the frontend/backend, and LB diagnostic settings/logging.

## Working theory

N/A — proactive config review, not root-causing. Leading candidate action: replace or supplement `SFCG-MOBI-LB-probe02` (TCP-only, `numberOfProbes=1`) with the already-existing, already-correctly-configured `SFCG-MOBI-LB-probe01` (HTTP, app-aware, `numberOfProbes=2`) on the live rule — this would have prevented the 2026-08-21 startup-gap 503 burst. Needs re-confirmation that `probe01`'s HTTP endpoint is still valid/healthy before switching (an app-aware probe against a broken health endpoint would be worse than a working TCP probe), and needs to check whether the orphaned probes are still configured as GITIN-1909 documented them (10 days old, unverified since).

## Ruled out

N/A yet.

## Open questions / next steps

- Confirm ticket GITIN-1967 stays empty/proactive or gets a description later that narrows scope.
- Re-verify all inherited LB config facts above are still current (`az network lb probe list` / `az network lb rule list`) before acting on them — 10 days old, unverified since GITIN-1909 closed.
- Confirm `/api/MobileAppService/CheckServiceStatus` (the orphaned `probe01`'s target) is a real, currently-working endpoint on both hosts before proposing it as the replacement probe.
- Review outbound rules/SNAT, distribution mode, zone redundancy, diagnostic settings — none of these were covered by GITIN-1909 (that investigation was root-cause-driven, not a full config audit).
