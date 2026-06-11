---
name: feedback-ticket-sql-queries
description: When creating event tickets that involved SQL queries, save queries to a separate .sql file and reference them from the ticket with a brief description table
metadata:
  type: feedback
---

When a ticket (events/ artifact) involves SQL queries that were executed during the investigation or fix:

- Save all queries to a separate `.sql` file in the same event subfolder, named `YYYYMMDD_description_scripts.sql`
- In the ticket, include a reference table with columns: `#`, `Query` (short name), `Propósito` (one-line description of what the query does)
- Do NOT embed full SQL blocks in the ticket body

**Why:** Keeps tickets readable and concise; full query text is available for reference in the `.sql` file.

**How to apply:** Any time a ticket is created or updated that involved SQL queries run against the server.
