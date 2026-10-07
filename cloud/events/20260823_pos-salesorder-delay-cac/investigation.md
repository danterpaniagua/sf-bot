# Investigation — POS delay on Cobrar Orden / Anular Venta, tenant CAC (GITIN-1917)

**Status:** root cause identified for the "Cobrar Orden" delay — client-side (POS Blazor WASM `html2canvas` ticket-preview rendering, no timeout), not cloud infrastructure. See "Second HAR capture + definitive client-side root cause" below. "Anular Venta" not yet independently re-verified against this same root cause — its own HAR entries (`Sale/Cancel`, 5.5s/2.7s) were noted but not traced through source in this session.

## Objective

CAC reports latency in the POS app on three actions:
1. `/salesorder` — tapping "Cobrar Orden" (charge order), and the state transition NUEVO → COBRADO in general.
2. "Anular Venta" (void/cancel sale).

Reported by the user, not yet independently confirmed against telemetry (App Insights, Cosmos RU metrics). Environment (PRO assumed) and exact time window not yet confirmed.

**Tenant identity — resolved (2026-08-23):** "CAC" is shorthand for the **Canning** branch/franchise under the **WEISS** tenant — WEISS is already a confirmed onboarded tenant (`cloud/docs/infrastructure.md`), with a documented Cosmos layout (`Sales-WEISS`, `Orders-WEISS`, etc., partition key `[/FranchiseeCode, /FranchiseCode, /PosCode]`). No separate tenant onboarding gap — the `organizations` App Config lookup is not needed for scoping. Still need to confirm which of `FranchiseeCode`/`FranchiseCode`/`PosCode` actually holds "Canning" before filtering Cosmos/App Insights queries.

**Aside (tangential, not blocking this ticket):** attempting to read the `organizations` key from `SmartFran-Cloud-Settings-PRO` during tenant-identity troubleshooting surfaced a real, separate issue — `az appconfig kv show`/`list` crash with a Python `JSONDecodeError` instead of a clean error message. Root cause confirmed via direct REST call (`curl` with AAD token, bypassing the CLI): the App Config data-plane endpoint returns `403` with an **empty body**, which the CLI's error deserializer doesn't handle gracefully. This points to a missing **App Configuration Data Reader** (or Data Owner) RBAC role on `SmartFran-Cloud-Settings-PRO` for the querying identity — `Reader`/`Contributor` at the resource scope does not grant data-plane key-value access. `az role assignment list --scope <store> --include-inherited` still pending to confirm definitively. Worth a separate follow-up (IAM role grant) but out of scope for this ticket.

## Source-level mapping (confirmed via `repo/SmartFran.Cloud`, `origin/main` @ `94d624efb`)

Spanish state labels (NUEVO/COBRADO) are UI-only — the backend model is English (`Pending`/`Paid`, 3-step model). Endpoint mapping:

| POS action | Endpoint | Controller/Service |
|---|---|---|
| "Cobrar Orden" | `POST api/v1/SaleOrder/{id}/pay` | `SaleOrderController.PayOrder` → `SaleOrderService.PayOrderAsync` → `ExecuteTransitionByIdAsync` |
| "Anular Venta" | `PATCH api/v1/Sale/Cancel` | `SaleController.CancelAsync` → `SaleService.CancelAsync` |

### `PayOrderAsync` path (lean)

`GetByIdAsync` (Cosmos read, `SaleOrders` container) → in-memory state transition → `UpdateAsync` (Cosmos write) → controller then awaits `NotifyOrderUpdatedAsync` (SignalR). No external HTTP dependency in this path. Candidate bottlenecks: Cosmos RU throttling (429/retry) on `Sales-<TENANT>`'s `SaleOrders` container, or the awaited SignalR notification (Azure SignalR) hanging/throttling before the HTTP response returns.

### `CancelAsync` path (heavy — most plausible source of the "Anular Venta" delay)

Long sequential chain, all synchronous/awaited in series (from `SaleService.cs`):
1. `GetMovementsTypesAsync` + repository lookup for the sale.
2. `sale.Cancel()` (in-memory) + turno/shift validation.
3. If sale has an external MercadoPago payment: refund call — V2 (QR Wallet) tried first, V1 (legacy) as fallback. **External HTTP call to MercadoPago**, not fatal on error but still awaited before continuing.
4. `UpdateAsync #1` (Cosmos write — cancelled state).
5. `AddMoneyMovementsAsync` + `UpdateAsync #2` (Cosmos write — money movement data).
6. Stock offset: `StockOffsetMovementAsync` (or legacy `AddStockMovementsAsync` fallback) + another `UpdateAsync`.
7. KDS order cancel (`SetCancelledAsync`), non-fatal on error.

Every step is logged individually (`_log.LogInformation("[CancelAsync] ...")`) — this gives good signal for App Insights `traces`/`dependencies` correlation once we have a real `traceId`/`OperationId` from a slow request. Candidate bottlenecks: MercadoPago refund latency (step 3, only applies to sales paid via MP wallet), or cumulative Cosmos RU throttling across 3 sequential `UpdateAsync` calls (steps 4/5/6) — a single 429/retry on any one of them adds directly to total request latency since nothing here runs in parallel.

## Working hypotheses (unconfirmed, ranked by plausibility)

- **H1 — CosmosDB RU throttling** on the `Sales-<TENANT>` database (`Sales`/`SaleOrders` containers). Both paths hit Cosmos synchronously; `CancelAsync` hits it 3x sequentially. Would explain delay on both actions since they share the same containers. Needs RU consumption / 429 metrics.
- **H2 — MercadoPago refund latency**, `CancelAsync` only (step 3). Would explain "Anular Venta" delay in isolation without touching `PayOrderAsync`, but only for sales with an external MP wallet payment — doesn't explain it if CAC's cancelled sales are mostly cash/other tenders.
- **H3 — Azure SignalR** notification path (`NotifyOrderUpdatedAsync`, both controllers await it before returning). Would explain delay on both `PayOrder` and order-side cancel, but `SaleController.CancelAsync` ("Anular Venta") doesn't call this notifier at all — only `SaleOrderController` does — so this alone can't explain a shared root cause across both reported symptoms unless it's coincidental/separate.
- **H4 — General App Service performance** (Sales-PRO CPU/memory/instance count, unrelated to any specific business logic) — needs ruling out before trusting any code-path-specific theory above.

None of these are confirmed. Next step is pulling real telemetry, not guessing further from source.

## Confirmed against real telemetry (2026-08-23, reported incident window 2026-08-22 afternoon ART)

**App Insights query gap (blocking, unresolved):** `az monitor app-insights query --app SmartFran-Cloud-Sales-PRO_new` consistently returns empty for `requests` over both 24h and 7d windows, despite the component existing, being `Succeeded`-provisioned, and the App Service (`SmartFran-Cloud-Sales-PRO`) having the exact matching `APPINSIGHTS_INSTRUMENTATIONKEY`/`APPLICATIONINSIGHTS_CONNECTION_STRING` configured (both reference `e357f2f5-482b-4bf2-a10f-6b97aa73aec2`). Confirmed this isn't a resource-resolution problem — the same command against a genuinely nonexistent component (`SmartFran-Cloud-Business-PRO_new`, itself a doc-drift finding: contradicts `infrastructure.md`, not chased further here) throws a clear `ResourceNotFound`, while Sales-PRO_new just returns zero rows. Root cause not yet determined (adaptive sampling filtering everything, request auto-collection not actually enabled in the SDK, or something else) — worked around by going directly to the underlying Log Analytics workspace (`SmartFranCloudPro`) and querying `AppRequests` natively instead of through the App Insights compatibility API.

**Platform-level App Service metrics (`Microsoft.Web/sites/SmartFran-Cloud-Sales-PRO`), 2026-08-22 13:00–23:59 UTC (≈10:00–20:59 ART), 15-min buckets:**
- Average response time stays flat (~0.3–0.55s) throughout, even as request volume ramps ~30-40x (144 total/15min at 13:00 → ~5,500/15min by 21:00).
- Maximum response time per bucket is persistently high from ~14:45 UTC onward — most buckets show a max in the 10–23s range (e.g. 19:00 → 19.4s, 22:15 → 23.2s), not a one-off spike.
- `Http5xx` is ~0 the whole window (2 total across 11h) — the slow requests are succeeding, not failing.

This shape (flat average, persistent high tail latency scaling with load, near-zero errors) is what CosmosDB RU throttling with transparent SDK retry-on-429 would look like — **but this is refuted**: Cosmos account-wide (`smartfran-cloud-cosmos-platform-pro`) `TotalRequests` filtered to `StatusCode eq '429'` returns zero matching series for the exact same window, confirmed against a validated dimension list (`StatusCode` is a real filterable dimension on `TotalRequests`; the empty result isn't a bad-filter artifact — a baseline unfiltered query on the same metric/window returns real data, ~875K–1.1M total requests/hour account-wide). **H1 is refuted.**

Important caveat: the App Service HTTP metrics above are **service-wide**, not endpoint-specific — Sales-PRO also serves fiscal webservice calls (`WsFeAr`/`Pe`/`Py`/`Uy`), reports, shifts, etc. We have not yet confirmed the tail latency is actually coming from `SaleOrder/pay` or `Sale/Cancel` specifically, as opposed to some other heavy endpoint on the same App Service. Pivoting to a direct `AppRequests` query against the Log Analytics workspace to get real per-operation numbers — in progress.

## Real per-operation data (2026-08-23, via Log Analytics workspace `SmartFranCloudPro` directly — `AppRequests` table, `AppRoleName == 'smartfran-cloud-sales-pro'`, window 2026-08-22 13:00–23:59 UTC)

`az monitor app-insights query --app SmartFran-Cloud-Sales-PRO_new` never worked for this (see App Insights query gap above) — the actual `AppRoleName` in the workspace is the lowercase App Service name (`smartfran-cloud-sales-pro`), not the App Insights component name. Querying the workspace's native `AppRequests` table directly with the correct role name finally produced real data.

**Sampling caveat:** only 3,033 requests logged for Sales-PRO in this table over the 11h window, vs. ~130,000+ actual HTTP requests to the same App Service per the platform-level `Requests` metric over the same period (~2.3% capture rate) — likely aggressive adaptive sampling specific to this (Windows) App Service. Numbers below are from that partial sample; true max latencies are very likely understated, not overstated.

**No `SaleOrder`-family operation appears anywhere in the sample** (not `pay`, `cancel`, `create`, `deliver`) despite reasonable overall sample size. This contradicts the original endpoint-mapping assumption in this file (`SaleOrder/{id}/pay` = "Cobrar Orden") — Canning/WEISS almost certainly uses the **classic 2-step `Sale` flow** (`Sale/Create` → `Sale/Close`), not the newer 3-step `SaleOrder` model. Revised mapping: "Cobrar Orden" (NUEVO → COBRADO) = `Sale/Create` followed by `Sale/Close`; "Anular Venta" = `PATCH Sale/Cancel` (mapping unchanged).

Top operations by max latency (partial list, full sample was ~35 distinct operation names):

| Operation | Count | Avg (ms) | Max (ms) |
|---|---|---|---|
| `POST Sale/Close` | 537 | 707 | **13,457** |
| `POST WsFeAr/CaeRequest` | 374 | 2,355 | **11,228** |
| `GET Shift/GetPaginatedForReportByFilter` | 7 | 6,876 | 11,199 |
| `POST Sale/Create` | 523 | 325 | 8,609 |
| `PATCH Sale/AddBill` | 47 | 281 | 7,020 |
| `PATCH Sale/Cancel` | 4 | 1,568 | 2,208 |

## Working conclusion (evidence-based, not end-to-end traced — see caveats)

Two distinct, both-real contributors identified, **not yet proven causally linked to each other via a shared `operation_Id`** (that level of tracing wasn't done — this is inference from code + correlated timing, flagged accordingly):

1. **`Sale/Close` itself is slow (max 13.5s) because of its own synchronous cross-service call chain**, confirmed by source (`SaleService.ProcessBackgroundTaskAsync`, verified against real `main`/PRO branch — see branch-verification note below). In the "legacy inline" path (used whenever `_saleCloseFeatureFlag.ShouldUseServiceBusAsync(posCode)` is false for a given POS — **not yet confirmed which path Canning's POS actually uses**), closing a sale calls, sequentially and awaited:
   - `_moneyMovementCreator.CreateAsync` → `IMovementServices.POSCreateAsync` (internal, Sales' own Cosmos-backed movement service).
   - `_stockMovementCreator.CreateAsync` → **three sequential cross-service HTTP calls**: `Business.V1.FranchiseGetSaleMovementSetupAsync`, `Business.V1.StockCreateAsync`, `Catalog.V1.CostPriceListGetItemsCostsAsync` (i.e. two calls to `Business-PRO`, one to `Catalog-PRO`).
   - A final `_saleRepository.UpdateAsync` (Cosmos write).
   
   Any slowness in `Business-PRO` or `Catalog-PRO` cascades directly into `Sale/Close`'s latency, since nothing here runs in parallel. This alone is enough to explain "Cobrar Orden" feeling slow, independent of anything fiscal.

2. **`WsFeAr/CaeRequest`** (AFIP fiscal invoice / CAE request, Argentina) is itself consistently slow — avg 2.35s, max 11.2s, called 374 times (roughly tracking sale volume) — and is a **separate top-level inbound request** in the telemetry (its own `AppRoleName`/operation, not nested under `Sale/Close`), meaning POS calls it directly as its own step in the checkout flow, not as an internal dependency of `Sale/Close`. If Canning's checkout sequence is POS-orchestrated as `Sale/Create` → `WsFeAr/CaeRequest` → `Sale/AddBill` → `Sale/Close` (plausible given all four appear as separate high-volume operations with correlated latency), the cashier's perceived "Cobrar Orden" delay is the **sum** of all four steps, with AFIP's external webservice as a likely major contributor on its own.

**Refuted:** CosmosDB RU throttling (H1) — confirmed zero `429`s account-wide for the incident window, against a validated metric/dimension (see above). **Not yet tested:** MercadoPago refund latency (H2, `Sale/Cancel` only — but `Sale/Cancel`'s own sample shows much lower latency, max 2.2s, so this looks like a minor contributor at most, though the 2.3% sampling means this could be understated). Azure SignalR (H3) not investigated further — `SaleController.CancelAsync` doesn't call the SignalR notifier at all per source, so it can't explain "Anular Venta" specifically.

## Branch verification (2026-08-23)

Local `repo/SmartFran.Cloud` working tree was on `dev`, confirmed **181 commits behind** `origin/main` (the real PRO release branch, HEAD `94d624efb`, "Stg => PRO v02.41.00 20-08-2026") at the time of this check. All source claims in this file were made after checking out and pulling `main` — except the two files whose relevant methods were re-verified post-checkout (`SaleService.cs`, `StockMovementCreator.cs`, `SaleOrderController.cs`, `SaleController.cs`). Diffed `dev` vs `main` on those files specifically: the only divergence is an unrelated stock-quantity unit-conversion fix (wholesale `StockUnitFactor` handling) — the call chain / cross-service dependency structure relied on above is identical in both branches, so this doesn't change the conclusion, but the verification gap itself is worth flagging as a process note (should check out/diff against `main` at the *start* of a PRO investigation, not partway through).

## Direct confirmation + HAR analysis (2026-08-23, real capture from a Canning collaborator's browser — user relaying secondhand, not present at the PC themselves)

Received `weiss.pos.smartfran.com.har` (real browser export). Confirms hostname is `weiss.pos.smartfran.com` — consistent with the WEISS tenant resolution already established. Ground-truth timestamp in the HAR: `POST /api/v1/Sale/Close` started **2026-08-23T18:33:38.370Z** (≈15:33 ART), total logged **19,383ms** — the verbally-reported "19:30 ART" was off by ~4h from the actual capture; using the HAR's own timestamp as authoritative.

**Detailed timing breakdown reveals this specific instance is NOT backend latency:**
- The Service Worker's own `_workerRespondWithSettled` timing for this entry is **1,144ms** — matching a parallel "real network" HAR entry for the same call (`1,141ms` total, real `serverIPAddress` populated, `wait: 989ms`). **The Sales-PRO backend answered in ~1.1s.**
- The response body was ~0 bytes (`content.size: 0`) — nothing to justify a long body-download phase.
- The POS PWA's Service Worker (`service-worker.published.js`, checked against real `main`) has **no custom logic for POST/PATCH requests** — `onFetch` only special-cases `GET` (a `Favourites` cache-first branch and an offline `index.html` shell); everything else, including `Sale/Close`, is a bare `return fetch(event.request)` passthrough. Ruled out as a caching/IndexedDB-induced delay.
- Yet the HAR entry's **total logged time is 19,383ms**, with an 18.2s gap between the Service Worker settling the response (~1.1s in) and... nothing. Checked all other HAR entries in that window: **zero network activity of any kind from +0.87s to +15.62s** (dead silence, no other Blazor WASM/API calls), then a **burst of unrelated requests fires all at once** (logo, CSS, fonts, MudBlazor/AOS styles, gravatar avatar) — the classic signature of a **full page reload/navigation**, not a continuation of the same session.

**Collaborator's account (relayed, 2026-08-23):** not frozen — a loading/waiting indicator was shown continuously while the order applied, transitioning NUEVO → COBRADO. This refutes the reload theory (a hard UI-thread freeze would typically stutter/stop a spinner animation too, and the collaborator describes normal waiting-state UI, not a stuck screen) — **no reload occurred**; the request burst at +15.62s is not a page navigation.

**Revised working theory:** the backend answered fast (~1.1s), but the POS app kept its waiting/spinner state up for ~18 more seconds doing something else client-side before transitioning to COBRADO. Notably, `LogoTicket_kt76i` (a receipt/ticket logo asset) appears again in the +15.62s burst alongside other UI assets — suggestive of the client performing **receipt/ticket rendering** (or similar post-close UI work) after a successful `Sale/Close`, before finalizing the state transition on screen. This would be a **client-side Blazor WASM performance issue in the POS app itself** — not backend/cloud-infrastructure latency — a different bug class than anything traced through Sales-PRO/Business-PRO/Catalog-PRO/Cosmos so far, and not something Azure-side changes would fix. Not yet proven (would need the POS client source — `Pos.Wasm`/`Pos.Component` — or a client-side profiler trace to confirm what specifically runs during that 18s gap), but well-supported by the HAR evidence and the collaborator's description together.

**This doesn't overwrite the earlier server-side finding** (2026-08-22 `AppRequests` sample showing `Sale/Close` max 13.5s server-measured, correlated with the `StockMovementCreator`→Business/Catalog cross-service call chain) — that was a different day, aggregate telemetry, not this specific HAR-captured instance. Both could be real, independent, coexisting causes of "Cobrar Orden feels slow": (a) genuine backend cross-service latency in some fraction of calls, and (b) a client-side freeze-after-fast-response in this captured instance. Not yet reconciled — could also be the *same* underlying stall manifesting differently depending on where it's measured (App Insights measures server-side request duration, which wouldn't capture a client-side post-response hang at all) — worth keeping in mind rather than treating these as necessarily two separate bugs.

The earlier Business-PRO/Catalog-PRO metrics pull came back all-zero because it used the wrong (verbally-estimated, incorrect) time window — needs to be redone against the correct 18:33Z window if the cross-service-latency theory is still worth testing independently of the client-freeze theory.

## Decisive finding — `Sale/Close` is fire-and-forget on the client; the real await chain is local printing (2026-08-23, POS client source, `Source/Pos/SmartFran.Cloud.Pos/SmartFran.Cloud.Pos.Component/Pages/Pos/Sale.razor.cs`, verified against real `main`)

Traced the actual "Cobrar" checkout handler in `Sale.razor.cs`. The `SaleCloseAsync` HTTP call is **discarded twice over** — never awaited by the client at all:

```csharp
_ = Task.Run(async () => {
  ...
  _ = _proxy.Services.Sale.V1.SaleCloseAsync(closeTenant, closeCmd);   // line 4868
});
```

This means the 19s the HAR recorded for the `Sale/Close` HTTP request is **architecturally irrelevant to what the UI is actually waiting on** — the app moves on immediately after dispatching it, regardless of how long it takes or even whether it succeeds from the client's perspective. The HAR's total time for that entry is very likely a Service-Worker/DevTools lifecycle artifact, not a real blocking wait — reinforced by the fact that its own `_workerRespondWithSettled` (1.1s) already showed the real backend answer was fast.

Immediately after dispatching the fire-and-forget close, the code **does** genuinely `await` several steps in sequence, matching the "waiting image ... NUEVO, then COBRADO" the collaborator described:
1. `await CreateKdsOrderIfNeeded()` — only if the POS has KDS (Kitchen Display System) enabled.
2. `await PrintOrderIfNeeded()` — kitchen/dining-area ticket print.
3. `await Print("fiscal", "POSDefaultPrinter", true)` — fiscal ticket print, only if a `bill` was generated.

All three printing paths go through `JsPrintManager` / `IRemotePrintingService` / `PrintDispatcher.SendAsync` (`Services/Printing`) — a local WebSocket bridge (Neodynamic-style JS Print Manager pattern, per `JsPrintManager.StartForDevice(RemotePrintingService.UrlLic, DeviceInfo)`) to a **physical printer on the store's local network**, not any Azure/cloud service. This is a fundamentally different dependency than everything traced through Sales-PRO/Business-PRO/Catalog-PRO/Cosmos so far.

**Revised primary hypothesis:** the "Cobrar Orden" delay for Canning is most plausibly a **slow or unresponsive local printer / print-bridge at the store**, not cloud backend latency, not CosmosDB, not cross-service calls. This would explain everything observed: fast backend (~1.1s, confirmed via HAR), zero 5xx errors (nothing actually fails, it just hangs waiting on print), and a visible waiting indicator between NUEVO and COBRADO that only clears once the print call(s) resolve or time out.

**This likely shifts scope**: printer/print-bridge issues at a specific store are not an Azure/SmartFran-Cloud-infra problem — this may need to go to POS support / whoever manages Canning's printer hardware and the JS Print Manager local service, rather than continuing as a cloud investigation.

## Confirmation from the collaborator (2026-08-23) — nothing actually prints

Asked whether the kitchen/fiscal ticket printed at the end of the wait: **it doesn't, because these are test sales the collaborator immediately cancels afterward** (no bill requested, so `Print("fiscal", ...)` doesn't run). Confirmed this reproduction is on **Canning's real POS terminal**, not a remote/office machine missing printer hardware.

This still doesn't clear the printing theory — `PrintOrderIfNeeded()` (the kitchen/dining "comanda" ticket) runs **unconditionally on every sale close, regardless of billing or cancel intent** — confirmed by source, it's called right after the fire-and-forget close with no gating condition. So a print attempt genuinely fires every time, including these test sales; "nothing prints" is consistent with that attempt failing or hanging rather than succeeding, not with it never being attempted.

**Traced the actual print call chain** (`Sale.razor.cs:Print()` → `PrintDispatcher.SendAsync()`, `Services/Printing/PrintDispatcher.cs`, verified against real `main`):
- Non-Android path: `await jspm.SendClientPrintJobAsync(job)` — a bare call into the third-party **Neodynamic JS Print Manager** library talking to a local WebSocket bridge service on the POS terminal. No timeout/cancellation token in SmartFran's own code; whatever hang/retry behavior exists here is internal to that library, not visible in this repo.
- Android path: converts the ticket to ESC/POS raster commands, sends via the same `SendClientPrintJobAsync`, then an **intentional drain delay** (`DrainBaseMs=1200ms` + up to `DrainMsPerKb=60ms/KB`, capped at `DrainMaxMs=8000ms`) to let a slow mechanical printer finish before the next job — capped, so this alone doesn't explain an 18-19s wait, but if `SendClientPrintJobAsync` itself hangs (printer/local bridge unreachable), that part is unbounded.
- `ResolveEndpointAsync` would fail fast with a warning snackbar (no delay) if no printer were configured for the POS role at all — ruled out, since a fast failure wouldn't produce the observed multi-second wait.

## Working conclusion (revised, final for this session)

**Primary hypothesis, well-supported but not lab-confirmed:** Canning's local printer or its local print-bridge (JS Print Manager service) is unresponsive or slow to connect, causing the unconditional `PrintOrderIfNeeded()` comanda-print call to hang for ~15-20 seconds on every "Cobrar Orden," before the client gives up (or the underlying library eventually times out) and the UI proceeds to COBRADO with nothing actually printed. This is **not a SmartFran Cloud / Azure infrastructure issue** — it doesn't implicate Sales-PRO, Business-PRO, Catalog-PRO, CosmosDB, or Service Bus, all of which were checked and are behaving normally (or, in the earlier 2026-08-22 telemetry sample, show a separate/still-unreconciled server-side latency pattern on `Sale/Close` that may or may not be related — not disproven, just not what explains *this* specific captured instance).

**Not yet confirmed:** the exact failure mode inside `SendClientPrintJobAsync`/JS Print Manager (unreachable local service vs. an unresponsive physical printer vs. a network printer timeout), and whether "Anular Venta" (`Sale/Cancel`, which showed up separately in the HAR at 18:35:19-26, 5.5s/2.7s) shares this same printing-related cause or is independent — `Sale/Cancel`'s own code path was not re-checked for printing/local-hardware calls in this session.

## Second HAR capture + definitive client-side root cause (2026-08-23, `weiss.pos.smartfran.com(1).har`)

A second, independent reproduction on Canning's real POS terminal shows the **identical signature**: `Sale/Close` outer HAR entry = 17,390ms vs. its real network entry = 984ms (backend fast again); then **13.75s of total silence** (zero network activity), then the **same asset burst** (`app.css`, `MudBlazor.min.css`, `aos.css`, `logo.png`, gravatar avatar, `LogoTicket`, Google Fonts) as the first capture. Two independent captures producing the same pattern rules out a one-off fluke.

Checked both HARs for `Kds/orders` calls (ruling in/out `CreateKdsOrderIfNeeded()`, which runs before printing if KDS is enabled): present in both, but fired ~40-45 seconds **before** `Sale/Close` (at order-placement time, a separate step), fast (~400ms). **Ruled out** as the cause of this specific gap.

**Traced the actual call**: `PrintCommandPreview()` → `Print()` → `await _js.InvokeAsync<string>("window.getBase64", model)` (`Sale.razor.cs:4138`). Found `getBase64` in `Source/Pos/SmartFran.Cloud.Pos/SmartFran.Cloud.Pos.Wasm/wwwroot/js/clientPrint.js`:

```js
function getBase64(elementId) {
    return new Promise((resolve, reject) => {
        var item = document.getElementById(elementId);
        var clone = item.cloneNode(true);
        document.body.appendChild(clone);
        clone.style.position = 'relative';
        clone.style.left = '-9999px';
        clone.style.display = 'block';
        clone.style.width = '1024px';

    html2canvas(clone, {
        logging: true,
        letterRendering: 1,
        scale: 1,
        allowTaint: false,
        useCORS: true
    }).then(canvas => { resolve(canvas.toDataURL()); document.body.removeChild(clone); });
    });
}
```

This is the definitive root cause candidate, well-supported by every piece of evidence gathered:
- **`useCORS: true`** makes `html2canvas` itself fetch every image/font referenced in the cloned ticket-preview DOM (logo, `LogoTicket`, web fonts) as part of rendering the canvas — **exactly** matching the asset burst observed in both HARs, including external resources (`fonts.googleapis.com`/`fonts.gstatic.com`, `s.gravatar.com`, `i1.wp.com`/`cdn.auth0.com` avatar redirects) whose latency is entirely outside SmartFran Cloud's control.
- **No timeout anywhere in this call** — if any fetched resource is slow, `html2canvas` simply waits; nothing bounds the total time.
- **`logging: true`** — debug logging left enabled in production, adding unnecessary overhead on every print, independent of the main issue.
- This runs on **every `Sale/Close`**, printer-need or not (confirmed earlier: unconditional, no gating on billing/KDS/cancel-intent) — consistent with the collaborator's test sales (no bill, immediately cancelled) still going through this exact path.

**This is a client-side JavaScript/rendering performance issue in the POS Blazor WASM app — not SmartFran Cloud/Azure infrastructure, not the backend, not local printer hardware/network.** Sales-PRO, Business-PRO, Catalog-PRO, CosmosDB, and Service Bus have all been checked and are not implicated in this specific incident.

## Recommended next steps (handoff — dev, not infra)

This is a **dev handoff**, not an Azure/infra fix — no SmartFran Cloud resource change would address this. Superseded the earlier printer-hardware theory (kept above for the record — was a reasonable hypothesis given the evidence at the time, refuted by the `getBase64`/`html2canvas` source trace).

1. **Add a timeout around `getBase64`/`html2canvas`** (`clientPrint.js` / `Sale.razor.cs:Print()`) so a slow font/image fetch degrades gracefully (e.g. print without the logo, or skip the preview image) instead of blocking "Cobrar Orden" indefinitely for the cashier.
2. **Remove `logging: true`** from the `html2canvas` call — debug logging left on in production, unnecessary overhead on every single sale close.
3. **Reconsider `useCORS: true`** and the external resource dependencies it pulls in at render time (`fonts.googleapis.com`, `s.gravatar.com`, `cdn.auth0.com` avatar redirects) — none of these should be in the critical path of printing a receipt; inlining/self-hosting fonts and avoiding avatar-image fetches in the printable ticket template would remove the exposure to slow/unreachable third-party CDNs entirely.
4. **Check whether "Anular Venta" (`Sale/Cancel`) shares this same code path** — not verified in this session. If `SaleCancelAndBill.razor.cs` or similar also calls into ticket/receipt rendering via `getBase64`, the same fix would address both reported symptoms; if not, "Anular Venta"'s cause remains open and would need its own trace.
5. Not yet confirmed end-to-end in a controlled test (e.g. throttling/blocking Google Fonts or gravatar to reproduce the exact stall) — the source-level explanation is strong but hasn't been isolated to one specific resource fetch inside `html2canvas`.

## Next steps

1. **Confirm which `Sale/Close` path Canning's POS actually takes** — inline (legacy) vs. Service Bus async (`_saleCloseFeatureFlag.ShouldUseServiceBusAsync`) — only the inline path has the synchronous cross-service calls implicated above.
2. Pull `Business-PRO` and `Catalog-PRO` platform-level HTTP metrics (same pattern as the Sales-PRO `Microsoft.Web/sites` query used above) for the same 2026-08-22 window, to see if their response times spike in correlation with `Sale/Close`'s spikes — this would directly confirm (or refute) the cross-service-call theory instead of leaving it as a code-level inference.
3. If possible, get a sample of real slow `Sale/Close` `operation_Id`s and check for linked `AppDependencies` rows (same `operation_Id`) to see the actual internal breakdown (Business call vs. Catalog call vs. Cosmos) — would need dependency telemetry, not yet pulled (unclear if it's subject to the same ~97% sampling gap as `AppRequests`).
4. Confirm whether `WsFeAr/CaeRequest`'s latency is AFIP-side (external, nothing SmartFran Cloud can fix directly beyond timeout/retry tuning or async UX) vs. something in the SmartFran-side WSAA/CMS signing step before the call reaches AFIP.
5. Tangential, non-blocking for this ticket: the App Config `organizations` key 403/RBAC gap and the ~97% App Insights sampling gap on Sales-PRO specifically are both real findings worth their own follow-up, but out of scope here.
