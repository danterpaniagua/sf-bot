# Investigation — CPU spike, 2026-09-22 16:30-22:00 (mobile-requests hypothesis)

**Jira:** none for now — investigation only, no ticket to be filed at this stage.

## Scope

High CPU usage on `PNSSRL`/`SmartFran.Solution.SmartLoyalty` (`SFCG-DB01`), reported window **2026-09-22, 16:30-22:00 local (UTC-3)** → **19:30-01:00 GMT (2026-09-22 to 2026-09-23)**, server timezone.

**User's working hypothesis:** high volume of Mobile app requests (`SFCG-MOBI-01/02`) driving CPU.

## Related recent investigation (not the same incident — confirmed with user)

`loyalty/events/20260922_gitin2087-spike-cpu-loyalty/` (GITIN-2087) — a CPU spike the day before, **2026-09-21 ~17:00 UTC-3**, still open. Found `ASYNC_NETWORK_IO` fleet-wide across WebService v1 hosts (`SFCG-WEBS-01/02/03`, SOAP), client not consuming result rows fast enough on an EF/LINQ-generated `Sml.Promotion` query — not confirmed as the single root cause across all matched sessions yet. Different day, different working hypothesis (SOAP/WebService v1, not Mobile) — treated as a separate occurrence per user confirmation, but worth checking whether this 09-22 window shows the same `ASYNC_NETWORK_IO` signature or something distinct (Mobile-driven, per the new hypothesis).

Also worth checking against the broader recurring-CPU-spike history for this project before concluding anything new: `events/20260518_cpu_spikes/`, `events/20260530_cpu_spikes/`, `events/20260715_cpu_spikes/`, `events/20260727_cpu_peaks_loadtest/`, `events/20260803_cpu_peaks_loadtest/`, `events/20260920_cpu-spikes/` (root cause there: `Query101`'s `OR`/`LOWER()` pattern on `SmlSt.CustomerAdditionalInformation`, Dev fix still pending).

## Status

**Converged.** Data available for the full window (66 snapshots, 19:31-00:56 GMT, `data/c1_data_availability_check.txt`). CPU-delta-per-SPID query run two ways — aggregated by host/program, and top 30 individual SPIDs — `data/queryA_B_hostprogram_and_top30_spids.txt`.

## Confirmed facts

- **Mobile-requests hypothesis not supported.** `SFCG-MOBI-01`+`SFCG-MOBI-02` combined = 6,833 CPU-delta units out of a fleet-wide total of ~516,800 (~1.3%) across the full window — the smallest contributor of any app server, despite `MOBI-02` alone having the most distinct sessions of any single host (50 spids). Mobile is driving request *volume*, not CPU.
- **WebService v1 (SOAP) dominates**, same as GITIN-2087 the day before: `SFCG-WEBS-03` (157,351), `SFCG-WEBS-01` (123,124), `SFCG-WEBS-02` (67,630) — combined 348,105 (~67% of total). `SFCG-WSIT-01` (WebSite) adds another 125,407 (~24%). WEBS+WSIT together = ~92% of all CPU delta in the window.
- **Same root-cause signature as GITIN-2087 and the original 2026-05-18 finding**, now identified precisely: two LINQ/Entity-Framework-generated queries, both using the pattern `ORDER BY row_number() OVER (...) OFFSET 0 ROWS FETCH NEXT 2147483647 ROWS ONLY` — an unpaginated "fetch everything" idiom — recurring repeatedly across WEBS-01/02/03 with `ASYNC_NETWORK_IO` (suspended, client not consuming result rows fast enough) or `SOS_WORK_DISPATCHER` (runnable, CPU spent serializing the large result set) wait types:
  - Query against `Sml.Promotion` (`ActivatedDate IS NOT NULL AND DeactivatedDate IS NULL AND ValidToDate >= @p`) — full active-promotions catalog pull. Top single-sample CPU: 78,139 (WSIT-01, MISCELLANEOUS/sleeping — largest single row in the whole sample).
  - Query against `Sml.Article` JOIN `Sml.Product WHERE ForSale = 1` — full sellable-product catalog pull. Matches the *exact* description from the original 2026-05-18 finding ("LINQ queries against the product catalog").
  - These two queries alone account for the large majority of the top-30 CPU-delta rows.
- **Secondary, much smaller pattern**: a customer-lookup query (`WHERE LOWER(Email) = LOWER(@p)`, non-sargable predicate) recurs across CLUB-01/WSCG-01/MOBI-02/WSIT-01 at ~4,000 CPU-delta each — minor compared to the catalog-pull queries above, but a real `LOWER()`-on-column pattern (same class of issue as `Query101`'s known `OR`/`LOWER()` problem from `events/20260920_cpu-spikes/`). Not investigated further this session — flagged for awareness only.
- One `SFCG-CLUB-01` row (`Query077-sql.xml`, `SOS_SCHEDULER_YIELD`, 4,859 CPU) is genuinely CPU-bound query processing (XML param parsing + promotion/branch-office join), not an I/O-wait pattern — distinct from the dominant signature, minor contributor.

## Conclusion

This is very likely the **same recurring, unresolved issue** as GITIN-2087 (2026-09-21) and the original 2026-05-18 finding, recurring again the very next day — not a new mobile-driven problem. The mobile-requests hypothesis is ruled out by the CPU-delta breakdown. Root cause: WebService v1 (SOAP, WEBS-01/02/03) and WebSite (WSIT-01) issuing unpaginated LINQ queries against `Sml.Promotion` and `Sml.Article`/`Sml.Product` that fetch the entire table in one round-trip, with the client not consuming the result set fast enough (`ASYNC_NETWORK_IO`) and/or the server spending CPU serializing it (`SOS_WORK_DISPATCHER`).

## Open questions / next steps

- The old 2026-05-18 finding's recommended next step (check WebService v1 source for the actual LINQ query and its result-set/paging config) is still not done — same gap GITIN-2087 also flagged. Worth doing once for both tickets since the query shapes are now precisely identified (`Sml.Promotion` full-catalog pull, `Sml.Article`/`Sml.Product` full-catalog pull).
- Confirm whether this is a genuinely daily/periodic pattern (e.g. triggered by a scheduled sync or cache-refresh job hitting WebService v1) by checking a few more recent days for the same signature.
- GITIN-2087 is still open with its own next steps (source-code check, daily-pattern confirmation) — this session's findings should be merged into that ticket rather than opened as a separate one, given it's confirmed the same underlying pattern.
