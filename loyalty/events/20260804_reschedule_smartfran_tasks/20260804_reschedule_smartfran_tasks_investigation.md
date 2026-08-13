# Investigation — 20260804_reschedule_smartfran_tasks

**Status:** open

## Confirmed facts
- Jira ticket: [GITIN-1753](https://smartit-ar.atlassian.net/browse/GITIN-1753)
- Origin: action item #5 from GITIN-1749 (`20260803_cpu_peaks_loadtest`) — a cluster of 5 daily `\SmartFran\` scheduled tasks on `SFCG-DB01` fires between 12:00 and 12:30 GMT, overlapping SPID 114's (TaskOperatorService `CustomerPointsLog` sync) active window (12:06-13:06 GMT). Identified as a routine business-day-start pattern contributing to "peak 1" observed in two consecutive load-test CPU investigations (GITIN-1669, GITIN-1749).
- Tasks to reschedule: `ReportUpdateCustomer`, `ReportErrorSurveyNoResponse`, `NotSamplesSurveyActivated`, `Promotion Vigency Advisor B`, `Promotion Vigency Advisor C`.
- Target: scheduled for tomorrow, 2026-08-04.
- Target time window not yet defined — need to distribute the 5 tasks at times distinct from each other and outside SPID 114's 12:06-13:06 GMT window.

## Current working theory
Not a root-cause fix for the still-unresolved CPU peaks 2/3 (GITIN-1749) — this addresses the separate, already-explained "peak 1" clustering by spreading routine load away from the SPID 114 window, as a general load-hygiene improvement.

## Open questions / next steps
- Confirm new target times for each of the 5 tasks (any business constraints — e.g. do these reports need to complete before a specific downstream deadline?).
- Apply the reschedule via Task Scheduler on `SFCG-DB01`.
- Verify new schedule takes effect (next `LastRunTime`/`NextRunTime` reflects the change).
