# Investigation — 20261016_unity-config-consistencia-zabbix

**Status:** discovery C1 done (2026-10-16 12:48-12:54 UTC): `Config\Unity.config` exists in 11 of 12 application folders on 10 VMs and 10 files have the same MD5; no alert built yet, waiting for the user's answers (scope, golden hash vs file-vs-file, meaning of "the healthcheck one", Jira ticket).

## Request (user, 2026-10-16)
- "In each project there is, in Config, a Unity.config file. That file needs to be the same in all apps, all projects. First check on each one if the file exists, then create 2 alerts: one for each project change, and another if they are all not the same. This last one needs to be closed by hand. Also the healthcheck one."
- Ambiguous, to confirm with the user: "also the healthcheck one" (a) the same two alerts for `healthcheck.ashx` (changed per file / not identical everywhere), or (b) keep the existence alerts of GITIN-2239 (already built, plus the WebService ones in progress, C12).

## Known (from documentation and earlier events, not re-verified today)
- App folders per server (loyalty/docs/infrastructure.md): `SFCG-WEBS-01/02/03` `C:\SmartFran\SmartLoyalty.WebService\`; `SFCG-WSV2-01/02` `D:\SmartLoyalty.WebServiceV2\` (WSV2-02: `E:\` per the healthcheck-file work of GITIN-2239); `SFCG-WSIT-01` `D:\SmartLoyalty.WebSite\`; `SFCG-MOBI-01/02` `D:\SmartLoyalty.MobileAppService\`; `SFCG-TO-01` `E:\SmartLoyalty.TaskOperatorService\`; `SFCG-WSCG-01` WebServiceCG (path not documented).
- GITIN-2223 (TaskOperator, PREPROD vs TEST02): `Unity.config` was byte-identical in the two environments (same size and hash prefix `7764F07A`, last written 2026-10-09 12:06). It registers data-context types per application, so identical content across *different* applications is something to verify, not assume (the user states it must be the same).
- The loyalty clone has a template `Default-Template/Unity-Template.config` and a `Test/QueryPerformance/Config/Unity.config` (branch `main`, `d38f4fe24`); not compared.
- Zabbix 6.0: active-agent items `vfs.file.exists[path]` (works, GITIN-2239) and `vfs.file.md5sum[path]` (string); the hosts of GITIN-2239 and C12 use "... by Zabbix agent active" templates behind proxy 10609.

## Plan (proposed, nothing applied)
1. **Discovery (read-only), C1:** `az vm run-command invoke` runs `check-config-files.ps1` on each application VM: per `SmartLoyalty.*` folder, whether `Config\Unity.config` exists, size, last write (UTC) and MD5, plus the same for `healthcheck.ashx`. Output goes to `data/c1-run-*/tabla.tsv` with a summary of distinct hashes and folders without the file. This answers "does it exist on each one" and "are they identical today" before any alert is designed.
2. **Zabbix items (per file):** `vfs.file.exists[path]` and `vfs.file.md5sum[path]` (literal path in the key, as in GITIN-2239; triggers only after the first value is read).
3. **Alert A, "changed in project":** per file, trigger on `change()` of the MD5 item, severity per the user; recovers by itself on the next sample (to confirm).
4. **Alert B, "not all the same":** one trigger on a single host (e.g. `Zabbix server`) that compares the MD5 of every file with a reference one, OR a golden-hash macro per the user's choice; `recovery_mode` None plus manual close, so it stays open until someone closes it by hand (user requirement). Question: reference = golden hash in a macro (updated on each legitimate change) or file-vs-file comparison.
5. Tags: routing tags of the other healthchecks + `env=PROD` (user rule for the new triggers).

## Open questions for the user
- Confirm the meaning of "also the healthcheck one" (above).
- Confirm the scope of "all projects": every `SmartLoyalty.*` folder on the application servers listed above, including WebSite and TaskOperator? CLUB servers (website) are left out unless the user says otherwise.
- For alert B: golden-hash macro or file-vs-file comparison.
- Jira ticket for this work (folder renamed when the user gives it).

## C1 result (data/c1-apply-log-20261016T124758Z.txt, run folder data/c1-run-20261016T124758Z/, table in tabla.tsv; an earlier apply, c1-apply-log-20261016T124034Z.txt, stopped after the first VM and was repeated)
- 10 VMs found and running (`SFCG-MOBI-01/02`, `SFCG-TO-01`, `SFCG-WEBS-01/02/03`, `SFCG-WSCG-01`, `SFCG-WSIT-01`, `SFCG-WSV2-01/02`), run as SYSTEM by `az vm run-command`; 12 `SmartLoyalty.*` folders listed.
- `Config\Unity.config` exists in 11 of them. **10 files are identical** (MD5 `A658C626E3ABE2B4031C99701A3B81F9`, 64,720 bytes, last write 2026-10-09 12:06:07Z on every one): MobileAppService (MOBI-01/02), TaskOperatorService (TO-01 `E:`), WebService (WEBS-01/02/03 `C:\SmartFran`), WebServiceCG (WSCG-01 `E:`), WebSite (WSIT-01 `D:`), WebServiceV2 (WSV2-01 `D:`, WSV2-02 `E:`). The user's premise (same file in all apps) holds for these.
- Exceptions on `SFCG-TO-01`: `E:\SmartLoyalty.MigrateDataBase` has a different file (MD5 `70A2E414C49AC161D4C2E04B2DE35A9A`, 63,396 bytes, written 2025-08-13), and `E:\SmartLoyalty.SmlBackScript` has no `Config\Unity.config`. Both look like auxiliary tools, not applications; whether they are in scope is for the user to say.
- `healthcheck.ashx` exists in MOBI-01/02, WEBS-01/02/03 and WSV2-01/02; absent in TO-01, WSCG-01 and WSIT-01. Hashes: MOBI-01/02 `AD053EDC...` (equal), WSV2-01/02 `B315565A...` (equal), WEBS-02/03 `93AB2007...` (equal), **WEBS-01 `C4AF0035...` differs from WEBS-02/03** (same application). Different applications differing is expected; WEBS-01 vs WEBS-02/03 is not explained (not checked; the user said `healthcheckv2.ashx` on WEBS-01 was a test).
- The file `C:\SmartFran\SmartLoyalty.WebService\healthcheck.ashx` exists on WEBS-01/02/03 (Test-Path as SYSTEM), so the C12 items (GITIN-2239) should read 1; they had no data after about 9 minutes (cause not found; C13 pending).

## Consequences for the design
- Alert B (not all the same) can compare the 10 application files of the 9 VMs plus the exceptions the user decides to include; today they are all equal, so it starts quiet.
- For `healthcheck.ashx` a cross-application comparison does not fit (each application has its own file); a per-application comparison (WebService x3, MobileApp x2, WebServiceV2 x2) fits, and would fire today for WEBS-01.

## Scope decision (user, 2026-10-16)
- `SmartLoyalty.SmlBackScript` (`SFCG-TO-01`, `E:`) does not need a `Config\Unity.config`: out of scope, so its missing file is not a finding and gets no existence alert.
- Still open: whether `SmartLoyalty.MigrateDataBase` (`SFCG-TO-01`, `E:`, different file `70A2E414...`, written 2025-08-13) is in scope; golden hash vs file-vs-file for alert B; the meaning of "the healthcheck one"; the Jira ticket.

