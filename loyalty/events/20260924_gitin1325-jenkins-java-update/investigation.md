# Investigation — Jenkins Java version update (GITIN-1325)

**Jira:** [GITIN-1325](https://smartit-ar.atlassian.net/browse/GITIN-1325), "[OPE] Actualización de Jenkins"

## Status

**Converged — satisfied by work already done under GITIN-2099, moved here.** GITIN-1325 was an empty ticket (no description/notes) scoping "update Jenkins' Java version." That work was actually performed reactively on 2026-09-23 while resolving GITIN-2099 (`loyalty/events/20260923_gitin2099-jenkins-service-crash-loop/`) — a Jenkins service crash loop whose root cause was `SFCG-JENKINS-01` running Java 17 while modern Jenkins core hard-requires Java 21+. Per the user (2026-09-24), the Java-update actions belong under this ticket rather than only GITIN-2099. This folder's `ops.md` is written to be pasted into the (currently empty) Jira ticket.

**Not a re-investigation** — no new diagnostic work was done to produce this folder. All facts, root cause detail, commands, and verification steps are carried forward from GITIN-2099's own `investigation.md`/`ops.md`/`scripts.sh`, which remain the full technical record. This folder exists to give GITIN-1325 its own ticket body, since the two Jira tickets track the same underlying fix for different reasons (GITIN-2099: incident response; GITIN-1325: planned Java-version update, executed ahead of schedule by the incident).

## Context (carried forward from GITIN-2099, not re-derived)

- `SFCG-JENKINS-01` (SF-LOYALTY CI controller) failed to start after a routine VM reboot on 2026-09-23 — `jenkins.err.log`: `Running with Java 17 ... older than the minimum required version (Java 21). Supported Java versions are: [21, 25]`.
- Fix: installed Eclipse Temurin JDK 21.0.12.1, repointed WinSW's `jenkins.xml` `<executable>` to it, confirmed stable (no more restart loop).
- Three side effects of the JDK swap, all fixed and independently verified same day: Windows Firewall rule was program-path-scoped to the old `jdk-17\java.exe` (fixed via `Set-NetFirewallApplicationFilter`, firewall kept enabled); system `PATH`/`JAVA_HOME` change required a full VM reboot to propagate (Windows caches env at boot); shared Jenkins agent `sonarqube-srv` lost Remoting compatibility due to its own unrelated Java-default drift back to 17, fixed via `update-alternatives`, zero impact on SonarQube confirmed.
- Full command list: `events/20260923_gitin2099-jenkins-service-crash-loop/scripts.sh` — not duplicated here.
- Documentation already updated: `loyalty/docs/infrastructure.md` (`SFCG-JENKINS-01` entry), `operations/docs/sonarqube_upgrade_runbook.md` §7bis.

## Open questions (not pursued, out of scope for closing this ticket)

- Why `SFCG-JENKINS-01`'s Jenkins core was already on a version requiring Java 21+ before this session — i.e. whether a prior, undocumented Jenkins core/plugin upgrade already happened, or the box was provisioned that way. Not investigated; doesn't block this ticket's Java-version-update scope.
- Root cause of `sonarqube-srv`'s own Java-default drift back to 17 after its GITIN-1327 upgrade — flagged as pending in GITIN-2099, not re-opened here.

## Next steps

`ops.md` written for pasting into GITIN-1325. No further action expected — mark the ticket resolved once pasted, referencing GITIN-2099 for full technical detail.
