# Investigation — 20261013_gitin2201-evaluar-proveedor-correos

**Status:** evaluation ticket written (`ops.md`); no provider chosen; answers from Development (`email_dev.md`) and quotes are pending. Nothing has been run against any system: the work is local code reading (`cloud/repo/SmartFran.Cloud` `main` @ d969856fa, 2026-09-30) and web search. All prices are list prices from web search or third-party blogs, not verified on vendor or cloud pages.

Jira: GITIN-2201 "[CLOUD] Evaluar Proveedor de Envio de Correos" (https://smartit-ar.atlassian.net/browse/GITIN-2201). The ticket body was not provided; the scope is read from the title and from earlier research under `operations/events/20261008_gitin2204-sendgrid-alternativa/` (GITIN-2204 "[OPE] Alternativa a SendGrid", same subject: replace SendGrid for emailing bills to customers). Whether 2201 is a duplicate, parent or sibling of 2204 is not known. `data/` is empty (no command was run); the earlier detailed notes (fiscal QR length, ACS limits, delivery format) are in the 2204 investigation.

## Facts

**Flow and volume**
- User: per-sale bills are only printed on the POS printer today; no email is sent per sale. A per-sale email would be a new flow in Cloud (consistent with no sender found on `main`). The only email consumer found in Sales is the shift-closure email.
- User-given volume: 72,360,308 sales 2026-01-01..10-07; 11,799,070 in January; source not checked. Derived: 258,430 sales/day average over 280 days (about 7.86M per 30 days); January 380,615/day (about 4.4 per second on average). Planning figure: 11.8M bills per month, assuming one email per sale.
- **User (2026-10-13): the customer's consent is needed to send a bill by email.** The legal basis, how consent would be captured and recorded (POS, order channel, customer profile) and whether any consent exists today were not reviewed. Consequence: 11.8M per month is an upper bound; the real volume is the share of sales with a customer email and consent (unknown, Dev question 5). Prices that scale with volume (SES, ACS, Postmark, Mailgun, Brevo) drop in proportion. Opt-out/unsubscribe handling and the consent record also need a place to live.

**Code (Cloud, `main`)**
- `IEmailProvider.SendAsync(EmailMessage)`; one implementation `SendGridEmailService`; `EmailMessage` has To, Subject, HtmlBody (no attachments, no custom headers). Failures are logged and swallowed: no retry, queue or dead-letter; no bounce/complaint handling in code.
- Bills exist as data (`Sale.Bills` in the Cosmos DB `Sales` container); the printed ticket is rendered from templates; no stored PDF found; the QR image is not stored in the bill.

**Size**
- Cloud bill size not measured. User assumption: 50 KB and 100 KB. User reference: SmartFran onprem sends PDFs of 17 to 50 KB via Sendinblue (renamed Brevo; same account not confirmed); unknown whether the Cloud bill is the same format.
- Volume of data at 11.8M bills: 17 KB = 200 GB/month; 50 KB = 590 GB; 100 KB = 1,180 GB. 12 months at 7.86M/month (94.3M objects): 1.6 TB / 4.7 TB / 9.4 TB. Period to 10-07 (72.4M): 3.6 TB (50 KB), 7.2 TB (100 KB). 1 GB = 1,000,000 KB.

**Providers (list price at 11.8M per month; Cost excludes engineering)**
- SES about $1,180 ($0.10 per 1,000; attachments $0.12/GB: $71 at 50 KB, $142 at 100 KB); dedicated IP about $24.95/month each; bounces, complaints, suppression and reputation are self-managed.
- Azure Communication Services Email about $2,950 ($0.00025 per email; attachments $0.00012/MB: $71 / $142); quota requested via support; native to Azure, managed identity.
- Postmark about $2,900 (older plan table; a 2026 restructuring is reported); Mailgun about $9,400 at the listed Flex rate (Enterprise lower, unverified); Brevo no public price at this volume (about $11,800 only as a rough upper bound if $1.00 per 1,000 overage applied); SendGrid current plan and cost unknown (Pro listed $89.95/month up to 2.5M).
- Brevo is already used by SmartFran onprem (plan, cost, volume, reputation unknown).

**Storage price signals** (third-party blogs, sources disagree; high end used): Azure Blob East US LRS Hot $0.018-0.0208, Cool $0.010-0.0152, Cold $0.0036-0.0045, Archive about $0.00099 per GB-month; S3 us-east-1 Standard $0.023, Standard-IA $0.0125, Glacier Instant Retrieval $0.004. Cool/Cold/IA tiers bill a minimum of 128 KiB per object (Azure's small-object minimum comes from one unverified source), so 50 KB and 100 KB objects cost the same as 128 KiB there. 12 months of bills per month: 50 KB: Hot $98, S3 Standard $108; 100 KB: Hot $196, S3 Standard $217; 17 KB: Hot about $33, S3 Standard about $37. Requests (about 94M objects), egress, retrieval, redundancy and early deletion are not included.

**Domain and reputation**
- User: sending domain `smartfran.com`, DNS access available; current SPF/DKIM/DMARC records not read. User recommendation (pasted): a new domain dedicated to sending, e.g. `factura@comprobantes.smartfran.com`, to keep blacklist problems apart from work email. A subdomain still sits under the main domain, so some reputation risk could reach it (to confirm with the chosen provider); a separate registered domain isolates fully but has no history or brand recognition.
- A new IP and domain need a gradual warm-up (several weeks; no fixed schedule in the ticket) and a plan with SendGrid kept running during the transition. Reputation is measured from the sending provider's bounce/complaint data, Google Postmaster Tools, Microsoft SNDS/JMRP, DMARC aggregate reports, blocklist checks and optional inbox-placement tests; reference levels (hard bounces under about 2%, complaints under 0.1%, never above 0.3%) and SES review/pause thresholds come from general knowledge and are marked as to confirm.

**Delivery and generation options** (compared in `ops.md`, no decision): attach a PDF (A), short email with a signed expiring link (B, provisional direction), or both (C); generate/store as stored PDF, stored LaTeX source compiled on open, or bill data (already in Cosmos) plus a template version rendered on demand (provisional direction). The fiscal QR URL is about 313 characters with the 13 specification fields and about 609 with the current code (extra null fields); not tested against the fiscal validator or printers. A base64 QR image in the email is unsafe (Gmail does not show it); regenerate a small QR from the URL.

## Open items

- Development (email in `email_dev.md`, open questions, no hypotheses): when the email would be sent and who generates the bill; real bill size and whether it is the onprem format; whether a copy of the sent bill must be stored and what; retention time (with Accounting/Legal); share of sales with a customer email.
- Consent: legal basis and how to capture and record the customer's consent; share of customers with consent (Legal and Development).
- Current SendGrid plan, cost and sender domains; onprem Sendinblue/Brevo plan, cost, volume, bounce/complaint rates (baseline for reputation).
- Written quotes at about 12M per month (mail providers) and official price/limit pages for SES, ACS Email, Azure Blob and S3; the figures used are third-party.
- Legal retention period for fiscal documents; whether the official fiscal PDF already exists in the flow.
- Current SPF/DKIM/DMARC records of `smartfran.com`; the domain choice (subdomain vs separate domain).
- Fiscal QR payload check (validator and printers).

## Decisions made by the user so far

- Recommendation for a dedicated sending domain (example `comprobantes.smartfran.com`).
- Recommendation (2026-10-13): take the email-sending responsibility away from the POS; the sale flow publishes the bill data to a queue and another process, for example an Azure Function, consumes it, generates the bill or its link and sends it through the chosen provider. In the ticket as a recommendation: retries with backoff, dead-letter queue, idempotency per bill id, consume rate matched to the provider quota and the warm-up ramp, data read at processing time instead of copied into the message; Service Bus and Functions costs at this volume are not calculated (action 13); when the message is published and what it carries are Dev's to answer (question 1); which existing Function App, if any, would host it was not evaluated.
- Storage, format and provider are not decided.

## LaTeX bill demo (2026-10-19, local, nothing sent)

- Folder `outputs/factura-demo/`: `plantilla-factura.tex` (narrow one-column ticket that follows a printed example ticket, Factura A; it holds no data), the folder `datos/` (one JSON file per section: meta, emisor, comprobante, cliente, detalle, descuentos_recargos, impuestos, pagos, totales, autorizacion, pie), `render.py` (writes `datos.tex` from the data and compiles with `latexmk` when given `--compile`) and `build/factura-demo.pdf` with its PNG preview.
- The data is invented (all-zero CUITs, fake CAE, `example.com` email); nothing was copied from the example ticket. The fields of comprobante, impuestos, descuentos, pagos, detalle and cliente follow `SaleBill`, `SaleDetail` and `SaleClient` of Cloud (`main`, 2026-09-30); the issuer, cash register and authorization fields are examples (where they would come from in production was not checked).
- It corresponds to the option "bill data (already in Cosmos) plus a template version, rendered on demand". The fiscal QR of the demo has 13 fields and a 313-character URL, as in this ticket's estimate; the encoding was not validated against the fiscal validator. The one-page PDF is about 110 KB, mostly embedded fonts: the same order as the 50 to 100 KB assumed, not compared with the real Cloud bill or with the 17 to 50 KB PDFs of the on-premise system.
- The script checks that the amounts add up (items minus discounts equal the total, net plus IVA equals the total, payments equal the total).

## User clarification about the printed ticket (2026-10-19)

- User-stated: the example ticket is printed by an Argentine fiscal printer. So the layout of the ticket (narrow column, fixed-width font, order of the sections) is defined by the printer and not by SmartFran; the LaTeX demo imitates it for the email and is not the document the printer issues.
- To confirm (not verified): the PDF of the email would be a representation of the bill generated from the sale data (`SaleBill`: number, CAE, expiry, amounts, QR data). Whether it replaces or complements the printed fiscal ticket, and what the regulation requires for a bill sent by email, is a question for Accounting and Legal, already listed above (whether the official fiscal PDF exists in the flow).
- Still unknown: what the fiscal printer returns to Cloud (only number, CAE and date, or also the text of the ticket), and whether the width and content of the printed ticket vary by printer model.

## PDF width of the demo (2026-10-19)

- User decisions in sequence: first "10 cm", then "12mm", read as 12 cm because 12 mm cannot hold any text (an assumption, not confirmed by the user). The demo ended at 12 cm wide (340.157 pt), about 21 cm tall, one page, 110,711 bytes; the content area is 114 mm.
- The ticket printed by the fiscal printer is narrower (58 or 80 mm paper, width not confirmed; the example photo holds about 33 to 37 characters per line). To imitate the printed ticket, the real paper width or the printer model has to be fixed.

## LaTeX bill demo: closed (2026-10-19)

- Closed by the user ("bill latex closed"). Still unconfirmed: the 12 cm width (the user wrote "12mm", read as cm), the real paper width of the fiscal printer, what the printer returns to Cloud, and the QR validation against the fiscal validator. The files stay in `outputs/factura-demo/`.
