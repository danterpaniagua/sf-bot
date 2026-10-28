# Runbook — SonarQube upgrade (`sfcg-sonarqube`)

> Source: ticket `GITIN-1327`, event `operations/events/20260905_sonarqube_upgrade/` (its `investigation.md` holds the sources of each fact, intermediate findings and discarded theories). This document is the persistent infrastructure reference; the event is the work record.

## 1. Goal

Upgrade the SonarQube Community Edition (9.9.3) instance on `sfcg-sonarqube` to a current SonarQube Community Build, following the official upgrade path, with no data loss and no downtime beyond the planned maintenance window.

## 2. Topology and starting state (confirmed 2026-09-05, before any jump)

- **Host:** `sfcg-sonarqube` (Azure VM, login `azureuser`), Ubuntu 20.04.6 LTS. Azure subscription `0190fa7d-4ccf-4e3d-beb1-323b5780bfc8` (Smart IT - Grido), resource group `DEFAULTGROUP01` (via IMDS).
- **Version/edition:** SonarQube **9.9.3** (build 79811), **Community Edition** (LGPL v3), confirmed in the UI ("About") and from the real process classpath.
- **Install:** manual, no symlink. `/opt/ssd01/sonarq/sonarqube/` is a real directory, runs as `sonarqube:sonarqube`, systemd service `sonarqube.service`.
- **Other directories in `/opt/ssd01/sonarq/`:** `sonarqube-9.6.1.59531/` (older version, unconfigured leftover) and `sonarqube-10/` (reported as an abandoned upgrade attempt; not verified in detail). The root `/opt/ssd01/sonarq/data/` (empty `es8` skeleton) is orphaned, probably left by that 10.x attempt (ES8 vs the real ES7 of 9.9.3).
- **Data:** `/opt/ssd01/sonarq/sonarqube/data/` (184M: ES7 index, installed plugins). `sonar.path.data` / `sonar.path.temp` are not set (default, relative to the install home).
- **Java:** OpenJDK 17.0.15 (Ubuntu package): enough for the first jump (24.12), not for 26.1.
- **Database:** PostgreSQL 13.15 (`pgdg20.04`), local `127.0.0.1:5432`, DB `sonarqube`, user `sonarqube`: enough up to 25.x, not from 26.x (needs 15+).
- **Web server:** nginx reverse proxy (`/etc/nginx/conf.d/sonar.conf`), TLS with the SmartFran wildcard certificate, proxy to `127.0.0.1:9000` with no path rewrite. Public hostname `sf-sonarqube.smartfran.com`.
- **Host specs:** 2 logical CPUs (1 physical core with hyperthreading, no headroom), 7.7 GB RAM, 159 GB free on `/opt/ssd01`. `vm.max_map_count=552428` and file-descriptor limits (65536, via systemd) already meet the Elasticsearch requirements: no OS tuning needed.

## 3. Confirmed upgrade path

SonarQube Community Edition became Community Build after 10.7 (CalVer versioning). Any instance older than 2024 must go through `24.12.0.100206` before any 2025+ release; crossing a calendar-year boundary also requires the December release of that year.

```
9.9.3 (LTA) → 24.12.0.100206 → 26.1.0.118079 → 26.9.0.129388
```

- The "natural" intermediate hop would be `25.12.0.117093`, but it has a documented database-migration bug reported by other users (SonarSource forum). `26.1.0.118079` resolves it and is documented as a valid substitute for that hop.
- `26.9.0.129388` was the latest Community Build when this was investigated: check again before executing.

## 4. Infrastructure requirements per jump

| Jump | Java | PostgreSQL |
|---|---|---|
| 9.9.3 → 24.12.0.100206 | JRE/JDK 17 (current) | 13.15 (current) |
| 24.12.0.100206 → 26.1.0.118079 | **full JDK 21 or 25** (a JRE is not enough) | **PostgreSQL 15+** (supported 15-18) |
| 26.1.0.118079 → 26.9.0.129388 | no change | no change |

Both infrastructure changes (Java and PostgreSQL) fall at the same point of the sequence.

## 4bis. Operating-system upgrade requirement

Installing PostgreSQL 15+ on Ubuntu 20.04 is no longer a clean procedure. The official PGDG repository stopped building/hosting packages for 20.04 (focal) in July 2025; PG 15/16/17 are reachable only through an archive repository that PGDG itself says has "dependency conflicts with the aging base libraries", so the install is unreliable. Ubuntu 20.04 also left standard support in April/May 2025 unless the host is enrolled in Ubuntu Pro/ESM.

**Pre-check (2026-09-05):** no Ubuntu Pro/ESM subscription (`pro status`: "This machine is not attached to an Ubuntu Pro subscription"). The mirror is `azure.archive.ubuntu.com`, which still serves `focal` (`apt-get update` works). `do-release-upgrade -c` reports `New release '22.04.5 LTS' available`.

**Risk not in the original design:** third-party repos pinned to `focal`: `ppa:deadsnakes`, Docker CE (`download.docker.com/linux/ubuntu focal`), Microsoft Azure CLI (`packages.microsoft.com/ubuntu/20.04/prod focal`), Trivy, and three Zabbix repos (`zabbix-agent2-plugins`, `zabbix-tools`, `zabbix/6.0`, all `focal`). After the move to `jammy` they fail (404) until re-pointed; `do-release-upgrade` probably disables unrecognised third-party sources, but they must be re-enabled/re-pointed by hand. The installed Zabbix agent keeps running but gets no updates until fixed: a mandatory follow-up, since Zabbix must keep working.

**Decision (user):** upgrade the host OS **in place** (`do-release-upgrade`, 20.04 → 22.04). The tool only allows the next LTS, so 24.04 would be a second, sequential upgrade (check that restriction against the current tool before executing). It is a higher-risk operation on a live production host (touches nginx, systemd and every installed package) and needs its own rollback: take a VM snapshot immediately before the OS upgrade, not only once at the start of the project (section 7).

## 4ter. The 20.04 → 22.04 jump: real problems and confirmed causes

`do-release-upgrade` needed two passes (the first stopped halfway without rebooting). Three real dpkg failures, diagnosed from `/var/log/apt/term.log` (the generic "Errors were encountered" summary does NOT give the cause: search line by line for `dpkg: error processing archive ... (--unpack)` / `(--configure)`):

- **`dotnet-hostfxr-7.0`:** depended on `dotnet-host-7.0`, missing because the Microsoft repo is pinned to `focal`. Fixed with `apt --fix-broken install` (Ubuntu's own jammy-updates ships a compatible version).
- **`cron` / `at`:** `error creating directory './var/spool/cron/crontabs': Operation not permitted`. `/var/spool/cron` had **both the immutable (`i`) and append-only (`a`)** attributes (deliberate pre-existing hardening): both had to be cleared (`chattr -ia`; `-i` alone is not enough) before dpkg could extract, then restored (`chattr +ia`). Confirmed intact after the reboot.
- **`linux-azure-tools-5.15.0-1050`:** file conflict with the obsolete `linux-azure-5.15-tools-5.15.0-1050` (kernel package rename gap between focal/jammy). `apt-get remove` refuses to run while any other package is broken (global dpkg consistency check): fixed with `sudo dpkg --remove linux-azure-5.15-tools-5.15.0-1050`, bypassing the apt resolver.

**Verified after the reboot, all healthy:** kernel `6.8.0-1065-azure`, SonarQube 24.12.0.100206 (`status: UP`, started by itself via systemd), `postgresql@13-main` with SonarQube reconnected, nginx (`HTTP 200` using the Host-header trick, section 7), Zabbix Agent 2 uninterrupted.

**Third-party repos:** of the 5 pinned to `focal`, `do-release-upgrade` automatically disabled 2 of the 3 Zabbix ones (`zabbix.list`, `zabbix-agent2-plugins.list`, with `jammy` already substituted in the comment) but left `zabbix-tools.list` active and untouched; Docker CE and Azure CLI were also untouched. All 5 were re-pointed/re-enabled to `jammy` and verified with `apt-get update` (all resolve). Trivy needed no change: its repo uses a `generic` component, not a distribution codename (it was wrongly in the original risk list).

**`ppa:deadsnakes`:** its only real purpose on this host was Python 3.10 for `get-fq.py` (a script unrelated to SonarQube that pulls Grido data into the Fabric bronze layer, hosted on this VM). Ubuntu 22.04 provides `python3.10` natively, so the repo was removed, together with `python3.9` / `python3.9-minimal` (no consumers identified).

## 5. Scope decision: the 24.04 jump is out of scope

24.04 is not needed: PGDG supports PostgreSQL 15/16/17 on Ubuntu 22.04 until well into 2029, and JDK 21 is available cleanly on 22.04 via Adoptium, so both blockers that motivated the OS upgrade are solved on 22.04. 24.04 also has no clean Python 3.10 source for `get-fq.py` (the main deadsnakes PPA does not publish it for `noble`, only its unstable nightly channel). **22.04 → 24.04 is out of scope of this ticket.** If it is taken up later, `get-fq.py` must first be containerised (Docker is already installed on the host) or otherwise decoupled from the OS Python version.

## 6. Recommended sequence (one change at a time)

1. `9.9.3 → 24.12.0.100206` first, on the **current** OS / Java 17 / PostgreSQL 13.15: validates the SonarQube-specific binary swap and rollback without mixing in OS changes.
2. **OS upgrade** 20.04 → 22.04 (not 24.04, section 5), in its own maintenance window with SonarQube 24.12 already running; verify SonarQube + PostgreSQL 13.15 + nginx before touching anything else. Separates OS-caused failures from SonarQube-upgrade failures.
3. **Java 21/25 + PostgreSQL 15+** on Ubuntu 22.04, both available cleanly from the official PGDG / Adoptium repositories.
4. `24.12.0.100206 → 26.1.0.118079`.
5. `26.1.0.118079 → 26.9.0.129388`.

## 6bis. Executed 2026-09-05: what the plan did not say

The whole chain ran on 2026-09-05 (event `operations/events/20260905_sonarqube_upgrade/`): SonarQube `9.9.3 → 24.12.0.100206 → 26.1.0.118079 → 26.9.0.129388`, Ubuntu 22.04.5 LTS, Java 17 → 21 (Temurin, Adoptium repo, Java 17 kept), PostgreSQL 13.15 → 15.19; no data loss, no Zabbix agent gap over the 2+ hours. Findings that change how to repeat it:

- **PostgreSQL 13 → 15 with `pg_upgradecluster`** (Debian/Ubuntu native tool): the new `15/main` cluster took port 5432 directly, so `sonar.properties` needed no change. Check: 21 projects, 102 tables. The old `13/main` stays stopped in `/opt/ssd01/postgresql/13/main` as the rollback plan.
- **Java selection:** setting `JAVA_HOME` in the systemd unit does nothing (`sonar.sh` resolves `java` through `update-alternatives`; SonarQube ended up on Java 17 until `update-alternatives --set java` was run in manual mode). From the 26.1 jump the version is fixed with **`SONAR_JAVA_PATH`**, the variable `sonar.sh` actually reads; confirm from the process list that all SonarQube `java` processes run from the Temurin 21 path.
- **26.9.0.129388:** the downloaded package did not keep the execute bit of the scripts in `bin/` after unzip (`chmod +x` missing); systemd had also entered its start-limit state and needed a reset. The database migration took about 2 minutes, the longest of the three.
- **Housekeeping left (no urgency):** after an observation period with 26.9 stable, `pg_dropcluster 13 main`, then archive/delete the old install directories in `/opt/ssd01/sonarq/` (`sonarqube-9.9.3.79811/`, `sonarqube-9.6.1.59531/`, `sonarqube-24.12.0.100206/`, `sonarqube-26.1.0.118079/`).
- **Disk monitoring:** `/opt/ssd01` (ext4, 251 GB) reached 96-100 % in July with no Zabbix alert because of the ext4 root reserve; see `docs/zabbix_observability.md` → "Filesystem free-space trigger on ext4 data disks" (`operations/events/20260720_sonarqube_disco_lleno/`).

## 7. Rollback plan

SonarQube schema migrations are one-way: there is no database downgrade. Rollback depends on backups taken immediately before each jump, not on one backup at the start.

**Pre-flight (once, before touching anything; repeat the snapshot right before the OS upgrade of section 6, step 2):**
- Azure disk snapshot of the VM `sfcg-sonarqube`.
- Full `pg_dump` of the `sonarqube` database.
- Backup of `/opt/ssd01/sonarq/sonarqube/data/` (184M: ES7 index + plugins). `sonarqube/temp/` need not be backed up (regenerable).
- Backup of `sonar.properties`, `sonar.conf` (nginx) and the `sonarqube.service` unit.

**For each jump (24.12, 26.1, 26.9):**
- Extract the new version into its own new directory (`sonarqube-24.12.0.100206/`, etc.), never over the running version. `azureuser` cannot write to `/opt/ssd01/sonarq/`: the `unzip` / `chown` / `cp` need `sudo` (confirmed in the real execution of jump 1).
- Copy the already configured `sonar.properties` to the new `conf/` (do not retype DB credentials).
- **Cut-over mechanism (confirmed, jump 1):** `sonarqube.service` has no `WorkingDirectory`; `ExecStart` / `ExecStop` embed the literal path `/opt/ssd01/sonarq/sonarqube/bin/linux-x86-64/sonar.sh`. The cut-over is therefore a **directory swap** (`mv sonarqube sonarqube-<old-version>`, then `mv sonarqube-<new-version> sonarqube`), not a unit edit: no systemd change, no `daemon-reload`.
- New `pg_dump` immediately before this specific jump (do not reuse the previous jump's).
- Stop `sonarqube.service`, point it at the new directory, start, check `logs/sonar.log` and `logs/ce.log`.
- **Manual database migration (confirmed, jump 1):** on start SonarQube does NOT run the schema migration; it stays in `DB_MIGRATION_NEEDED`, visible in `sonar.log` ("The database must be manually upgraded. Please backup the database and browse /setup") and in `GET /api/system/status`. Trigger it explicitly on every jump (UI at `/setup`, or `POST /api/system/migrate_db`). `ce.log` does not exist yet in this state (Compute Engine starts only after migrating): not an error. `GET /api/server/version` no longer exists from this version on; use `/api/system/status` for version/state.
- If it fails: stop, point back to the previous (intact) directory, restore this jump's `pg_dump`, restart.
- Do not delete/archive the previous version until the next jump is stable.
- **Correct post-jump check (confirmed, jump 1):** `curl` to the public hostname from the VM itself can return `000` even when everything works, because the VM does not resolve its own public DNS name. Use `curl -H "Host: sf-sonarqube.smartfran.com" https://127.0.0.1/`. The real end-to-end confirmation is from outside the VM (browser or external `curl`).
- Zabbix Agent 2 must be healthy (active, no reporting gaps) before and after each jump; the OS upgrade (section 4bis) is the highest-risk point.

**Java:** install JDK 21/25 alongside the existing JDK 17 (`update-alternatives`), without uninstalling 17: a rollback to 24.12 after a failed 26.1 attempt still needs Java 17.

**PostgreSQL:** the 13 → 15 major upgrade is a separate, harder-to-revert operation (`pg_upgrade` or dump/restore into a new cluster): keep the PG 13 cluster stopped but intact (not deleted) until PG 15 + SonarQube 26.1 are stable over an observation period, not only right after the cut-over.

## 7bis. Additional host role: shared Jenkins agent (`sonarqube-srv`), confirmed 2026-09-23 (`GITIN-2099`)

Besides SonarQube, `sfcg-sonarqube` is the Jenkins agent **`sonarqube-srv`** (Ubuntu, over SSH), shared by the SF-LOYALTY and SF-PEDIDOS pipelines (see `sf-devops/jenkins/SF-PEDIDOS/smartpedidos.md`). The role is independent of the SonarQube service and was not covered by the original `GITIN-1327` investigation.

**Confirmed finding (2026-09-23):** after the Jenkins controller (`SFCG-JENKINS-01`) moved from Java 17 to Java 21 (see `loyalty/docs/infrastructure.md` → `SFCG-JENKINS-01`), the `sonarqube-srv` agent failed its SSH/Remoting connection with `java.lang.UnsupportedClassVersionError` (class file 65 = Java 21 vs 61 = maximum for Java 17). The system `java` on this host (resolved through `update-alternatives`, **not** `SONAR_JAVA_PATH`) still pointed to `java-17-openjdk-amd64`, although Temurin 21 had been installed on the host since `GITIN-1327` itself.

**Why `java-17` became the system default again:** not investigated. The `update-alternatives --set java` to Temurin 21 recorded in the `GITIN-1327` event was accepted at the time as a trade-off ("nothing else depends on 21 yet"); later something reverted it to 17 (not confirmed whether a routine `apt upgrade` re-triggering `auto` mode, a manual revert, or another cause). SonarQube never depended on this system default (it uses `SONAR_JAVA_PATH` since the jump to 26.1), so the drift had no visible effect on it; it showed only when **another** consumer of the system `java` (the Jenkins agent) needed a Java 21-compatible version.

**Fix applied (2026-09-23):** `sudo update-alternatives --set java /usr/lib/jvm/temurin-21-jdk-amd64/bin/java` (manual mode, not `auto`). **Verified with no SonarQube impact** before and after: `GET /api/system/status` → `{"version":"26.9.0.129388","status":"UP"}` with no interruption, service uptime intact (no restart), the 5 SonarQube `java` processes still running from `/usr/lib/jvm/temurin-21-jdk-amd64/bin/java` through the `SONAR_JAVA_PATH` drop-in: the SonarQube `SONAR_JAVA_PATH` and the host-wide `update-alternatives` are independent mechanisms.

**Lesson:** on this host, changing the system default `java` (`update-alternatives`) is safe for SonarQube, but SonarQube is not the only `java` consumer (the Jenkins agent is another). Before assuming a drift of the system default is harmless, confirm what else depends on it.

## 8. Out of scope

- **AI Code Assurance / AI-generated code detection:** a Developer Edition (paid) feature onward, not available in Community Build at any version. It would need a separate edition/licence decision, outside `GITIN-1327` as understood today.
- The `sonarqube-10/` directory (abandoned upgrade attempt, user-reported) was not verified in detail: before executing, confirm it holds no partial migration state that could confuse the real attempt.
- **OS jump to Ubuntu 24.04:** discarded for this ticket (section 5); a separate future initiative, conditional on decoupling `get-fq.py` from the OS Python version first.

## 9. References

- https://docs.sonarsource.com/sonarqube-community-build/server-update-and-maintenance/update/determine-path
- https://docs.sonarsource.com/sonarqube-community-build/server-installation/server-host-requirements
- https://community.sonarsource.com/t/upgrade-path-for-our-sonarqube-community-edition-9-9-3-instance/149250
- https://community.sonarsource.com/t/sonarqube-community-build-25-12-0-117093-released/153805
- https://community.sonarsource.com/t/postgresql-compatibility-for-sonarqube-upgrade-from-9-9-3-to-25-4/145051
- https://www.postgresql.org/message-id/aCtIvml4sCYnRSjp@msg.df7cb.de (PGDG drops Ubuntu focal packages, July 2025)
- https://ubuntu.com/blog/ubuntu-20-04-lts-end-of-life-standard-support-is-coming-to-an-end-heres-how-to-prepare (Ubuntu 20.04 end of standard support)
