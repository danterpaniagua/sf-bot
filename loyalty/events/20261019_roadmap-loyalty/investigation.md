# Investigation: SmartLoyalty roadmap — queue for point additions and a single DB writer

**Status (2026-10-19):** first roadmap item drafted in `outputs/roadmap-loyalty.md`; no Jira ticket given yet (ask the user; rename the folder to `YYYYMMDD_gitinXXXX-description` with `scripts/rename_event_folders.sh` when it is). No Loyalty roadmap file existed before this one (searched `loyalty/`, `cloud/`, `operations/`).

## Request (user, 2026-10-19)

For the Loyalty roadmap: a queue that stores every point addition and a function that writes them to the database, removing that responsibility from Mobile, WebService v1 and WebService v2; it can also be used for the website reports. Instruction: base it on the GITIN-2251 investigation.

## Evidence used (GITIN-2251, `loyalty/events/20261018_gitin2251-webs-db-misma-ventana/`)

- `Sml.CustomerPointsLog`: 404,460,588 rows, partitioned by year (16 partitions), about 500-700 inserted rows and 240-300 customers per minute at 17:00 GMT on 2026-10-18.
- Every insert fires `[Sml].[CustomerPointsLogAfterInsert]` (deployed definition equals the clone), which sums `Points` over the whole history of each inserted customer and MERGEs the total into `SmlSt.CustomerPointsLog`. No index holds `CustomerId` together with `Points` (`IX_CustomerId` is keyed on `CustomerId` without included columns), so each execution reads the customer's rows and looks `Points` up in the clustered index; cost grows with the customer's history. For customers with 484-1,171 rows the cost is small (Q11).
- In the saturation windows of 2026-10-18, WEBS sessions were the largest origin of database CPU (V1: WEBS-02, 100,038 ms against 6,890 for the next origin); the 97.5 s delta of one session could not be attributed to the trigger or to any statement, and the cause of the WEBS-02 saturation was not found. Query Store is off; the capture tables sample every ~5 minutes.
- Therefore the roadmap text does not claim the queue fixes the GITIN-2250 saturation; it says the opposite explicitly.

## Evidence from the code (`loyalty/repo/dev-src-sol-smartloyalty`, branch `main`, HEAD d38f4fe24 of 2026-10-14; working tree, not the deployed build)

- Point entries are created in domain code: `SaleService` (many `CustomerPointsLogs.Add(customerSvc.NewCustomerPointsForSale(...))` and `pendingSale.Sale.CustomerPointsLogs.Add(...)`), and `CustomerService` (lines ~1304-1441 and ~3109), `AssignmentPointsService`, `PointsExpireService`, `Exchange`, `CardService`; so more than purchases write points.
- `SaleProviderApplicationService` (v1) and `SaleProviderApplicationServiceV2` build the response from `saleResult.CustomerPointsLogs` (`PointsLogDetail.TotalEarn` / `TotalDiscount`): the POS gets the earned and discounted points in the reply of the sale call. A queue that defers the write must still define what this response contains (row 1.f of the roadmap).
- In the Mobile controllers read here (`CustomerController`, `AdditionalInformationController`) point logs are read (movements, balance from `SmlSt.CustomerPointsLog`); where Mobile writes points was **not** found. The user states that Mobile writes; the roadmap's first task is to survey it.
- Not read: `TaskOperator` and other batch writers, `ClubSiteG2` (its `MemberController` references the table), which also appear in the `CustomerPointsLog` grep.

## Open points

- Jira ticket URL for the roadmap (and for this story).
- Priority (criticality / effort) and estimate: left "A definir"; not invented.
- Whether "all point additions" includes the batch writers and the website.
- Technology of the queue (the roadmap text does not name one).

## User decisions (2026-10-19, afternoon)

- No ticket for now. The batch writers (expiry, manual assignment and others) are left for later analysis: the scope of "all point additions" is still undecided.
