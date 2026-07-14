# SmartLoyalty — Infrastructure Reference

**Last updated:** 2026-07-11
**Subscription:** Smart IT - Grido (`0190fa7d-4ccf-4e3d-beb1-323b5780bfc8`)

---

## Database Server

| Field | Value |
|---|---|
| Instance | `SFCG-DB01` |
| Engine | Microsoft SQL Server 2022 Standard, 64-bit, version 16.0.4075.1 |
| Host OS | Windows Server 2022 Datacenter |
| Server timezone | GMT (UTC+0) — all `LogDate`/timestamp columns are GMT; user's local timezone defaults to UTC-3 |

---

## Application Servers

| Host | Role |
|---|---|
| `SFCG-WEBS-01/02/03` | WebService (`C:\SmartFran\SmartLoyalty.WebService\`) |
| `SFCG-WSV2-01` | WebServiceV2 (`D:\SmartLoyalty.WebServiceV2\`) |
| `SFCG-WSIT-01` | WebSite (`D:\SmartLoyalty.WebSite\`) |
| `SFCG-MOBI-01/02` | Mobile service |
| `SFCG-WSCG-01` | CG web service |
| `SFCG-CLUB-01/02` | Club Grido website |
| `SFCG-TO-01` | TaskOperatorService (`E:\SmartLoyalty.TaskOperatorService\`) |
| `SFCG-DB01` | SQL Server host (see Database Server below) |
| `LUCAS-KIUVI` | QA workstation — must not connect to production |

### Database accounts

| Account | Type | Used by | Role on SmartLoyalty |
|---|---|---|---|
| `SMARTIT\itservices` | Windows domain | All app servers | cross-role (not audited) |
| `sfsqlusr` | SQL login | TaskOperatorService (SFCG-TO-01) | `db_owner`, `db_securityadmin` ⚠️ over-privileged |
| `sfsqlusrit` | SQL login | QA / SSMS (LUCAS-KIUVI) | `db_owner`, `db_securityadmin` ⚠️ over-privileged |
| `NT SERVICE\SQLSERVERAGENT` | Windows service | SQL Agent jobs | system |

---

## Databases

| Database | Purpose | Query scope |
|---|---|---|
| `PNSSRL` | Monitoring — index maintenance captures, blocking info, tempdb usage, CPU/memory captures | Default target for DBA investigation queries (`/loyalty-dba-investigation`) |
| `SmartFran.Solution.SmartLoyalty` | Production — points, customers, sales, promotions, fraud investigation surface | Query only when explicitly requested or via a skill granting implicit access (e.g. `/loyalty-fraud-points`) |

Read-only access only — never DML/DDL against either database.

---

## Network / Azure Placement

SmartLoyalty's VMs and networking sit on the **Smart IT - Grido** subscription, distinct from the **SmartIT Cloud** subscription (`85c76dea...`) that hosts SmartFran Cloud (see `cloud/docs/infrastructure.md` — do not confuse the two).

| Resource | Value |
|---|---|
| Resource group (prod) | `DefaultGroup01` |
| VNet (prod) | `sfcgvnet01` (`192.168.0.0/16`) |
| Resource group (dev/staging) | `SFCG-REGR-DEV` |
| VNet (dev) | `SmartFran-vnet` (`10.2.0.0/16`) |
| Azure AD DS domain | `smartit.azure` |
| AADDS DC subnet | `192.168.40.0/24` |
| AADDS DC IPs | `192.168.40.4`, `192.168.40.5` |

Full NSG rules, VNet peering, and private endpoint inventory: `../docs/azure_nsg.md` (repo-root shared reference — covers both `sfdev02-nsg` and `sfcgnetsec01`).

---

## Multi-brand Platform Scope

SmartLoyalty hosts multiple franchise brands on the same DB instance:

| Brand | Registration identifier |
|---|---|
| Club Grido | `GRIDO*`, `GR*` branch codes |
| Mundo Helado | `MDOH*` branch codes |

---

## Related

- Skills: `/loyalty-dba-investigation`, `/loyalty-fraud-points`, `/loyalty-fraud-pos`, `/loyalty-azure-nsg` — investigation workflow and query patterns for this infrastructure.
- `../docs/azure_nsg.md` — NSG/VNet/AADDS detail, shared across projects on this subscription.
- `memory/` — persistent fraud actor memory (known hubs, relays, POS actors), not infrastructure.
