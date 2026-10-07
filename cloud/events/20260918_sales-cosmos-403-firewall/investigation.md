# Investigation: Sales / Cosmos DB 403 Forbidden (firewall block)

**Jira:** [GITIN-2083](https://smartit-ar.atlassian.net/browse/GITIN-2083)

## Reported symptom

User-reported: HTTP 403 errors + connection errors, "sales cosmos sales" (unclear yet whether this is the `Sales-<TENANT>` Cosmos database specifically, or the Sales App Service generally).

Error text supplied by user (source not yet confirmed — Graylog vs. raw Cosmos SDK exception vs. something else):

```
Forbidden (403) — Request originated from IP 20.253.36.226 through public internet.
This is blocked by your Cosmos DB account firewall settings.
```

This is the standard Cosmos DB SQL API firewall-rejection message: the caller's egress IP (`20.253.36.226`) is not present in the Cosmos account's IP allow-list / virtual network rules.

## Known relevant infrastructure

- Each franchise has its own **dedicated CosmosDB account** (`smartfran-cloud-cosmos-<tenantId>`), separate from the shared platform account (`smartfran-cloud-cosmos-platform-pro`) — `cloud/docs/infrastructure.md`.
- Confirmed CosmosDB account naming exception for WEISS: `smartfran-cloud-cosmos-pro-kt76igzny9q` (extra `-pro-` segment, truncated tenant id) — don't assume the plain pattern.
- `Sales-<TENANT>` Cosmos database (SQL API) confirmed containers (WEISS): `Sales`, `SaleOrders`, `Shifts`, `Movements`, `MovementCurrentAccount`, `PaymentMethods`, `KdsOrders`, `DeliveryRoutes`, `WalletNotifications`.
- Sales App Service is Windows/.NET — `AppServiceConsoleLogs` doesn't ship for it; Sales has its own direct Serilog→Event-Hub CLEF sink (GITIN-1811/1835) that does reach Graylog. `AppServiceHTTPLogs` also confirmed working for Sales (GITIN-2034).

## Open questions

- Which tenant/franchise and environment (PRO/DEV) is affected — not yet confirmed by the user.
- Whether `20.253.36.226` is a legitimate outbound IP for a SmartFran Cloud component (App Service outbound IP, NAT gateway) that fell out of the Cosmos firewall's allow-list (e.g. after a NAT gateway IP rotation or scale-out), or an unrelated/unexpected caller.
- Whether this is isolated to the `Sales` Cosmos database or affects other per-tenant Cosmos databases (Orders, Business, PersonsDB, Audit) on the same account.

## Next steps

1. Full-text search Graylog for the firewall-block message / IP to find which `Service`/`Environment`/`TenantId` actually hit it, and since when (see `scripts.sh` C1).
2. Cross-check `20.253.36.226` against the SmartFran Cloud outbound IP ranges (App Service outbound IPs, NAT gateway public IPs) to determine if this is an internal IP that fell off the Cosmos allow-list, or external.
3. Once tenant/account is identified, read the actual Cosmos DB firewall config (`az cosmosdb show` → `ipRules`/`isVirtualNetworkFilterEnabled`) to confirm the gap directly rather than inferring it from the error message alone.

## C1 result — query anomaly (2026-09-18)

First attempt (`query="Cosmos DB account firewall settings" OR "20.253.36.226"`, 7-day relative range) did **not** filter as intended: `total_results: 891990` over 7 days — a full-corpus-scale count, not a phrase-matched one — and all 100 returned hits were generic `AppServiceHTTPLogs`-category placeholder messages (`message` field literally `"AppServiceHTTPLogs"`), unrelated to the searched phrase or IP. Treating this as "no Cosmos firewall errors in Graylog" would be wrong — the query itself didn't apply the filter, root cause not yet understood (possibly how this Graylog REST endpoint handles a quoted-phrase `OR` query). Root cause of the anomaly itself still not understood — not pursuing further since the narrower retry queries below worked correctly.

## C1b/C1c results — real Cosmos 403 firewall errors found, but NOT on Sales, and NOT the user-reported IP (2026-09-18)

**C1c (`query="20.253.36.226"` alone)** returned real, relevant hits — this narrower query worked. But the matches are **not** Cosmos-related: they're normal inbound POS sale/stock traffic hitting `SmartFran.Cloud.Business.API` (`RequestHandlingMiddleware` request-body logs, `CLIENT-IP`/`X-Client-IP` headers = `20.253.36.226:10201`), tenant GRIDO (`d3186bc6d7b2`), Production — real `Venta`/`Stock/Create` payloads, not errors. **`20.253.36.226` does not appear in any actual Cosmos firewall exception found so far** — it looks like a normal upstream client/gateway IP for inbound POS calls, unrelated to the reported Cosmos block. Don't carry the user-reported IP forward as confirmed without further evidence.

**C1b (`query=firewall AND Cosmos AND NOT message:AppServiceHTTPLogs`)** found the real thing: 49 real `Microsoft.Azure.Cosmos.CosmosException` / `Forbidden (403)` / "blocked by your Cosmos DB account firewall settings" errors, all tenant **GRIDO** (`d3186bc6d7b2`), **Production**, tightly clustered **2026-09-18T21:08:00–21:09:56 UTC** (~2 minutes). Services affected: `SmartFran.Cloud.Business.API`, `SmartFran.Cloud.Person.API`, `SmartFran.Cloud.Orders.API` — **not Sales** (contrary to the original "sales cosmos sales" framing; either Sales wasn't hit, or wasn't hit within this 7-day/this-burst window — not yet checked in isolation).

**4 distinct blocked source IPs** in the real errors (not the one the user reported):
- `52.188.43.177` (bulk of the Orders.API hits)
- `52.188.42.76` (Person.API)
- `52.188.42.131` (2 Orders.API hits)
- `20.42.109.76` (Business.API)

All 4 are in Microsoft/Azure-owned public ranges (`20.x`/`52.x`), consistent with being SmartFran Cloud's own App Service outbound IPs or NAT gateway IPs — not external/malicious traffic. Working hypothesis: an outbound-IP change (App Service scale event, NAT gateway IP rotation, or similar) introduced one or more egress IPs that the GRIDO Cosmos DB account's firewall allow-list doesn't have — **not yet confirmed**, needs the actual `ipRules` on the Cosmos account and the App Services' current `outboundIpAddresses` compared directly, not inferred.

Burst ended ~21:09:56 UTC per this data — not yet confirmed whether it's recurring/ongoing at time of writing or was a one-off ~2-minute event.

## Outbound IP correlation — hypothesis strongly supported (2026-09-18)

`az webapp show --query outboundIpAddresses` for `SmartFran-Cloud-Business-PRO`, `SmartFran-Cloud-Person-PRO`, `SmartFran-Cloud-Orders-PRO` (all 3 return the **identical** 7-IP set — same App Service Plan): `52.188.42.76, 52.188.42.131, 52.188.43.40, 52.188.43.177, 52.188.43.221, 52.188.44.142, 20.49.104.9`.

**3 of the 4 blocked IPs from the real Cosmos exceptions are an exact match** to this current outbound IP set: `52.188.42.76`, `52.188.42.131`, `52.188.43.177`. This is a real (not inferred-from-format) confirmation that the traffic being blocked is SmartFran Cloud's own legitimate outbound traffic, not an external/unrelated caller.

`20.42.109.76` (the 4th blocked IP, on Business.API) is **not** in the current `outboundIpAddresses` set — not yet explained. Possibilities not yet checked: (a) it's in the App Service Plan's fuller `possibleOutboundIpAddresses` pool (outbound IPs can rotate on scale events, current `outboundIpAddresses` is only the currently-active subset) and simply isn't active right now, or (b) it belongs to a different resource entirely. Needs `az webapp show --query possibleOutboundIpAddresses` before concluding either way.

**Still not confirmed directly:** the Cosmos DB account's actual `ipRules` — everything above is a strong correlation (error text + outbound IP match), not yet a direct read of the firewall config itself. Cosmos account name for GRIDO also still unconfirmed (`az cosmosdb list -g SmartFran.Cloud.PRO.GRIDO` requested, not yet returned).

## ROOT CAUSE CONFIRMED (2026-09-18)

GRIDO's Cosmos account: `smartfran-cloud-cosmos-pro-3186bc6d7b2` (RG `SmartFran.Cloud.PRO.GRIDO`) — same naming exception as WEISS (extra `-pro-` segment, tenant id truncated: `d3186bc6d7b2` → `3186bc6d7b2`, drops the leading `d`). Not yet reflected in `cloud/docs/infrastructure.md` (currently documents only the WEISS exception) — update once this closes.

`az cosmosdb show` (direct read of the firewall config, not inferred):
```json
{
  "ipRules": [
    {"ipAddressOrRange": "0.0.0.0"},
    {"ipAddressOrRange": "181.117.137.123"},
    {"ipAddressOrRange": "186.13.46.224"},
    {"ipAddressOrRange": "200.80.249.74"}
  ],
  "isVirtualNetworkFilterEnabled": false,
  "publicNetworkAccess": "Enabled",
  "virtualNetworkRules": []
}
```

`0.0.0.0` here is Azure's sentinel value for "allow Azure Portal Data Explorer access," not a wildcard/allow-all. The other 3 entries are static IPs (likely office/VPN), unrelated to any App Service. **None of the 7 current App Service outbound IPs, and none of the 4 actually-blocked IPs from the real exceptions, are present in this allow-list.** No VNet-based bypass exists either (`isVirtualNetworkFilterEnabled: false`, `virtualNetworkRules: []`) — `networkAclBypass` (Azure-services bypass) was not queried yet, worth checking before ruling that mechanism out too.

**This is now a confirmed root cause, not a correlation:** the GRIDO Cosmos DB account's firewall simply never had SmartFran Cloud's own App Service outbound IPs allow-listed. Every Cosmos call from Business/Person/Orders-PRO (and presumably Sales-PRO, not yet checked in isolation) is exposed to this same 403 risk — the 2026-09-18T21:08–21:09:56 UTC burst is one manifestation, not a one-off fluke, and could recur at any time. Whether this is a very-recent regression (e.g. Cosmos firewall rules changed/reset) or a long-standing gap that only started manifesting now (e.g. a code path that didn't call Cosmos directly before) is **not yet determined** — worth checking Cosmos account activity log / resource change history before choosing remediation.

### Remediation options (not yet chosen by user — do not act unilaterally)

1. Add the 7 current (or ideally the fuller `possibleOutboundIpAddresses`) App Service outbound IPs to `ipRules` — narrowest fix, but outbound IPs can rotate on scale events, so needs the fuller pool or periodic re-check to stay correct.
2. Enable `networkAclBypass=AzureServices` — broader (trusts any Azure-service-tagged caller), simpler, robust to future IP rotation, but loosens the firewall beyond just these App Services.
3. Move to VNet-integrated access (regional VNet Integration + Cosmos virtual network rule) instead of IP allow-listing — most robust long-term, biggest change.

### Recheck (2026-09-18, later same session)

Re-ran `az cosmosdb show` on the same account — identical `ipRules` (still just the 4 unrelated entries), and additionally confirmed `networkAclBypass: "None"` (not queried in the first read). Rules out "already fixed" and rules out option 2 (Azure-services bypass) as an already-active mitigating factor — it's genuinely off. Gap confirmed still open at time of this recheck.

Portal link (Networking blade): `https://portal.azure.com/#resource/subscriptions/85c76dea-3304-4310-8656-bf21b28e4f4b/resourceGroups/SmartFran.Cloud.PRO.GRIDO/providers/Microsoft.DocumentDB/databaseAccounts/smartfran-cloud-cosmos-pro-3186bc6d7b2/networking

## Full scope — which services actually need Cosmos access (checked against source, `origin/dev` @ `88d021a4367296ed05ccc1893d9c4f84480a61a8`, 2026-09-18)

Much broader than the 3 services caught in the observed 403 burst (Business/Person/Orders):

**Direct Cosmos data-access code** (dedicated `CosmosClientPool`/domain repositories): Business, Orders, Person, **Platform**, **Sales** — 5 App Services. Sales and Platform have real Cosmos code paths despite not appearing in the observed burst — same exposure, just not caught failing in this particular 7-day window.

**Also wired to Cosmos indirectly**, via a shared logging provider (`CosmosBusinessLogger`/`CosmosLoggerProvider`, registered in each service's `Program.cs`): Orders, Business, Person, **Catalog**, Platform, Sales, **Security** — 7 of the 8 App Services.

**Confirmed NOT using Cosmos** (no matches in source): Admin, Pos.

**Additional Sales-specific finding (2026-09-18):** Sales.API also writes to Cosmos via two background Service Bus consumers (`MoneyMovementConsumer`/`StockMovementConsumer`, one `ServiceBusProcessor` per tenant, consuming the `"SaleClosed"` topic's `money`/`stock` subscriptions), not just inline request-path repositories. Both have a circuit breaker explicitly built as "retry storm protection" for exactly this kind of sustained Cosmos failure — on failure the message is abandoned and redelivered rather than dropped, so a firewall-blocked Cosmos call here doesn't just error once, it can drive continuous reprocessing. Cross-referenced into `cloud/events/20260918_sales-cpu-live-metrics-discrepancy/` as a leading (not yet proven) hypothesis for that day's CPU spike.

**Outside the 8 App Services**, also direct Cosmos users: 3 of the 4 onboarded Function Apps — `SFC-CodeGenerator-PRO` (+ `LiteEditionV2` variant), `SFC-TicketProcess-PRO`, `SFC-ScheduledJobs-PRO` (not `SFC-PosWasmRelay-PRO`). Plus `_MigrationData` (one-off tooling, not a running service — low priority).

**Implication for remediation:** this is effectively 7 App Services + 3 Function Apps = up to 10 separate compute resources needing Cosmos access, each with their own (rotating) outbound IP pool. Manually maintaining `ipRules` for all of them is a real ongoing burden — this is a point in favor of `networkAclBypass=AzureServices` or VNet integration over the narrow IP-allow-list option, though final call is still the user's.

## Full outbound IP inventory across all Cosmos-consuming services (`data/outbound_ips_all_cosmos_consumers.txt`, 2026-09-18)

| IP | Service(s) | In Cosmos `ipRules`? |
|---|---|---|
| `52.188.42.76`, `52.188.42.131`, `52.188.43.40`, `52.188.43.177`, `52.188.43.221`, `52.188.44.142`, `20.49.104.9` | Business, Orders, Person, Platform, Catalog (shared App Service Plan), plus `SFC-CodeGenerator-PRO`, `SFC-TicketProcess-PRO`, `SFC-ScheduledJobs-PRO` (share the same outbound set) | No |
| `20.253.36.226`, `20.253.36.230`, `20.253.36.231`, `20.253.36.250`, `20.253.36.251`, `20.253.37.4`, `20.119.8.47` | Sales-PRO — **separate App Service Plan**, own distinct outbound set | No |
| — | Security-PRO — resolved, see below | Not applicable |

**14 of 14 confirmed outbound IPs, across every Cosmos-consuming service, are absent from the firewall — zero coverage, not partial.**

**Security-PRO resolved:** not among the 8 documented shared App Services in `cloud/docs/infrastructure.md` (Pos, Admin, Business, Sales, Orders, Platform, Person, Catalog). `Services/Security/SmartFran.Cloud.Security.API` exists in source with the Cosmos logger wired up, but isn't part of the confirmed-deployed production fleet — very likely not an actual live Cosmos consumer in PRO. Not chasing outbound IPs for it further; the 14-IP list above is treated as the complete confirmed exposure set.

**Correction to the earlier IP dismissal:** `20.253.36.226` (the IP from the user's original report at the start of this investigation) is confirmed here as **Sales-PRO's own outbound IP** — not just an unrelated inbound POS client IP as I'd concluded earlier from seeing it in Business-PRO's request logs. Since Sales-PRO has confirmed direct Cosmos code (`CosmosClientPool` in `Sales.Infrastructure`), this IP getting firewall-blocked is fully consistent with the original report — it just wasn't in the specific 7-day burst captured for Business/Person/Orders. Retracting "don't carry the user-reported IP forward" — it should be carried forward, just understood as an outbound IP rather than a request-source IP.
