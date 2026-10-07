# Investigation — 20260917_smartpedidos-peru-orders-pending

**Jira ticket:** [GITIN-2068](https://smartit-ar.atlassian.net/browse/GITIN-2068)

## Reported symptom

SmartCloud is not receiving orders from SmartPedidos. Narrowed by the user: **orders from Peru specifically are stuck in "Pending" status.** Not yet confirmed whether this means all countries are affected and Peru is just the first noticed, or Peru specifically is the only one impacted.

## Architecture context

- SmartPedidos (`smartpedidos/CLAUDE.md`): `platforms-service` receives orders from delivery platforms, persists to MongoDB, **pushes accepted orders to AWS SQS**, routed to branch POS terminals via SmartCloud.
- No prior local investigation involving Peru specifically was found in either `cloud/events/` or `smartpedidos/events/`.

### Bridge mechanism — confirmed from source 2026-09-17 (was previously undocumented)

`SmartFran.Cloud.Orders.API` polls AWS SQS **directly** (AWS SDK, not Azure Service Bus, not a Function App relay) — confirmed against `cloud/repo/SmartFran.Cloud` (`origin/dev`, freshly pulled this session, `37470e4f`, 2026-09-16). Full path:

1. **Producer side (SmartPedidos):** `concentrador-service`'s `Aws.createQueues(branchId)` (`api/src/provider/aws.js`) creates one **per-branch FIFO SQS queue** (name pattern with `##_` replaced by `branchId`), with an IAM policy granting `SendMessage` to `role/smartfran-task-role` and `ReceiveMessage`/`DeleteMessage`/`ChangeMessageVisibility` to `user/userSQS`. `platforms-service`'s `Aws.pushNewToQueue(newOrder)` (`api/src/platforms/provider/aws.js`) sends each new order to that branch's queue. Confirmed: `platforms-service` also runs its own separate SQS consumer (`pollFromQueue`/`createConsumerSQS`, same file) against a *different*, non-per-branch `ORDER_CONSUMER` queue — that one drives internal `news`/state-machine updates (`SetNews`), not the SmartCloud bridge; don't conflate the two queues.
2. **Consumer side (SmartCloud):** `SmartFran.Cloud.Orders.Application.Services.Aws.MessageProcessor.PollOnceAsync` (`Source/Services/Orders/SmartFran.Cloud.Orders.Application/Services/Aws/MessageProcessor.cs`) polls that same per-branch queue with the AWS SDK directly from the Azure-hosted Orders API, deserializes each message, and dispatches to one of two paths based on `OrderSQSVersionSettings.GetVersion(tenantId)`:
   - `v1` (default when the tenant isn't registered) → `ProcessGridoOrderAsync`, maps to the Grido-specific `OrderSQS` model.
   - anything else registered as non-`v1` → `ProcessNonGridoOrderAsync`, maps to `OrderSQSV2`.
   Successfully processed orders are persisted to Cosmos (`orderRepository`/`orderV2Repository`) and an acknowledgment (`RecievedOrder`/`ViewedOrder`) is published back to SmartPedidos via a second SQS queue (`queueSend`, `IAmazonPublisherService.PublishAsync`) — this ack is presumably what flips a SmartPedidos-side order out of "Pending" (not yet confirmed against SmartPedidos' own state-transition code).
   **Failure handling:** an exception in either processing path (mapping error, Cosmos error other than a duplicate-conflict) falls into a generic `catch (Exception ex)` that sets `ShouldDelete = false` — the SQS message is **not deleted**, so it stays in the queue and is retried after the visibility timeout, indefinitely (the queue's `RedrivePolicy` only routes to the DLQ after `maxReceiveCount: 1000` receives). No ack is ever published back to SmartPedidos in this case.

### Real Graylog evidence, 2026-09-17 — Peru orders observed progressing normally (adds to, doesn't confirm/deny, the reported symptom)

Free-text search (`Peru OR peru OR PERU`, `Service:Orders`, last 24h, corrected after an initial leading-wildcard query failed with a parse error — see `data/graylog_peru_freetext_24h.json`) returned 22 hits, 20 from `SmartFran.Cloud.Orders.API`. All 20 are real orders from a single Grido Peru franchisee (`"client":"TINKU RETAIL PERU S.A.C"`, `"country":"Perú"` — note the accented `ú`, doesn't match any key in `TimeZoneCountries`'s dictionary either way), all under `TenantId: d3186bc6d7b2` — **the already-onboarded GRIDO tenant**, not a distinct/unregistered Peru tenant. This weakens H1 below: `OrderSQSVersionSettings.GetVersion("d3186bc6d7b2")` would resolve however GRIDO's own entry is configured (already the default `v1`/Grido path either way), not an unregistered-tenant fallback.

Traced 4 distinct order IDs through their full log sequence (`EnumStateIdOrder`: 1=PENDING, 9=VIEWED, 3=CONFIRMED, 12=READY):

| Order ID | Sequence observed (24h window) |
|---|---|
| 2285861811 | 1 → 9 (×3, ~35-40s apart) |
| 2285866698 | 1 → 9 → 3 → 3 |
| 2262121001 | 1 → 9 → 3 → 12 |
| 2285897582 | 1 → 9 → 3 → 3 |
| 2286252786 | 1 → 9 → 3 → 3 |

**Observation, not a conclusion:** every one of these 4 sample orders left `PENDING` (1) and progressed through the lifecycle within minutes — none were observed stuck. This is real telemetry for a narrow sample (one Grido Peru franchisee, PedidosYa platform, last 24h) — it does not confirm the reported "stuck in Pending" symptom is resolved, absent, or was ever reproducible in this window; it only adds information about what this specific slice of Peru traffic is actually doing right now. Could still be: a different Peru franchisee/branch, a different platform, an earlier/narrower time window, or an intermittent condition not hit by this sample.

**Separate, unexplained pattern worth a closer look:** the `CONFIRMED` (3) status is logged **twice** for every order that reached it (2285866698, 2285897582, 2286252786 — 35-90s apart each time), via `RequestHandlingMiddleware`-logged HTTP calls into the Orders API (not the SQS consumer path traced earlier — this is a different, separate ingestion point; `OrderController.cs` not yet read to confirm which endpoint). Consistent across all 3 orders that reached this status, in this small sample. Not yet investigated: whether this is two different legitimate callers (e.g. POS + Sales both posting the confirmation) or a genuine duplicate/retry — worth checking `OrderController.cs` and correlating against `RequestId`/source IP if this pattern turns out to matter for the actual reported issue.

**Most useful next step:** ask the reporter for a specific order ID (or branch/franchisee) that is *currently* stuck, so the trace above can be repeated on the actual failing case instead of a random recent sample — a targeted trace will confirm or rule out the hypotheses below far faster than broad free-text search.

### ROOT CAUSE CONFIRMED, 2026-09-17 — live `TimeZoneNotFoundException` in `MessageProcessor.SetTimeZones`, not a silent fallback as first assessed

User pulled a live Azure `AppServiceConsoleLogs` export directly (not via Graylog) showing a real, current (2026-09-17T18:33:04Z) unhandled exception on branch 5454's per-branch SQS queue (`5454PRD_PlatformMessages.fifo`, one of the 35 confirmed Peru branches):

```
Level: Error
MessageTemplate: "Error procesando mensaje en https://sqs.us-east-1.amazonaws.com/382381053403/5454PRD_PlatformMessages.fifo"
Exception: System.TimeZoneNotFoundException: The time zone ID 'Argentina Standard Time' was not found on the local computer.
 ---> System.IO.FileNotFoundException: Could not find file '/usr/share/zoneinfo/America/Buenos_Aires'.
   at MessageProcessor.SetTimeZones(String country, String orderTime) MessageProcessor.cs:line 257
   at MessageProcessor.ApplyTimeZones(Object order, String country) MessageProcessor.cs:line 251
   at MessageProcessor.ProcessGridoOrderAsync(...) MessageProcessor.cs:line 195
   at MessageProcessor.<PollOnceAsync>...
```

**This corrects the earlier H2 assessment above** (which said the `TimeZoneCountries.cs` fallback was silent and didn't throw) — it does throw. The bug: `GetTimeZone`'s fallback branch calls `TimeZoneInfo.FindSystemTimeZoneById("Argentina Standard Time")` — a **Windows-style** timezone ID — while the dictionary's matched-country branches (Argentina/Chile/Uruguay/Paraguay) correctly use IANA IDs (e.g. `America/Argentina/Buenos_Aires`). On this Linux container, the Windows ID resolves (via .NET's ICU compatibility mapping) to the non-canonical alias path `/usr/share/zoneinfo/America/Buenos_Aires` (missing the `Argentina/` subfolder) rather than the real `/usr/share/zoneinfo/America/Argentina/Buenos_Aires` — that alias apparently isn't present in this container's tzdata, so `FindSystemTimeZoneById` throws.

**Full confirmed failure chain:** Peru isn't in the 4-country dictionary → every Peru order hits this fallback → throws, unhandled, inside `ApplyTimeZones`/`SetTimeZones`, called from `ProcessGridoOrderAsync` (all Peru orders route here since they're under the GRIDO tenant, `d3186bc6d7b2`) → propagates to `PollOnceAsync`'s generic `catch (Exception ex)` → `ShouldDelete = false` → SQS message never deleted, retried indefinitely → until the per-branch queue's `MessageRetentionPeriod` (259200s = 3 days, confirmed in `concentrador-service`'s `createQueues`) expires and SQS silently discards it — no DLQ, no ack, nothing. This matches every prior finding: order stuck at `PENDING` in SmartPedidos' Mongo forever (no ack ever received), not in `deadletters` (never reached `maxReceiveCount`), and (for branch 5610's stuck order specifically) an empty live queue (already expired out).

**Open, not resolved — whether this exception predates 2026-09-17 is unconfirmed, not ruled out.** Attempted to check via Graylog (`TimeZoneNotFoundException`, `Service:Orders`, 2026-09-01 to 2026-09-17): 0 results. But a sanity check against the *known, confirmed* occurrence (branch 5454, ~18:33:04Z today, from the user-provided raw export) also returned 0 — both with and without the `Service:Orders` filter, and searching by queue name instead. That means Graylog's search can't find even the one occurrence we're certain happened, so the 0-result history check is inconclusive, not a confirmation of absence. The raw file (`{"records": [...]}` shape) looks like a direct Azure Diagnostic Settings export rather than a Graylog result — possibly this error category never reaches Graylog at all (a distinct ingestion gap), or it lands under a different index this search doesn't cover. Not yet resolved which. Do not state "this is new as of the Sept 7 migration" as confirmed in any output until this is actually checked at the source (Log Analytics/KQL or equivalent) — the correlation with the migration date remains a timeline coincidence across the 12 known-stuck orders, not a confirmed absence-before/presence-after.

**Not yet reconciled — flagging rather than glossing over:** the 4 Peru orders traced earlier this session as "progressing cleanly through VIEWED→CONFIRMED→READY" did so via `RequestHandlingMiddleware`-tagged log lines that this new evidence shows are actually `/api/v1/Queue/Heartbeat` HTTP calls (`QueueServices.Heartbeat`) — a **separate, pull-based bridge path**, distinct from the AWS-SQS-push path (`MessageProcessor.PollOnceAsync`) where this crash lives. Two different mechanisms appear to exist between SmartPedidos and SmartCloud; this bug specifically breaks new-order ingestion via the SQS path, which fits "stuck in Pending" (never gets past initial receipt) far better than it explains orders that already reached later states via the Heartbeat path. The exact relationship/precedence between these two paths (which one is authoritative, whether both are load-bearing in production, or one is legacy) is not yet understood and worth its own investigation before closing this ticket.

### Precise deploy mechanism, confirmed via Azure + user account, 2026-09-17

**Multiple, partially-reconciled timestamps — recording all of them precisely rather than collapsing to one.**

- **Git/CI:** commit `8c19f850a` ("Cambio NET10 en YML PRO", 2026-09-16 17:16 ART) fixed the stale PRO pipeline SDK pin but touched no `Source/**` file, so it deployed nothing by itself. The next `Source/**`-touching push, `faca32f14` ("Stg => PRO v02.45.01", 2026-09-17 14:01:22 ART, containing two small unrelated fixes — "fix nulleable", "fix pedidos atributos opcionales") is what actually fired `Orders.PRO.yml`'s build+deploy, per the GitHub Actions run list (started "Today at 2:01 PM", 1m33s).
- **Azure deployment history** (`az webapp log deployment list`, no `--slot`, i.e. whatever is currently production): entries at **17:02:44Z (14:02:44 ART)** and **19:10:52Z (16:10:52 ART)** today — nothing between 2026-09-16T10:54 UTC and the first of these.
- **Azure Activity Log — the actual, named `SwapWebSite` operation:** `Update web sites config` (slotConfigNames) by `gastona@smartfran.com` at **19:12:53Z (16:12:53 ART)**, immediately followed by **`SwapWebSite`** on `SMARTFRAN-CLOUD-ORDERS-PRO(STG2)`, **Started 19:13:10Z → Succeeded 19:13:12Z (16:13:10-16:13:12 ART)**. This is the one real, confirmed, first-party "swap" event in the 30-day activity log for this resource — not inferred.
- **`stg2` slot's own deployment history:** last entry Sept 16 21:03 UTC — no new deploy into `stg2` today. This means the 16:13 ART swap most likely promoted a build that had been sitting in `stg2` since yesterday evening, not something freshly built today.

**CORRECTED, 2026-09-18 — the "6am" swap is real; my CLI-based Activity Log checks were wrong, not Gastón's report.** User provided the Azure Portal's own Activity Log UI view for Orders-PRO, which shows a full, real swap sequence at **06:08:20 → 06:10:57 ART on 2026-09-17**, by `gastona@smartfran.com`:

| Time (ART) | Operation | Caller |
|---|---|---|
| 05:55:42-47 | `Restart Web App Slot`, slot settings checks | gastona@smartfran.com |
| 06:08:10 | `Get Web App Slots Differences` | gastona@smartfran.com |
| 06:08:20 | `Swap Web App Slots` — Started | gastona@smartfran.com |
| 06:08:23 | `Apply Web App Slot Configuration`, `StartSlotWarmup` — Succeeded | SlotSwapJobProcessor |
| 06:08:23 | `Swap Web App Slots` — Accepted | gastona@smartfran.com |
| 06:10:11 | `EndSlotWarmup` — Succeeded | SlotSwapJobProcessor |
| 06:10:54-57 | `Swap Web App Slots` — Succeeded | SlotSwapJobProcessor / gastona@smartfran.com |

Same exact procedure signature as the 16:12-16:15 swap (diff-check → swap → apply-config → warmup → complete). **Root cause of the CLI miss, confirmed (not just theorized):** a 20-minute window around the swap (09:00-09:20 UTC) and a full 24-hour window both returned **exactly 50 entries** — identical counts across wildly different time ranges is only possible if `az monitor activity-log list` hard-caps at 50 results with no automatic pagination, silently, regardless of how many real events exist in range. The 50 entries even a *narrow* window returns are fleet-wide slot-swap noise (11 services × ~10-15 log lines each for the same 06:08-06:11 ART swap event — `slotsdiffs`, `config/list`, `slotsSwap`, `StartSlotWarmup`/`EndSlotWarmup`, `SwapWebSite`, per app), so the cap is hit almost immediately even scoped tightly. My earlier full-day queries, run hours later in the day with far more accumulated noise in between, truncated long before paging back to 06:08 ART. The Portal UI isn't subject to the same 50-result cap (or paginates transparently). **Lesson, now confirmed rather than assumed: `az monitor activity-log list` needs explicit pagination (or a much narrower, targeted time window plus resource-specific filtering) to be trusted as exhaustive — a clean/empty result on this specific command is not proof of absence without checking the returned count against the cap.**

**Corrected full timeline for Orders-PRO, 2026-09-17:**
1. **06:08-06:11 ART:** first swap — promotes the build sitting in `stg2` since the previous evening (last `stg2` deploy: Sept 16 18:03 ART) into production. **This is the actual moment `net10.0` first went live in production**, matching Gastón's original "6am" report essentially exactly (previously wrongly treated as unconfirmed).
2. **14:02 ART:** direct deploy to production (`v02.45.01`, two small unrelated fixes — "fix nulleable", "fix pedidos atributos opcionales"). Production was already on .NET 10 by this point (since 06:11).
3. **15:33 ART:** live crash captured (`TimeZoneNotFoundException`) — now fully consistent: by this time production had been running `net10.0` for ~9.5 hours.
4. **15:50-15:59 ART:** Peru timezone fix commits merged (`d5d87db50`, `86bab37f9`).
5. **16:09 ART:** fix release pushed (`v02.45.02 fix timezone`, commit `958dfa2`).
6. **16:10 ART:** direct deploy to production — very likely the fix landing live.
7. **16:12-16:15 ART:** second swap, same procedure, by Gastón — purpose relative to the 16:10 direct deploy still not fully explained (possibly a belt-and-suspenders promotion of a `stg2` build that also had the fix), but no longer load-bearing for "when did .NET 10 go live" (already answered by #1).

**Live-confirmed right now:** `az webapp config show` → `linuxFxVersion: DOTNETCORE|10.0`. **User-confirmed:** Peru orders processing normally after the fix (see "Fix confirmed working" section above).

### CORRECTION, 2026-09-17 — deploy date is NOT the same as the commit date

User confirmed: the .NET 10 build was actually **deployed to Orders-PRO today (2026-09-17)**, not on 2026-09-07. The commit date below is when the code was merged, not when it went live in production. This invalidates the timeline correlation drawn earlier — **none of the 12 historical stuck orders (2026-09-04 through 2026-09-14) can be explained by this migration**, since the code causing the confirmed `TimeZoneNotFoundException` wasn't running in production until today. The confirmed root cause (H1/H2 below) explains today's live crash and anything going forward from today's deploy — it does **not** explain the pre-existing 12-order backlog. Their cause is open again, unconfirmed. Do not restate "8 of 12 postdate the migration" as a timeline correlation anywhere — that claim is now known to be wrong.

### "Why now" (for TODAY's crash specifically) — fleet-wide .NET 8→10 migration, commit merged 2026-09-07, deployed to PRO 2026-09-17

User's hypothesis, checked and confirmed: commit `c7fa45721` ("Migracion Framework", GSFC-998, 2026-09-07 10:18:59 -0300) bumped `TargetFramework` from `net8.0` to `net10.0` across essentially every SmartFran.Cloud service. **Exhaustively verified 2026-09-17** (first pass had used a truncated `head -40` view and was a partial inference, not confirmed — corrected on request): the untruncated commit stat shows exactly 50 `.csproj` files changed, covering Orders (all 4), Sales (`API`/`Application`/`Infrastructure`/`Application.Tests`), Business, Catalog, Person, Platform, Pos, Client, the Function Apps (`CodeGenerator.LiteEditionV2`, `Functions.Sales.TicketProcessAsync`, `Functions.ScheduledJobs`), and every shared `Provider.*` library. Genuinely fleet-wide, not an inference from a partial list. `AWSSDK.SQS` was NOT touched in the same commit (still `4.0.0.20`) — ruling out an SQS-client-library regression as a contributing factor.

Orders API deploys to Azure App Service Linux (no custom Dockerfile in this repo or the two local sibling ops repos checked, `sf-devops/jenkins` and `smartfran-documentacion/jenkins`, neither of which cover SmartFran.Cloud at all) — the container is Azure's own managed runtime-stack image, selected by `linuxFxVersion`. Changing `TargetFramework` to `net10.0` implies a different Microsoft-maintained base image than the one used for `net8.0`, which very plausibly ships different/leaner `tzdata`.

**Precision correction, checked 2026-09-17 via web search:** this is not a .NET-10-specific runtime regression. Confirmed via [dotnet/runtime#103864](https://github.com/dotnet/runtime/issues/103864) that the identical failure (`FindSystemTimeZoneById` unable to resolve `America/Buenos_Aires` on Linux) is a known, pre-existing issue that already reproduces on **.NET 8** (8.0.105/Ubuntu) — not something introduced by .NET 10's code. CLDR's own `windowsZones.xml` mapping (confirmed via web search) has long mapped `"Argentina Standard Time"` → the legacy alias `America/Buenos_Aires` (not the canonical `America/Argentina/Buenos_Aires`) — a stable, long-standing mapping, not something that changed between .NET 8 and .NET 10. Whether that alias actually resolves depends entirely on whether the underlying Linux distro's `tzdata` package still ships that "backward"-compatibility symlink — a base-OS/image property, not a .NET-version property. So the precise claim is: the .NET 8→10 migration's accompanying **base container image change** most likely swapped in an OS image whose `tzdata` lacks that legacy alias — not that .NET 10 itself changed how it resolves the ID.

**Timeline check against the 12 genuinely-stuck orders (smartpedidos side) — SUPERSEDED, see correction above.** All 12 (2026-09-04 through 2026-09-14) predate today's actual PRO deploy — none of them are explained by this migration. Their cause remains unconfirmed. Open follow-up: was there a *different* defect active in the pre-deploy (.NET 8) build that produced the same "stuck at PENDING forever" symptom via a different mechanism? Not yet investigated.

**Separate, fleet-wide finding (worth its own ticket, not folded into GITIN-2068):** every PRO GitHub Actions workflow checked (Orders, Admin, Business, Catalog, Platform, Pos, CodeGen, ScheduledJobs, TicketProcessAsync) still pins the pre-migration `DOTNET_CORE_VERSION` (7.0.x or 8.0.x) in `actions/setup-dotnet@v4` — none were touched by the Sept 7 commit, while every DEV/STG/TEST workflow for the same services was correctly bumped to `10.0.x`. This didn't block the actual .NET 10 deploy (confirmed live in PRO via the stack trace above) — GitHub's `ubuntu-latest` runners carry multiple pre-installed SDKs and `dotnet build`/`publish` resolves to whichever matches the project's `TargetFramework` regardless of the explicit pin — but it's a real, fleet-wide CI/CD correctness gap distinct from the Peru bug itself.

**Fix (not yet applied — this is investigation/read-only work):** `TimeZoneCountries.GetTimeZone`'s fallback should use the same IANA ID convention as the rest of the dictionary (`America/Argentina/Buenos_Aires`), not the Windows-style `"Argentina Standard Time"`. Separately, actually adding Peru's real IANA zone (`America/Lima`) to the dictionary would be the more correct fix rather than defaulting non-Argentina/Chile/Uruguay/Paraguay countries to Argentina's timezone at all.

**Also found, separate from GITIN-2068 — flagged immediately, not deferred:** the live log export used to find this also showed POS-terminal branch-login JWTs embedding the same plaintext AWS SQS credential pair already confirmed committed in `concentrador-service`'s `production.js` (`cloud/CLAUDE.md`'s existing note about that file covers the git-committed instance; this is a second, worse exposure — live distribution to branch devices via issued tokens). Not written into this file or anywhere else in the repo. Needs its own security ticket.

### Two candidate gaps found in the same code, tenant/country-config-shaped (weakened by the above, not yet ruled out)

1. **`OrderSQSVersionSettings.Tenants`** (`Common/OrderSQSVersionSettings.cs`) is bound from a live Azure App Configuration key (`OrderSQSVersion`, section under `SmartFran-Cloud-Settings-PRO` — not present in any local `appsettings.json`, confirmed via repo-wide grep). If Peru's `tenantId` isn't registered in this key, `GetVersion` silently defaults to `"v1"` (Grido mapping) rather than failing loudly. **Hypothesis, not confirmed:** if Peru is a real, distinct tenant whose actual order payload shape doesn't match Grido's, being routed through `ProcessGridoOrderAsync` could throw inside the mapping/Cosmos-persist step, landing in the no-delete/retry-forever branch above — which would look exactly like "orders stuck in Pending, SmartCloud not receiving." Needs: (a) confirm whether Peru is onboarded as its own tenant (see `organizations` App Configuration key), (b) confirm whether that tenantId is present in `OrderSQSVersion:Tenants` and what version it maps to, (c) pull real Orders-API exception logs for that tenant from Graylog (see below).
2. **`TimeZoneCountries.cs`** (`Models/Enum/TimeZoneCountries.cs`) hardcodes a country→timezone dictionary with only `Argentina`, `Chile`, `Uruguay`, `Paraguay`. Peru isn't in it — but the fallback (`GetTimeZone`) is silent, not throwing: an unmatched country just gets Argentina's timezone applied to `OrderTime`/`DeliveryTime`. This is a real bug (mis-timestamps Peru orders) but does **not** by itself explain "stuck in Pending" — no exception is thrown here, so it wouldn't block the message from being deleted/acked. Flagging as a separate, likely-unrelated gap, not a leading hypothesis for this ticket.

## Open questions — need answers before proceeding

1. ~~Jira ticket URL~~ — answered, GITIN-2068.
2. Where exactly is "Pending" observed — which system/UI/table (SmartCloud's order/sale status, a POS terminal view, a SmartPedidos-side status)?
3. Is this Peru-only, or the first-noticed instance of a broader issue?
4. Is Peru a newly onboarded country/tenant, or has it been live and working before now? (If newly onboarded, this may be an onboarding-config gap, not a runtime failure.)
5. When did this start — a specific time/date, or "noticed just now"?
6. Any error/alert already seen (SQS DLQ accumulation, CloudWatch alarm, Azure Monitor alert, Zabbix)?
7. Is Peru registered as its own `tenantId` in the live `organizations` App Configuration key, and if so, is it also registered in `OrderSQSVersion:Tenants` — and as which version? (Needed to confirm/rule out the H1 hypothesis above.)

## User's final synthesis, 2026-09-17

"My thoughts: ~14:00 was [when] dotnetcore10 [was] deployed." — the user's own conclusion, after all the deploy/swap evidence above, is that the **14:02:44 ART direct production deploy** is the real moment .NET 10 went live in Orders-PRO, not the 16:13 swap. Recorded as the user's stated view, distinct from the evidence itself (which shows both events as real and doesn't fully resolve which one was the operative moment — see the deploy-mechanism section above for the underlying data this synthesis is drawn from).

## Fix confirmed working, 2026-09-17 (post-16:10 deploy / post-16:13 swap)

User confirmed directly: after the timezone-fix deploy (commit `958dfa2`, "v02.45.02 fix timezone", 16:09-16:11 ART), Peru orders are processing normally. This resolves the earlier open question about whether the 16:13 swap had overwritten the fix — it hadn't, or whatever the net effect of deploy+swap was, the fix is live. Not independently re-verified via a fresh no-cutoff query at the time of this note — if a formal close-out number is needed later, re-run `mongo_peru_all_blocked_orders.js` and confirm the count hasn't grown past 12 (the pre-existing historical backlog, still unexplained and still open separately).

## Not yet done

Bridge mechanism and two candidate code-level gaps now identified from source (see above) — not yet confirmed against live App Configuration or real Graylog error logs for the Orders API. Next diagnostic step: pull the live `organizations` and `OrderSQSVersion` App Configuration values, and query Graylog (`Service:Orders`, `AppLevel:Error`) for exceptions in `MessageProcessor` around the reported window, once a time window is known (open question 5).
