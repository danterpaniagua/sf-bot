---
name: feedback-activity-vs-ticket
description: Before writing test results, findings, or updates to an event, ask the user whether it should go as an activity log entry or a ticket update
metadata:
  type: feedback
---

When working on an event (operations/events/ or loyalty/events/), do NOT automatically update the ticket (_ops.md) or any other file with test results, command outputs, or new findings.

**Why:** The user distinguishes between "activities" (execution logs, test results, command outputs) and "ticket updates" (changes to the formal ticket content). These may go to different files or formats.

**How to apply:** After receiving command output or a new finding, ask: "¿Lo registro como actividad o actualizo el ticket?" before writing anything. Wait for the user's answer.
