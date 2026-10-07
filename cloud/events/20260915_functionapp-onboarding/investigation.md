# Investigation — 20260915_functionapp-onboarding

**Jira:** GITIN-2050
**Status:** converged — migrated from a separate repo (`cloud-graylog`, not part of this monorepo) after the work was already completed and verified there. This file is a light summary; `ops.md`/`ops-events.md` carry the full detail.

## Context

Not an incident — planned onboarding. Two gaps existed before this work: (1) the 4 SmartFran Cloud Function Apps (`SFC-CodeGenerator-PRO`, `SFC-ScheduledJobs-PRO`, `SFC-PosWasmRelay-PRO`, `SFC-TicketProcess-PRO`, all on `SFC-FunctionAPP-Linux-Plan-PRO`) were not onboarded to the Graylog ingestion pipeline at all; (2) even where `FunctionAppLogs` messages did land in the shared Default stream, the category had never had any field promotion — every message showed the generic Azure fallback `"Microsoft.Web/sites/functions/log"`, because `properties` arrives as a Python dict-repr string (single-quoted), not JSON, and no existing `JSON.parse`-based guard in the Logstash pipeline ever matched it.

## Confirmed facts

- Terraform onboarding (diagnostic settings for the 4 apps + their `stg2` slots) applied cleanly: 5 added, 0 changed, 0 destroyed.
- `SFC-TicketProcessAsync-PRO` no longer exists in Azure — renamed to `SFC-TicketProcess-PRO`; the old Terraform resource was updated in place, not left orphaned (a stale-name reference would have broken the whole `terraform plan`, not just this onboarding).
- Graylog's `name` field indexes uppercase (from `resourceId`) — a query using Azure's exact mixed-case resource name returns `0` silently. Caused a real false negative during this session before being traced to the actual cause.
- New Ruby parser (`azure-eventhub-to-graylog.conf`, `if [category] == "FunctionAppLogs"` block) handles both `properties.message` shapes found (`Host.Function.Console`, nested Python dict-repr; `Function.<name>`/`.User`, plain string) — validated against 9 real captured messages before touching the live pipeline.
- Deployed to production, `logstash -t` clean, `NRestarts=0` reconfirmed minutes after restart — no crash loop.
- End-to-end field promotion confirmed live for all 4 apps, including `SFC-TicketProcess-PRO` (open item from the original onboarding session, closed in a follow-up verification the same day) — see `ops-events.md`.
- Live-deployed config re-pulled and diffed against this repo's copy in the same follow-up verification: identical except the two by-design-redacted connection strings.

## Security incident, resolved in-session

The live-config re-pull (verification pass, not the original deploy) wrote 2 files containing a real Event Hub `SharedAccessKey` and Storage `AccountKey` in plaintext under this event's `data/` — plus 2 derived diff files that also carried them. All 4 redacted in place immediately on discovery; none had been git-staged. Both values were also visible briefly in a tool output during that session. **Not yet decided whether these two keys should be rotated** — flagged in Pendientes, not resolved here.

## Ruled out

- A leftover diagnostic setting (`ticketprocessasync_pro_sfc`, pointing at the old pre-rename resource name) is not urgent — orphaned until the next unscoped `terraform apply`, no functional impact in the meantime.

## Open questions / next steps

- `terraform apply` without `-target` to clean up the orphaned `ticketprocessasync_pro_sfc` diagnostic setting.
- Share (`Everyone`/`Viewer`) the 4 new streams — done for the DEV stream in GITIN-1794, not yet done here.
- Decide whether the briefly-exposed `SharedAccessKey`/`AccountKey` need rotating.
- `Duration=Xms`/`Succeeded`/`Failed` on `Function.<name>` completion lines remain free text inside `message`, not extracted to structured fields.
