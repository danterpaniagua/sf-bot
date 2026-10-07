# Investigation — Jenkins service crash loop (GITIN-2099)

Jira: https://smartit-ar.atlassian.net/browse/GITIN-2099

**Related:** [GITIN-1325](https://smartit-ar.atlassian.net/browse/GITIN-1325), "[OPE] Actualización de Jenkins" — per the user (2026-09-24), this ticket's scope is the Jenkins Java version update, not a Jenkins application/core version upgrade. The Java 17→21 fix below satisfies it directly, confirmed live and side-effect-free. GITIN-1325 was an empty ticket — its own ticket body now lives at `events/20260924_gitin1325-jenkins-java-update/ops.md`, sourced from this investigation, not re-derived.

**Status:** converged — fully resolved and verified live.

## Trigger

Jenkins service on `SFCG-JENKINS-01` (SF-LOYALTY CI controller, `DefaultGroup01`, Smart IT - Grido subscription `0190fa7d-4ccf-4e3d-beb1-323b5780bfc8`) failed after a routine VM reboot on 2026-09-23. WinSW (the Windows service wrapper) entered an infinite restart loop, cycling every 2-4 minutes for at least 30+ minutes.

## Root cause

`jenkins.err.log` showed the actual failure on every single restart attempt:
```
Running with Java 17 from C:\Program Files\Java\jdk-17, which is older than the minimum required version (Java 21).
Supported Java versions are: [21, 25]
```
Modern Jenkins core hard-requires Java 21+ and exits immediately on startup if it detects an older JVM. The box only had Java 17 (`C:\Program Files\Java\jdk-17`) installed, hardcoded as the `<executable>` in `jenkins.xml` (WinSW's config, `D:\Program Files\Jenkins\jenkins.xml`). `<onfailure action="restart"/>` with no backoff caused the infinite loop — each launch failed the version gate instantly, WinSW relaunched it, repeat indefinitely.

This is unrelated to the separate, earlier-suspected SonarScanner Java issue (GITIN-2098-adjacent investigation earlier the same day) — that was the *build-time* scanner failing on Java 17; this is the *controller itself* failing to start at all. Same underlying fact (box only had Java 17), two independent symptoms.

## Fix applied

1. Installed Eclipse Temurin JDK 21.0.12.1 (`C:\Program Files\Eclipse Adoptium\jdk-21.0.12.101-hotspot\`) via direct MSI download (Adoptium's own API, `api.adoptium.net`, resolved the real download URL — a static `github.com/.../latest/download/<filename>` guess 404'd since Adoptium's actual filenames carry a version suffix).
2. Backed up and repointed `jenkins.xml`'s `<executable>` to the new Java 21 path.
3. Restarted the Jenkins service — confirmed stable (no more restart loop, no more Java-17 warning in `jenkins.err.log`).

## Side effect 1: Windows Firewall blocked external UI access

After the JDK swap, the Jenkins UI (`https://sfcg-jenkins-01.smartfran.com:8443`) became unreachable externally, even though the service itself was healthy and `Test-NetConnection -ComputerName localhost -Port 8443` succeeded locally (loopback bypasses inbound firewall rules, which is why local test passed but external didn't).

**Root cause:** the Windows Firewall's `Jenkins` inbound rule (`Allow`, port 8443, `Profile: Any`, `RemoteAddress: Any` — looked completely unrestricted) was additionally scoped to a specific **program path**: `C:\Program Files\Java\jdk-17\bin\java.exe`. After repointing the service to the new Java 21 binary, the firewall rule silently stopped matching the new process.

**User's initial workaround (disabling Windows Firewall entirely) was flagged as a real security exposure and reverted** in favor of the actual fix: updated the rule's `Program` filter (`Get-NetFirewallRule "Jenkins" | Get-NetFirewallApplicationFilter | Set-NetFirewallApplicationFilter -Program "<new java path>"`), then re-enabled all three firewall profiles (`Set-NetFirewallProfile -All -Enabled True`). Confirmed working with the firewall active.

## Side effect 2: system `PATH`/`JAVA_HOME` change didn't propagate without a reboot

Updated `JAVA_HOME` and swapped the `Java\jdk-17` entry in the system `PATH` to Temurin 21 (`[Environment]::SetEnvironmentVariable(...,"Machine")`) — needed separately from the `jenkins.xml` fix, because `SonarScanner.MSBuild.exe` resolves `java` via system `PATH`, independent of Jenkins' own service config.

**Confirmed Windows-specific gotcha:** this change did **not** take effect for the Jenkins service after a plain `Restart-Service`, nor for a brand-new `Start-Process powershell` window spawned from the existing session — both inherited the *boot-time* environment snapshot. Windows only rebuilds a process's environment from the registry at actual system boot (services.exe and interactive logon sessions both cache it from then on). **A full VM reboot was required** to make the new `PATH`/`JAVA_HOME` actually visible anywhere. Confirmed post-reboot: `java -version` → `21.0.12.1` system-wide.

## Side effect 3: shared `sonarqube-srv` Jenkins agent lost Remoting compatibility

After the controller moved to Java 21, the `sonarqube-srv` agent (a **different VM**, `sfcg-sonarqube` — the SonarQube server itself, also acting as a shared Jenkins agent for SF-LOYALTY and SF-PEDIDOS pipelines) failed to reconnect via SSH Remoting:
```
java.lang.UnsupportedClassVersionError: hudson/slaves/SlaveComputer$SlaveVersion
has been compiled by a more recent version of the Java Runtime (class file version 65.0),
this version of the Java Runtime only recognizes class file versions up to 61.0
```
(65 = Java 21, 61 = Java 17 max — confirms the version mismatch.)

**Root cause:** `sfcg-sonarqube`'s own system-wide `java` default had drifted back to Java 17 at some point after that host's own SonarQube-focused Java 21 upgrade (`GITIN-1327`, completed 2026-09-05) — cause of the drift not investigated. SonarQube's own service was never affected by this drift (it's independently pinned via `SONAR_JAVA_PATH`, not the system default) — the drift only became visible once something else (the Jenkins agent) started depending on the system default again.

**Fix:** `sudo update-alternatives --set java /usr/lib/jvm/temurin-21-jdk-amd64/bin/java` (Temurin 21 was already installed on that host from the original GITIN-1327 work, just not selected as default). **Verified zero impact on SonarQube**: `GET /api/system/status` → `{"version":"26.9.0.129388","status":"UP"}`, uptime unaffected (no restart), all 5 SonarQube processes confirmed still running under Temurin 21 via the `SONAR_JAVA_PATH` drop-in, independent of the system default. Full detail added to `operations/docs/sonarqube_upgrade_runbook.md` § 7bis.

Confirmed resolved: `sonarqube-srv` shows connected in Jenkins after the fix.

## Hallazgo secundario 1: `LOCAL_GIT_COMMIT_MESSAGE` crash in every SF-LOYALTY Jenkinsfile's failure-notification block

Found while testing a build post-JDK-fix (`dev-src-proj-migratedatabase`, `sf-devops` repo). Every one of the 23 SF-LOYALTY jenkinsfiles' `post { failure { ... } }` block referenced `${LOCAL_GIT_COMMIT_MESSAGE}` in its Google Chat notification message, but only ever *defined* that variable in the sibling `success` block — since `success`/`failure` are mutually exclusive Jenkins post-conditions, a failing build could never have that variable set, crashing the failure-notification step itself with `groovy.lang.MissingPropertyException`. Confirmed via a working comparison: SF-PEDIDOS's equivalent jenkinsfiles correctly re-fetch all `LOCAL_GIT_*` variables independently inside their own `failure` block.

**Fix:** added the missing `LOCAL_GIT_COMMIT_MESSAGE` fetch to all 23 jenkinsfiles' failure blocks, matching each file's own existing style (`def`-scoped vs. bare, `deployUtils`-prefixed vs. local function). Committed and pushed to `sf-devops` (`origin/main`).

## Hallazgo secundario 2: `packProject.ps1` crashes on an orphaned build artifact

Found in a subsequent `dev-src-proj-webservicecg` build failure (`d:\jenkins\.jenkins\smartloyalty\compilations\test02\WebServiceCG-test02.build` not found). Root cause: the script's check for "does a prior compilation exist" used a wildcard match against the `.zip` artifact only (`Test-Path "${FileNamePrefix}*.zip"`), then unconditionally read the paired `.build` pointer file — but the two files aren't created atomically (zip first, `.build` second), so any run interrupted between those two steps leaves an orphaned zip with no `.build` file, crashing the *next* run. Likely triggered by one of today's several Jenkins service restarts/reboot interrupting an in-flight build.

**Fix:** changed the condition to require both the zip and its `.build` file to exist before attempting the archive-old-build step; otherwise falls through to a normal fresh backup — self-heals the orphaned state automatically. Committed and pushed to `sf-devops`.

## Out of scope for this ticket (separate work, not part of the incident)

- Adding GitHub-webhook-triggered builds (`GenericTrigger`) to all 16 SF-LOYALTY jenkinsfiles — a proactive feature request from the user, unrelated to this incident's root cause. Not documented here; if it needs its own ticket, ask the user for one.
- SmartPedidos BackOffice's SonarJS "bridge server unresponsive" pipeline failure — a distinct, unresolved issue on `sonarqube-srv`, likely CPU contention on that host (documented as having only 1 physical core, no headroom, per `GITIN-1327`). Flagged, not yet root-caused or fixed.

## Documentation updated

- `loyalty/docs/infrastructure.md` — added `SFCG-JENKINS-01` to the Application Servers table with the full JDK-upgrade story and both side effects.
- `operations/docs/sonarqube_upgrade_runbook.md` — new § 7bis documenting `sfcg-sonarqube`'s dual role as Jenkins agent and the system-`java`-default drift.
