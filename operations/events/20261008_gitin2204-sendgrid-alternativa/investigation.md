# GITIN-2204 — [OPE] Alternativa a SendGrid

- Jira: https://smartit-ar.atlassian.net/browse/GITIN-2204
- Opened (this folder): 2026-10-08.
- Status: in progress (2026-10-08). Done: volume, current integration, price orientation (SES, Azure Communication Services Email, Postmark, Mailgun, Brevo), ACS limits, delivery format and storage options, fiscal QR length. No provider chosen and no decision yet; waiting for answers on the open items.
- Ask (user, 2026-10-08): find an alternative to SendGrid for emailing bills (comprobantes) to customers. Volume given by the user: 72,360,308 sales from 2026-01-01 to 2026-10-07, 11,799,070 of them in January alone, and each sale will represent one email. The source of the sales counts was not checked here.

## Volume

- 280 days in the period: average 258,430 sales/day (about 7.86M per 30 days).
- January: 380,615/day, about 4.4 emails/second on average (more at meal-time peaks; the peak rate was not measured). The other months (Feb 1 to Oct 7, 249 days): about 243,200/day. January is therefore the peak month, about 1.5x the average of the rest.
- Planning figure: 11.8M emails per month sustained, with headroom for growth. Assumes every sale has a customer email address; if only a share of sales do, volumes and cost fall proportionally (not checked).

## Provisional direction (not a decision)

- Hosting in Azure does not force Azure Communication Services Email (SendGrid is not an Azure service either; the code only depends on `IEmailProvider`). ACS Email gives managed-identity authentication (no stored key) and Azure billing; Amazon SES is about 2.5x cheaper at list price (about $1,180 vs $2,950 per month at 11.8M; about $790 vs $1,960 at the 7.9M average month; estimates from unverified list prices) but needs an AWS credential or cross-cloud federation and more to operate (bounces, suppression, reputation). Brevo has no public price at this volume (Enterprise quote only) and is marketing-oriented, so it is not shortlisted unless a quote beats the others.
- Delivery: short HTML email plus a button to a signed, expiring URL (option B), with a queue and retry in front of the provider.
- Storage: the bill already exists as data in Cosmos DB (`Sales` container, `Sale.Bills`); the lower-cost route is to render from that data plus a template version id with a time-limited cache, instead of storing PDFs. Decision depends on the open items below.

## What exists today (SmartFran.Cloud, `main` @ d969856fa in `cloud/repo/SmartFran.Cloud`)

- Email goes through an abstraction: `IEmailProvider.SendAsync(EmailMessage)` in `Source/Common/Providers/SmartFran.Cloud.Provider.Contracts/Notifications/Emails/IEmailProvider.cs`. `EmailMessage` has only `To`, `Subject`, `HtmlBody` (no attachments, no custom headers or message ids).
- One implementation: `SendGridEmailService` (`Source/Common/Providers/SmartFran.Cloud.Provider.Email.SendGrid/`), registered in `Sales.API/Program.cs` (L278, settings section `SendGrid`) and in `Sales.Infrastructure/Extensions/DependencyInjection.cs` (L20). A swap is a new `IEmailProvider` implementation plus a DI line and settings.
- The only consumer of `IEmailProvider` found in `Sales` is `ShiftServices` (template `PrintShiftClosureTemplate_Grido.cshtml`, shift-closure email). No sender of per-sale bills was found on `main`, so per-sale email is a new flow or lives in another repo or system; the user should confirm which. The Catalog service has a separate class named `AzureEmailService` that actually calls SendGrid directly (name is misleading). Platform (SmartPedidos) also uses SendGrid (`SENDGRID_API_KEY`, `sgMail`, GITIN-1715 scope).
- Gaps that matter at this volume: `SendGridEmailService` logs failures and swallows them (no retry, no queue, no dead-letter), so a failed send is lost; no bounce/complaint handling in code; no attachment support (PDF bills would need it, or a link).

## Orientation on cost (list prices from web search, not verified on vendor pages; check before budgeting)

| Option | Price signal | At 11.8M/month | Notes |
|---|---|---|---|
| Amazon SES | $0.10 per 1,000; attachments $0.12/GB; dedicated IPs about $24.95/month each (managed dedicated IP tiers conflict between sources) | about $1,180/month (period total about $7,240) | Cheapest by far; you run bounce/complaint handling (SNS), suppression and reputation yourself; production access and quota increases needed; AWS account `382381053403` already exists for SmartPedidos |
| Azure Communication Services Email | $0.00025 per email + $0.00012 per MB (Microsoft docs example, marked illustrative) | about $2,950/month | Native to Azure where SmartCloud runs; cost about 2.5x SES; send limits need a quota request (see "Azure Communication Services limits" below) |
| Postmark | older tier table: $1,200 for 5M + $0.25 per 1,000 above (a 2026 plan restructure is also reported) | about $2,900/month by that table | High deliverability reputation; above 1.5M needs sales contact |
| Mailgun | Flex $0.80 per 1,000 listed by a comparison site; Enterprise custom | about $9,400/month at that rate | Enterprise quote would be lower; not verified |
| Brevo | Public tiers stop at Professional, $499/month from 150,000 emails; Enterprise is "contact sales". A third-party site lists overage of $1.00 per 1,000 (Business tier) and $1.50 (Starter); not confirmed for Professional | no public price; if overage at $1.00 per 1,000 applied, about $11,800/month (a rough upper bound, not a quote) | Dedicated IP: sources disagree (add-on on Professional and Enterprise, included in Enterprise, about $251/year on one page); Brevo recommends one above 100,000 emails/month. Marketing-oriented platform; transactional SMTP/API relay is available on all plans. Brevo's own pricing page did not load in the search tool |
| SendGrid (current) | Pro listed at $89.95/month for up to 2.5M; nothing found above | quote needed | Current plan and invoice not known; ask for them |

- Attachments: at an assumed 100 KB per PDF, 11.8M emails is about 1.2 TB per month, about $142/month more on SES. The real bill size was not checked.
- None of these figures include engineering time to add retry/queue, bounce handling and PDF attachment support.

## Azure Communication Services limits (web search, 2026-10-08; Microsoft Q&A posts, partly from 2024, official limits page not opened)

- Microsoft documents high volume up to 1-2 million messages per hour, depending on traffic, failure rate and domain reputation; the default quota is much lower (a 2024 moderator answer quoted 100 messages per hour; confirm the current default on the "Service limits for Azure Communication Services" page).
- A higher quota is requested through an Azure support ticket (quota type "Azure Communication Services Email: Sending Limits"); reported to be free, to take up to about 72 hours, and to require a failure rate below 1%.
- Maximum message size defaults to 10 MB; increases to about 30 MB are requested through support.
- Not checked: dedicated IP availability, bounce/complaint handling through Event Grid, custom-domain verification steps.

## Fiscal QR on the POS bill (checked 2026-10-08, `cloud/repo/SmartFran.Cloud` `main` @ d969856fa, working tree)

- Argentina: `WsFeArV1Services.QrAsync` (Sales.Application) serializes a `QrCmd` to JSON, base64-encodes it, appends it to the configured URL (`WsFeAr:UrlQr` + `?p=`), and renders that URL as a QR with QRCoder (error correction level Q, 20 px per module) returned as a base64 PNG image string. That image string is what the POS keeps as `QRString64` and prints (`SaleCancelAndBill`, `Sale.razor.cs`, `OrderServiceV2`, `SalePrintService`), and what `WsaaSetQrCache` stores in the Platform cache for reprints. Peru and Uruguay have their own builders (`WsFePeService`, `WsFeUyService`); not measured.
- Payload length (computed from the field list, with illustrative values; the configured `UrlQr` value was not read, so a 30-character URL base was assumed):
  - The 13 fields in the ARCA QR specification: JSON about 208 characters, base64 280, URL about 313 characters, which is QR version 16 (81 modules) and a PNG of about 1780 x 1780 px.
  - As the code is written, `JsonSerializer.Serialize(request)` also writes every other `QrCmd` property with default options (no null-ignoring found): `establishment`, `validationEndPoint` and the nine `FeUy*` fields, as nulls and a `FeUyTransaction` of 0. That gives JSON of about 431 characters, base64 576, URL about 609 characters, QR version 23 (109 modules), PNG about 2340 x 2340 px. Whether the fiscal validator tolerates the extra fields, and whether the printed QR scans reliably at that density on the ticket printers, was not tested. The actual stored value was not inspected.
- Image size: a 1700 x 1700 sample in `Pages/Sandbox/TestPrint.razor` is 27,632 base64 characters (20,722 PNG bytes); scaling by pixel count, about 23 KB (spec payload) to about 39 KB (current code) of PNG per QR, about 31 to 52 KB as base64 text (estimate).
- For email: embedding that string as a `data:` image is unsafe (several clients, including Gmail, do not show base64 `data:` images) and heavy (about 330 to 610 GB per month of image text for 11.8M emails at the estimated sizes); regenerate a small QR (about 300 px) from the URL payload at render time, or serve it from the signed bill page. The payload URL itself is under 700 characters.

## Where bills are stored today (checked 2026-10-08, `cloud/repo/SmartFran.Cloud` `main` @ d969856fa)

- Not MongoDB: the Cloud repo has no MongoDB reference (MongoDB Atlas belongs to SmartPedidos). Sales persists through Azure Cosmos DB (SDK repositories over `ICosmosConnection`); the `Sales` container holds `Sale` documents, and each `Sale` has a `Bills` list of `SaleBill` (`Sale.cs` L31, `SaleRepository` uses container "Sales"). Whether it is the NoSQL API in every environment was not checked beyond the SDK usage.
- `SaleBill` stores the data of the fiscal document: type, point of sale, number, net, exempt, IVA and IVA rates, discounts/surcharges, total, CAE and its expiration, date/time (UTC), establishment, validation endpoint, provider state, the Uruguay block (`FeUy`) and a retry counter. It has no field for the QR or for a rendered document.
- The QR image string is not part of the stored bill: it comes from the CAE response and is kept in the Platform cache (`WsaaSetQrCache`, for reprints). The fields the QR needs (point of sale, type, number, total, CAE, date) are stored, so the QR can be rebuilt from the stored bill plus the company tax id; the company tax id and customer document were not traced.
- The printed ticket is rendered from data by templates (`Ticket.razor`, `TicketFEPY.razor`, `TicketFEUY.razor` in the POS and print functions); no stored PDF of the bill was found. So today the bill exists as data, which fits the "store data plus template version and render on demand" option; a stored PDF would be new storage, not a copy of something that already exists.
- Not checked: other persisted copies (print queue, Blob), how long Sales documents are retained, and Cosmos container size per tenant.

## Operational points for any provider

- Cannot start cold: about 380k emails/day needs a dedicated-IP or domain warm-up plan (ramp over weeks), while SendGrid keeps running during the switch.
- DNS per sending domain: SPF, DKIM, DMARC; the sending domain/subdomain for bills to be decided.
- Bounces, complaints and unsubscribes must feed a suppression list; Argentina's data-protection rules for customer email addresses were not reviewed.
- Rate and burst: about 4.4/s average, peaks higher; each provider's default quotas need checking and raising before cutover.
- Delivery should go through a queue with retry and dead-letter (the platform already uses Azure Service Bus) rather than the current fire-and-forget call.

## Delivery format and storage (discussed 2026-10-08; no decision)

- An email button is only a link: clients strip JavaScript, so nothing can be "rendered" inside the message, and a `.tex` attachment cannot be compiled by the customer. Options: (A) attach a server-rendered PDF; (B) short HTML email with a button to a signed, expiring URL that serves the stored PDF/HTML; (C) both. Recommended direction: B.
- Whether the bill must be stored depends on the option: A needs no storage for delivery (but a resend or a customer claim then needs the bill regenerated); B needs the rendered file in storage for the life of the link. In both cases the bill must be reproducible exactly later, so either the PDF is stored or the data snapshot and template version used to render it are.
- Sizing (assumes about 100 KB per bill, not measured): 11.8M bills in the peak month is about 1.2 TB per month; the 72.4M in 280 days is about 7.2 TB; about 9.5 TB for a year at the 7.9M monthly average. Price per GB (hot/cool/archive tiers), retention and lifecycle rules were not checked.
- Storing LaTeX sources per bill instead of PDFs (asked 2026-10-08): about 5 KB per `.tex` (assumed, not measured) would be about 59 GB for the peak month versus about 1.2 TB for 100 KB PDFs, but it moves the cost to compute and risk: each button click compiles on demand (assumed about 1 s CPU per compile, so roughly 5 vCPU at the 4.4/s average and more in spikes right after a mass send), the TeX distribution, packages and fonts must be pinned so a bill renders identically years later, and customer-supplied text must be escaped and compiled with shell escape disabled in a sandbox. Storing the structured sale data (already in the sales store) plus a template version id, and rendering lazily with a time-limited PDF cache, gives similar space savings without one generated source file per bill. Fiscal exactness (the issued document) still has to be confirmed; the official fiscal PDF, if it exists, should not be re-rendered.
- Scope this adds if B is chosen: a renderer (sandboxed, own templates only), blob storage with lifecycle rules, a signed-URL endpoint on an owned domain (unguessable token, expiry, rate limiting), and handling of customer personal data inside the bills.
- Open: legal retention period for fiscal documents and who owns the official PDF (to confirm with accounting/legal); whether the official fiscal PDF already exists in the current flow.

## Open items

- Confirm what system sends the per-sale bills (code not found in `Sales` on `main`), whether PDFs are attached, and the average size.
- Whether the official fiscal PDF already exists in the current flow and where it is stored; legal retention period for fiscal documents (accounting/legal).
- Current SendGrid plan, monthly cost and sender domains (invoice and account usage page).
- Preference: lowest cost (SES) or fewer moving parts (ACS Email or a managed vendor with a quote).
- Written quotes at 12M emails per month, transactional (Microsoft for ACS Email, plus any vendor that stays shortlisted).
- Official pricing and limits pages for SES and ACS Email could not be opened by the search tool; confirm both.
- Fiscal QR: read the configured `WsFeAr:UrlQr` value (not a secret) and one real printed QR payload URL to confirm which payload row applies (13 fields vs the current code's 24 properties); test whether the extra null fields are accepted by the fiscal validator and scan reliably on the ticket printers.
