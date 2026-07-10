# Actor Notes

Extended context for known fraud actors. Keyed by DNI.

---

**DNI 46845173 — Simon Brizuela (hub)**
Hub in circular scheme with Dimon Briz (DNI 123456) and feeder DNI 46845174. DNIs 46845173/46845174 consecutive, same name — same person, duplicate accounts. Email: `simonnnn123@yopmail.com` — disposable domain. Absent from CustomerMailing. Balance at close: 9,565 pts intact.

**DNI 46845174 — Simon Brizuela (feeder)**
Sequential DNI to 46845173, same name — deliberate duplicate. Email: `simon12366@yopmail.com` — disposable. Received 10,000 pts from Dimon Briz on 2026-05-25 via WEB (staging). Injected 8,000 pts to hub on 2026-06-04 via APP. WEB→APP channel switch between sessions = obfuscation. Balance at close: 3,300 pts.

**DNI 123456 — Dimon Briz (relay)**
Fake account. "Dimon" = anagram of "Simon" (Brizuela). Invalid DNI (6 digits, sequential). Email: `keyavi4022@hilostar.com` — disposable. Absent from CustomerMailing. CustomerId hardcoded as default customer at POS in multiple franchises: 730+ sales at 21 branches across 7 franchise groups between 2026-05-16 and 2026-06-03. Simultaneous activity in multiple provinces on the same day (physical impossibility confirmed). Dominant franchise operator: Cura, Juan Cruz (ORAN ×4, 253 sales) — suspected insider: `luiscura29@yahoo.com.ar` (luis ignacio cura, 5 staff roles under same email). Prior infraction: -10,000 pts on 2026-05-25 → DNI 46845174. Probe 490 pts on 2026-05-30. Balance at close: 0 pts.

**DNI 43541207 — Homer Spo (hub_primary)**
Credential stuffing hub and Batman network feeder. CustomerId: 8DD60691-D9BE-C158-FF02-08DEBAC4AD81. Created 2026-05-26 WEB. Sequential DNI in block 43541200–43541209 (same Batman operator). Received 60,001 pts from 12 compromised accounts in 3 sessions (2026-05-25, 2026-05-27, 2026-06-02). 2 confirmed sends totaling 38,000 pts: 8,000 → El Batman (2026-05-28 23:11 ARG, APP) + 30,000 → Lucas Riquelme (2026-06-03 01:52 ARG, WEB). Limit violation: 30,000 pts in one send vs. customer limit 8,000. Active balance: 22,001 pts. Zero organic activity.

**DNI 46374837 — Nahir Niz (chronic_recipient)**
Chronic recipient of Grido employee transfers. ~132,000 pts received over 14 months since March 2025. Account created 2022-12-25 — legitimate in origin. Confirmed beneficiary of Carlos Andrés Roldan (Permanent Collaborator). 4 transfers in 93 seconds on 2026-06-03 — automated cadence. Balance at close 2026-06-03: 40,005 pts intact.

**DNI 44238411 — Lucas Riquelme (pass_through)**
Confirmed pass-through in two investigations. Created 2026-05-15 APP — coordinated batch with Dimon Briz (2026-05-16 WEB). Confirmed: 68,000 pts received (4 transfers), 29,000 pts transferred out (6 sends), zero cashout, 39,000 pts active — high-priority recovery target. Received 30,000 pts from Homer Spo on 2026-06-03 (01:52 ARG). Possible family/social link to Jenifer Riquelme (40960742) — same surname, same Chos Malal cashout cluster.

**DNI 24545466 — Carlos Daniel Sancho (recurring_recipient)**
Created 2026-06-02 APP — 2 days before the 2026-06-04 investigation. Recipient in two consecutive investigations. Received from Julia Roquelina Cuccaro (Temporary Collaborator) on 2026-06-03 (TransfId 286300, 8,000 pts) and 2026-06-04 (08:03 ARG, 8,000 pts). Same employee → same external recipient on consecutive days. Pattern of systematic employee benefit diversion.

---

**DNI 43541208 — El Batman (hub_primary) — Batman Network**
Primary hub active 18 months (Nov 2024–Jun 2026). Email `locosdeperros3090@gmail.com` — locosdeperros30XX family (three accounts, same operator). Sequential DNI: +1 from Elbarto Malo (43541209), +8 from Bat Man (43541200). No POS activity. Distributes to Castro Ortega, Pereyra, Guzman, Choque. Also received 8,000 pts from Homer Spo on 2026-05-28 23:11 ARG. Confirmed: 297,385 pts received (59 transfers), 256,000 pts transferred out (22 sends), 41,385 pts active. Account active without suspension.

**DNI 43541200 — Bat Man (hub_alias) — Batman Network**
Alias of same operator as El Batman. Email `locosdeperros3030@gmail.com`. DNI -8 from El Batman. No POS activity. Confirmed: 57,149 pts received (13 transfers), 20,000 pts transferred out (1 send), 37,149 pts active. Registered in same batch as 43541207–43541209.

**DNI 43541209 — Elbarto Malo (hub_parallel) — Batman Network**
Parallel hub. Fictional name (Bart Simpson). Email `josecastroo12343@gmail.com` — double 'o' in "castroo" references Lucas Castro Ortega. DNI +1 from El Batman. Pre-registration anomaly: received 30,000 pts from Eustacio Castro before NewCustomer event (Mar 7 2026, 18 min gap). Confirmed: 234,353 pts received (30 transfers), 129,999 pts transferred out (5 sends), 109,354 pts active — largest hub balance.

**DNI 92623449 — Eustacio C. Castro (relay_hub) — Batman Network**
Impossible DNI (92M — falls in 91–92M gap between valid AR foreign resident series 90M and 93M). Email `ortegacastro1234@gmail.com` combines surnames of Lucas Castro Ortega — same operator. Relay between Elbarto Malo, receptors, and toward Huanca. Reversed -62,475 pts by GSLCEBALLOS on 2024-12-20 (first detection) without account suspension; network continued 18 additional months. Confirmed: 127,214 pts received (22 transfers), 32,240 pts transferred out (3 sends), 62,475 reversed administratively, 32,499 pts active.

**DNI 13883289 — Juana De Torres (account_takeover?) — Batman Network**
Email `locosdeperros3080@gmail.com` — third account in the locosdeperros30XX family. Email_Flag = OK (present in CustomerMailing) — ONLY actor in the entire scheme with OK flag. Zero transfers received. 72,300 pts cashed out in 13 canjes entirely from own POS-accumulated balance. Diagnosis: probable account takeover — operator accessed a legitimate customer account and drained their accumulated points. DNI 13883289 — old range (1960s–70s generation), likely the real account holder. Active balance: 3,690 pts (belongs to real owner). Requires access log investigation and notification to account holder.

**DNI 45253012 — Lucas Castro Ortega (relay_cashout) — Batman Network**
Central cashout engine of the scheme — largest single actor. Email combines surnames of Juana De Torres (Torres) and Eustacio Castro (Castro) — same operator. Created in coordinated batch; activity started 2026-05-16 alongside Dimon Briz. Confirmed: 437,380 pts received (71 transfers), 230,000 pts cashed out (53 canjes) — largest non-recoverable total in the scheme, 152,000 pts transferred out (19 sends → Huanca and others), 55,730 pts active.

**DNI 47813765 — Valentina Ayelen Choque (cashout_mule) — Batman Network**
Largest confirmed canje volume among mules: 61,300 pts. Active since Sep 2025. Confirmed: 102,740 pts received (10 transfers) including 22,500 pts on Feb 10 2026 (2.8× daily limit). 61,300 pts cashed out (26 canjes), 42,140 pts active. Cashout at Branch 3385 SAN PEDRO JUJUY (Angelelli). Oct 26 2025 feeders (3 × 8K in 110 sec) pending identification.

**DNI 48016024 — Angel Pereyra (cashout_mule) — Batman Network**
Confirmed: 94,000 pts received (9 transfers), 45,800 pts cashed out (18 canjes), 48,500 pts active. Cashout at Branch 3385 SAN PEDRO JUJUY (Angelelli) — same geographic cluster as Choque. Dec 7 2025 feeders (2 × 8K) and Mar 30 2026 feeders (3 × 8K in 27 sec) pending identification. Note: surname "Pereyra" also belongs to franchise owner of Branch 3822 (Chaco) — common Argentine surname, no confirmed link.

**DNI 46403467 — Agustina Guzman (relay_mule) — Batman Network**
Real customer recruited as mule — legitimate POS activity since May 2024. Started as mule: May 14 2026 (received 8,000 from El Batman + 30,000 from Elbarto Malo with 2 min gap). Confirmed: 45,000 pts received (3 transfers), 17,500 pts cashed out (6 canjes), 16,000 pts transferred out (2 sends → Sandoval), 17,050 pts active. Cashout at Branch 5182 CHOS MALAL (Funes). Possibly coerced — recommend notification, not sanction.

**DNI 45978514 — Agustina Sandoval Sobarzo (cashout_mule) — Batman Network**
Recipient from Agustina Guzman. Immediate cashout: 101 sec between PointsByTransferReceived and DiscountPointsByExchange (Jun 10 2026). Confirmed: 30,000 pts received (6 transfers), 22,700 pts cashed out (8 canjes), 5,000 pts transferred out (1 send → destination pending), 2,850 pts active. Cashout at Branch 5182 CHOS MALAL (Funes).

**DNI 40960742 — Jenifer Riquelme (cashout_mule) — Batman Network**
Possible family/social link to Lucas Riquelme (44238411) — same surname, same Chos Malal cluster. Cashout at Branch 5182 CHOS MALAL (Funes). Confirmed: 11,000 pts received (2 transfers), 9,900 pts cashed out (3 canjes), 1,300 pts active.

**DNI 41218806 — Karina Taduyo (cashout_mule) — Batman Network**
Identified 2026-06-13. Received 8,000 pts from Carlos Barrionuevo (44679076) on 2025-04-01 via APP. Created 2025-04-01 APP — same day as the transfer, account opened to receive. Registered referencing branch MDOH01 MUNDO HELADO 01 (Franchise: Mundo Helado) — different brand from Club Grido on the same SmartLoyalty platform; indicates cross-brand fraud scope. Email: `karinataduyo1212@gmail.com` — name-matched, possibly real person recruited. Balance: 0 pts — all points already spent. NO_EN_MAILING. Earliest confirmed participant in the network: Apr 2025, 14 months before the Jun 2026 escalation.

---

**CustomerId 5DB72B42-AB4F-C9CD-1AD3-08DB103601B5 — [DEACTIVATED, PII scrubbed] (feeder) — Brainrot Cluster**
All PII fields replaced with own CustomerId GUID (deactivation pattern confirmed). Registered 2023-02-16 PUNTO DE VENTA at Branch 3822 ROQUE S. PEÑA II (Franchise: Pereyra, Diego — Chaco). First activity: 2022-11-05 (before CreatedDate — possible use as POS default CustomerId before formal registration). Last activity: 2026-05-23 16:21 ARG — exactly the 4th and final transfer to Tung Tung Sambayone. Deactivated after transfers, not before. Confirmed: 3,000 pts cashed out (1 canje), 27,000 pts transferred out (4 transfers to Tung Tung in 62 sec via APP), 815 pts HELD in smlst. Franchise surname "Pereyra" matches Angel Pereyra (DNI 48016024, Batman Network) — common Argentine surname, no confirmed link.

**DNI 18181818 — Tung Tung Sambayone (relay_hybrid) — Brainrot Cluster**
Hybrid account: POS default CustomerId fraud + transfer relay. Repeating-digit DNI (18181818) — invalid. Email: tatianasegovia2005@gmail.com (identity mismatch). Created Dec 2025. Confirmed: 27,000 pts received (4 transfers from 5DB72B42 in 62 sec on 2026-05-23), 19,000 pts cashed out (7 canjes), 38,000 pts transferred out (6 sends: 30,000 → Naza Rdz in 67 sec on 2026-06-04 with 3×8K+800+5,200 limit-bypass split; 8,000 → Bruno Mdm on 2026-06-06), 2,830 pts active. Bursts of 0-pt EarnPointsByBuying on 2026-02-01 and 2026-04-28 — CustomerId used as POS default terminal. NO_EN_MAILING.

**DNI 46652579 — Naza Rdz (cashout_mule) — Brainrot Cluster**
Full name: Nazareno Jerero Rodriguez (email: nazarenojererodriguez@gmail.com — name-matched). Registration: 2026-06-04 12:20 UTC-3, PUNTO DE VENTA, Branch 4513 LANUS OESTE II (FranchiseGroupId 4598F376). Account created same day as fraud operation — first transfer received 9 min 23 sec after registration (12:30 UTC-3). No organic POS activity (zero EarnPointsByBuying). Likely real person recruited as mule. Confirmed: 30,000 pts received (5 transfers in 67 sec), 17,750 pts cashed out (9 canjes Jun 4–11), 12,250 pts active. NO_EN_MAILING. Balance intact 2026-06-13 — suspend immediately.

**DNI 24242424 — Bruno Mdm (cashout_mule) — Brainrot Cluster**
Repeating-digit DNI (24242424) — invalid. Email: clashroyale.rocale@gmail.com (gamer handle, identity mismatch). Registration: 2023-09-01 19:46 UTC-3, PUNTO DE VENTA, Branch 3375 LA RIOJA VIII (FranchiseGroupId 9E2895B1) — invalid DNI registered at POS terminal, insider risk at Branch 3375. Account predates Brainrot cluster by 2.75 years with genuine POS activity (varied SaleIds, amounts, times — NOT a POS default CustomerId account). Cashout spree initiated 2026-05-25, 12 days before Tung Tung transfer (Jun 6) — separate activation event. Jun 1 2026: 18,500 pts in single transaction (SaleId 252089151, 16 rows same timestamp) — anomalous. Received 8,000 pts from Tung Tung on 2026-06-06 via APP. Sent 1,500 pts to Facundo Ietta (40302714) on 2026-06-07 22:32 UTC-3 via APP. Confirmed: 110,700 pts cashed out (55 canjes — ~84,200 in May–Jun 2026 spree + 2023–2024 organic), 1,500 pts transferred out (→ Facundo Ietta), 545 pts active. NO_EN_MAILING. New EventTypeCode observed: DiscountPointsByPromotion (2023-12-25, SaleId 170567465, -3,000 pts).

**CustomerId C34B7D32-4722-CC2B-EA17-08DE40DEF711 — [DEACTIVATED, PII scrubbed] (relay_destination) — Brainrot Cluster**
All PII fields replaced with own CustomerId GUID (deactivation confirmed). Received 5,000 pts from Tralalero Tralala on 2026-03-06 18:46 UTC-3 via APP. Spent ~3,990 pts between Mar 6 and May 16, 2026. Last activity: 2026-05-16 00:15 UTC-3. Confirmed: 1,010 pts HELD (Retenidos) in smlst.CustomerPointsLog — admin-reversible by CustomerId.

**DNI 40302714 — Facundo Ietta (minor_recipient) — Brainrot Cluster (peripheral)**
Email: facu.ietta24@gmail.com (name-matched). Received 1,500 pts from Bruno Mdm on 2026-06-07 22:32 UTC-3 via APP. Spent ~850 pts within 56 minutes (last activity 23:28 UTC-3). DNI 40302714 valid AR range. NO_EN_MAILING. Current balance: 650 pts active. Low-priority — may be personal contact of operator rather than recruited mule.
