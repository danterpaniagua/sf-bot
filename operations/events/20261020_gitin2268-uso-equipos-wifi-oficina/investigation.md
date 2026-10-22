# Investigation: use of company machines and the office WiFi problems (no ticket yet)

**Status (2026-10-20):** `email_equipos.md` approved to send with one change (reviewer, via the user: do not attribute CPU use to the internet problems, it would draw pushback); the high-CPU / tools sentences were removed and the email states the rule only. Not sent as far as the chat shows. Earlier: drafted, pending approval; opened for one deliverable, an email to the office staff; no ticket yet (the Jira id will rename the folder when it exists, `scripts/rename_event_folders.sh`).

## Request (user, 2026-10-20)
Write an email related to the WiFi problems in the office: the machines provided by SmartFran are strictly for work and for the role given, so any app such as a game hub is forbidden.

## Context
- Related event: `operations/events/20261019_gitin2257-herramienta-estado-conexiones/` (closed "no viable": Google Admin gives no per-host data for the office; no Zabbix in the office). It gives no measurement of what each machine consumes, so **no link between any app and the WiFi problems has been shown**. The user reports (2026-10-20) that some PCs show high CPU and that this may cause connection problems (user-stated, not measured here); the email says (user-stated) that tools to measure what each machine consumes are being worked on, and cites that report with that hedge and does not say that game apps caused it.
- The rule comes from the user; whether a written company policy exists, and a deadline or a check for removal, were not stated and are not in the email.

## Open
- Audience (all office staff, or only some roles) and who signs: the draft addresses "equipo" and is left for the user to adjust.
- If a ticket is created, rename the folder and reference it.

## Second email (user, 2026-10-20): `email_problemas_equipos.md`
- Procedure stated by the user: every laptop/PC problem is reported by email to Operaciones with a copy to the person responsible (PM / CTO); RAM and disk improvements will be analysed; a replacement has to be requested by the responsible and depends on inventory and the user's role. The draft adds only "indicate the machine name and what happens" (not stated by the user). No deadlines or response times are promised.
- Not sent as far as the chat shows. It overlaps with the line "Cualquier problema con su equipo debe reportarse a su líder" in `email_equipos.md`: same subject, different recipient (leader vs Operaciones with copy to the responsible); to reconcile before sending both.

## Ticket and ops (2026-10-20)
- Jira: https://smartit-ar.atlassian.net/browse/GITIN-2268, "[OPE] Problemas con WiFi" (parent of GITIN-2269 and GITIN-2270, user-stated). `ops.md` written at the user's request ("ops for 2268"), then rewritten in full on 2026-10-21 at the user's request ("redo ops.md") from the state below (adds the first complete run of the 2270 script; the first version was assumed not yet pasted into Jira, not confirmed); ticket still open. The folder was renamed on 2026-10-21 from `20261020_uso-equipos-wifi-oficina` to `20261020_gitin2268-uso-equipos-wifi-oficina` with `scripts/rename_event_folders.sh` (dry run then apply, both run locally; outputs in `data/rename-dry-run-gitin2268.txt` and `data/rename-apply-gitin2268.txt`; the script left a symlink under the old name, to be removed by the user). Check after apply: 0 references to the old name outside `data/`.
- 2026-10-20: the two email drafts (`email_equipos.md`, `email_problemas_equipos.md`) were moved to `operations/events/20261020_gitin2271-redaccion-emails/` (GITIN-2271); both fixes of the review (stray line, "su líder" line) were applied there. Mentions of the emails above refer to those files.

## State at 2026-10-21 (summary; details in the sibling events)
- GITIN-2270 (audit script): first complete run on one Windows 10 laptop without administrator (all 20 sections OK; Windows 11, elevated run and 2.4 GHz not covered). The earlier `ArgumentException` did not recur and its cause was never identified (not reproduced, not fixed). See `operations/events/20261020_gitin2270-script-auditoria-wifi/investigation.md`.
- GITIN-2271 (emails): both drafts live in `operations/events/20261020_gitin2271-redaccion-emails/`, not sent as far as the chat shows.
- GITIN-2269 (Meet quality): closed. `ops.md` of this ticket was written once on 2026-10-20 and is unchanged; its action 1 (test the script) is still open.

