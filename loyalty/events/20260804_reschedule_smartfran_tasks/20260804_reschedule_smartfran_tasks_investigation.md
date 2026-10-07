# Investigation — 20260804_reschedule_smartfran_tasks

**Status:** Closed (confirmed via real Jira content, 2026-09-09). Final resolution differs from this file's original plan below — see "Actual resolution" section.

## Confirmed facts
- Jira ticket: [GITIN-1753](https://smartit-ar.atlassian.net/browse/GITIN-1753), subtask of [GITIN-1749](https://smartit-ar.atlassian.net/browse/GITIN-1749) — "[SML] Mover tareas que corren en horario productivo."
- Origin: action item #5 from GITIN-1749 (`20260803_cpu_peaks_loadtest`) — a cluster of daily `\SmartFran\` scheduled tasks on `SFCG-DB01` fires between 12:00 and 12:30 GMT, overlapping SPID 114's (TaskOperatorService `CustomerPointsLog` sync) active window (12:06-13:06 GMT). Identified as a routine business-day-start pattern contributing to "peak 1" observed in two consecutive load-test CPU investigations (`20260727_cpu_peaks_loadtest` — ticket unconfirmed, previously mis-cited as GITIN-1669, which actually belongs to an unrelated event; and GITIN-1749).
- Original plan (below) was to reschedule 5 tasks: `ReportUpdateCustomer`, `ReportErrorSurveyNoResponse`, `NotSamplesSurveyActivated`, `Promotion Vigency Advisor B`, `Promotion Vigency Advisor C`. **Superseded — see actual resolution below, which used a different task list and a disable approach, not a reschedule.**

## Actual resolution (per real Jira ticket content, confirmed 2026-09-09)

Disabled (not rescheduled) 4 tasks: `ReportErrorSurveyNoResponse`, `NotSamplesSurveyActivated`, `ReportSurveyUnsatisfied`, `ReportSampleMailResponseXSurvey`. Two of these (`ReportSurveyUnsatisfied`, `ReportSampleMailResponseXSurvey`) don't appear in this file's original 5-task list — not previously tracked here. `Promotion Vigency Advisor B`/`C`, part of the original plan, aren't mentioned in the real closure at all — status unconfirmed, not necessarily addressed.

**Still pending, not resolved by this ticket:** `ReportUpdateCustomer` — still runs at 12:00 UTC (09:00 UTC-3), unchanged. It was the one task in the original cluster explicitly *not* disabled; whether it still overlaps SPID 114's window or was otherwise addressed is unconfirmed.

## Current working theory (original, superseded by the actual resolution above)
Not a root-cause fix for the still-unresolved CPU peaks 2/3 (GITIN-1749) — this addresses the separate, already-explained "peak 1" clustering by spreading routine load away from the SPID 114 window, as a general load-hygiene improvement. (This framed the plan as a *reschedule*; the actual resolution was a *disable*, a different mechanism, though the same underlying goal.)

## Open questions / next steps
- `ReportUpdateCustomer` remains on its original 12:00 UTC schedule — still needs an actual fix if the SPID 114 overlap is still a concern; not evaluated further here.
- `Promotion Vigency Advisor B`/`C`'s status is unconfirmed — not mentioned in the real ticket closure. Confirm whether they were addressed elsewhere or simply dropped from scope.
- `loyalty/docs/infrastructure.md`'s "Known clustering issue" note (Scheduled Tasks section) still describes the original 5-task cluster and should be checked against this actual resolution — not yet updated as of this correction.
