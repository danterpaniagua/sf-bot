# Investigation: GITIN-1468 — dedicated Graylog for SmartCloud (project summary)

**Status (2026-10-20): closed by the user.** `ops.md` written from the project's own records at the user's request ("create ops based on investigation in cloud-graylog"); nothing was run against Azure or Graylog for this event. Jira: https://smartit-ar.atlassian.net/browse/GITIN-1468. The Jira title and body were not seen; the ticket was identified by the user as "the ticket for cloud-graylog". The title in `ops.md` is descriptive, not the Jira title.

## Sources (all read 2026-10-20, local files only)
- The separate project `~/Documentos/git/cloud-graylog/` (not in `bots/`): `CLAUDE.md` (authoritative state, last entries 2026-09-15), `README.md` (stale: says only the Sales pilot is live, last updated 2026-07-02), `docs/architecture.md`, and the `ops.md` of its 10 event folders (2026-06-25 to 2026-09-15). Its working tree has uncommitted edits (`CLAUDE.md`, `docs/architecture.md`, Terraform, event scripts), so the text read may differ from its last commit (`68678cf`, 2026-07-02).
- Later work tracked here in `bots/cloud/events/`: GITIN-1794 (DEV tier), GITIN-1834 (all 8 PROD apps), GITIN-1937 and GITIN-1940 (HTTP logs), GITIN-1946 (three Function Apps, 2026-08-26) and GITIN-2050 (all four, 2026-09-15); folders exist for all of them.
- The project's internal ids (CG-001 ... CG-007) are not Jira ids; the parent "CG-001" (central logging via Event Hubs) is probably the umbrella this ticket stands for, not confirmed.

## What is not verified (everything in `ops.md` is "per the project's records")
- Current state of Azure (Diagnostic Settings, Event Hub, VM size/phase) and of Graylog (streams, index sets, inputs); no `az` or API call was made.
- Certificate: the records say it expires 2026-09-28 with certbot auto-renewal active; that date has passed and the renewal was not checked.
- NSG: SSH and Graylog web were opened to `0.0.0.0/0` temporarily at provisioning (2026-06-30); whether they were closed is not recorded.
- Key rotation: the Event Hub listen key and the checkpoint storage key were pasted in plaintext in July; the records say "rotate if not already done"; no confirmation of rotation was found.
- Costs are the project's figures (Log Analytics $679 for June 2026 from Cost Analysis, read 2026-07-03; Graylog infrastructure estimates from retail prices), not rechecked.
- Whether the old Docker Graylog index `graylog_299` finding (2026-06-25) was fixed is not recorded.

## Notes for a later session
- Rules applied to `ops.md`: no name of the sibling repo, no local paths, no developer names, no key values or IPs.
- Open items copied from the records are listed in `ops.md` under "Acciones propuestas"; check each before reporting it as still open.
