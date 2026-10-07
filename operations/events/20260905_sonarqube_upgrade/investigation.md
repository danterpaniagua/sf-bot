# SonarQube upgrade (GITIN-1327)

Jira: https://smartit-ar.atlassian.net/browse/GITIN-1327

## Goal

Upgrade the SonarQube instance running on `sfcg-sonarqube`.

## Prior context checked

No prior investigation exists for a SonarQube upgrade. The only related local artifact is `operations/events/20260720_sonarqube_disco_lleno/` — a Zabbix disk-alerting miscalibration on the same host's `/opt/ssd01` filesystem. Different problem (monitoring gap, not version/upgrade), same host. Not assumed to be causally related unless evidence emerges.

## Host facts (confirmed, see `data/host_info.txt`)

- Host: `sfcg-sonarqube` (Azure VM, `azureuser` login)
- OS: Ubuntu 20.04.6 LTS
- SonarQube install path: `/opt/ssd01/sonarq/`
- Process owner: `sonarqube:sonarqube`
- Java: OpenJDK 17.0.15 (Ubuntu build)
- Webserver: nginx (reverse proxy, `/etc/nginx/conf.d/sonar.conf`), listening on 80/443, in front of the SonarQube app (see `data/webserver_check.txt`)
- SonarQube app process: `java` pid 1201814, bound to `127.0.0.1:9000` (web) — additional local `java` processes/ports observed (1201690 on 9001/44639, 1201884 on 32967), consistent with SonarQube's separate Web/Compute Engine/Search Elasticsearch node processes, not yet individually confirmed
- Database backend: PostgreSQL running locally, bound to `127.0.0.1:5432` (pid 941) — version not yet confirmed
- Public hostname: `sf-sonarqube.smartfran.com`, TLS via the shared SmartFran wildcard cert (`smartfran_wild.crt`), nginx proxies straight to `127.0.0.1:9000` with no path rewrite (see `data/nginx_sonar_conf.txt`) — the upgrade shouldn't need nginx config changes unless the target version changes SonarQube's default context path/port

## Install layout (confirmed, see `data/sonar_properties_grep.txt`, `data/version_confirm.txt`)

`/opt/ssd01/sonarq/` contains three plain directories (none are symlinks): `sonarqube/`, `sonarqube-10/`, `sonarqube-9.6.1.59531/`, plus `data/` and `temp/`.

- **Live version: SonarQube 9.9.3 (build 79811), Community Edition** (LGPL v3) — edition/version confirmed via the SonarQube web UI "About" footer (obtained from the front-end, not a shell command), consistent with the running process's classpath (`sonar-application-9.9.3.79811.jar`) confirmed earlier via SSH. Running from `/opt/ssd01/sonarq/sonarqube/`. `sonarqube.service` (systemd) is active/running.
- `sonarqube-9.6.1.59531/` — older, unconfigured (template `sonar.properties`, no JDBC set) — likely a leftover from the version installed before 9.9.3, never removed.
- `sonarqube-10/` — reported by the user as an old, abandoned upgrade attempt (not yet independently verified — contents, its own `sonar.properties`, whether `data`/`es` subdirs were ever initialized are still unchecked). Treated as inert/not-in-use for planning purposes unless a check surfaces otherwise.

9.9.3 is a SonarQube LTA (Long-Term Active) release, so the current install is not off-cycle, just behind the newer LTA line — needs the target version (GITIN-1327 scope) confirmed before further planning.

## Confirmed dependency versions

- Java: OpenJDK 17.0.15
- PostgreSQL: 13.15 (Ubuntu, `pgdg20.04`)
- Both are compatible with 9.9.3; whether they meet the *target* upgrade version's minimums is still open (Java 17 covers most current LTA lines; PostgreSQL 13 support cutoff varies by target SonarQube version and should be checked against official requirements once a target is picked).

## Upgrade path (per official docs — see sources below)

Important edition note: this instance is **Community Edition** (LGPL v3). Per the official docs, **after version 10.7, Community Edition was renamed to Community Build with a new (CalVer) versioning scheme** — so 9.9.3 predates both the rename and the new scheme. Community Build has no LTA concept (continuous monthly releases) — distinct from the commercial "SonarQube Server" line (which does have a 2026.1 LTA, but requires a paid license/different edition). Unless a decision is made to switch editions/purchase a license, the target should be a current Community Build release, not the Server LTA.

Confirmed directly from SonarSource's official "Update path examples" table (see `data/update_path_table.md`, pasted verbatim from the docs — supersedes an earlier WebFetch summary that mis-stated this as "two intermediate steps"):

**9.9 LTA (Community Edition) → 24.12.0.100206 → 25.4.0.x (one intermediate step)**

General pattern confirmed by the table: any pre-2024 (edition-based-versioning) source must first hop to `24.12.0.100206` before reaching any 2025+ release. Separately, crossing a calendar-year boundary within the new CalVer scheme (e.g. 25.9.0.x → 26.3.0.x) requires a stop at that December's release (25.12.0.x) first — this only becomes relevant if the final target is a 2026.x build.

So for this instance: `9.9.3 → 24.12.0.100206` is mandatory regardless of final target. If the final target is a 2025.x build, that's the only intermediate hop (one intermediate step total). If the final target is a 2026.x build, an additional stop at `25.12.0.x` (or whatever December-2025-equivalent release is current) is likely needed — not yet confirmed against the live table for a 2026.x target specifically.

### Decided target and path

Target chosen: **26.9** (2026.9 Community Build). Full path, following the documented pattern (mandatory pre-2024 bridge + one December stop per calendar-year boundary crossed):

**9.9.3 (LTA) → 24.12 (December release) → 25.12 (December release) → 26.9** — two intermediate steps.

This is self-consistent with the official pattern (matches the `9.9 LTA > 24.12.0.100206 > 25.4.0.x` and `25.9.0.x > 25.12.0.x > 26.3.0.x` rows in `data/update_path_table.md`).

### Confirmed build numbers (see `data/build_numbers.md`)

| Hop | Version | Full build |
|---|---|---|
| 1 (mandatory bridge) | 24.12 | **24.12.0.100206** |
| 2 (year-boundary bridge) | 25.12 | **25.12.0.117093** |
| 3 (final target) | 26.9 | **26.9.0.129388** (confirmed current latest Community Build) |

**Risk confirmed (see `data/25_12_known_issue.md`):** 25.12.0.117093 has a documented database-migration bug, fixed in the following 26.1.0.118079 release. Corroborated by two separate community-forum reports of real upgrade failures on/around 25.12.0.117093 (an Elasticsearch error during upgrade, and a separate failed 25.12→26.5.0 upgrade). SonarSource's own 26.1 release notes state 26.1.0.118079 can substitute for 25.12.0.117093 as an intermediate hop.

**Revised recommended path:** `9.9.3 → 24.12.0.100206 → 26.1.0.118079 → 26.9.0.129388` (substituting 26.1.0.118079 for 25.12.0.117093 as the year-boundary bridge, per the documented workaround).

Separate, unrelated note surfaced from the same research: Java 17 is deprecated as a supported **scanner** runtime as of the 25.12 release (scanner-side support ends July 2026) — this is about the analysis-scanner client, not the server JVM.

**Confirmed server-side blocker (see `data/java_requirement_26x.md`):** since the 26.1.x release, the SonarQube Community Build **server** requires a full **JDK 21 or 25** (a JRE alone is not sufficient) for ZIP installs — the current host Java 17 no longer suffices once past 24.12.0.100206. Java must be upgraded to JDK 21/25 *before* the 26.1.0.118079 hop. 24.12.0.100206 (first hop) still runs on the existing Java 17.

Also confirmed general host requirements: 4GB RAM/2 CPU/30GB disk minimum for small-scale (up to 1M LOC), 16GB RAM/8 CPU for large-scale (up to 50M LOC); Elasticsearch-related Linux prerequisites must be satisfiable (explicitly unsupported on Azure App Service/AWS App Runner/Fargate — not applicable here, this is a plain Azure VM). Still open: actual `vm.max_map_count`/ulimit values on `sfcg-sonarqube` against current requirements, host RAM/CPU/disk against the above minimums, and PostgreSQL version requirement for 26.x (current host has PostgreSQL 13.15 — not yet confirmed compatible).

## Edition note: "AI Code Assurance" / Autodetect AI code — out of scope for this upgrade

User asked how SonarQube's AI-generated-code detection works. Confirmed:
- **Autodetect AI code** works by matching **GitHub Copilot Business usage statistics** (via a GitHub App integration) against recent contributors/commits — not by analyzing code content for AI "fingerprints," and not retroactive to older commits.
- Detection just surfaces an "AI code detected" badge; a Project Admin then opts the project into a stricter **AI Code Assurance** quality profile/gate.
- **This is a Developer Edition+ (paid) feature — not available in Community Build**, which is what this instance runs and what the whole planned upgrade path (9.9.3 → 24.12 → 26.1 → 26.9) stays within. Reaching 26.9 will not unlock it; that requires a separate edition/licensing decision, out of GITIN-1327's scope as currently understood.

Sources: https://docs.sonarsource.com/sonarqube-server/2025.1/instance-administration/ai-features/autodetect-ai-code , https://www.sonarsource.com/blog/sonarqube-compare-editions/

## PostgreSQL upgrade requirement (see `data/postgresql_requirement.md`)

Confirmed the host's current PostgreSQL 13.15 will not survive the full path to 26.9:
- Fine through hop 1 (24.12.0.100206) — 12.7+ still works.
- Fine through 25.1.0.102122 (11 dropped, 13-17 supported).
- **Not fine by the 26.x line** — the supported floor moved to 15-18 (13 and then 14 successively dropped). PostgreSQL must be upgraded from 13.15 to **at least 15** before the 26.1.0.118079 hop.
- Exact SonarQube build where each floor bump took effect isn't pinned precisely — re-verify against 24.12's and 26.1's own upgrade notes immediately before executing, since these pages change.
- Community-recommended practice: do the PostgreSQL major upgrade *during* one of the SonarQube version hops (not as a separate standalone maintenance window) to minimize total downtime.

## Consolidated plan summary (as of this research pass)

Confirmed path: `9.9.3 → 24.12.0.100206 → 26.1.0.118079 → 26.9.0.129388`

Required infrastructure changes beyond the SonarQube binary swap itself:
1. **Java**: OpenJDK 17 (current) is fine through 24.12.0.100206; must become a full **JDK 21 or 25** before the 26.1.0.118079 hop.
2. **PostgreSQL**: 13.15 (current) is fine through 24.12.0.100206 and 25.x; must become **PostgreSQL 15+** before the 26.1.0.118079 hop.
3. Both infra bumps land at the same point in the sequence (the 24.12 → 26.1 transition) — can likely be done together in one maintenance window, per community-recommended practice.
4. Still unconfirmed: host RAM/CPU/disk against 26.x minimums (4GB/2CPU/30GB small-scale — SonarQube host's actual specs not yet pulled), and current `vm.max_map_count`/ulimit values for Elasticsearch.
5. Edition stays Community Build throughout — no license/edition change implied by this path. AI Code Assurance and similar Developer+ features remain unavailable regardless of version reached (see edition note above).
6. `sonarqube-10/` directory (reported as an old abandoned upgrade attempt) still not independently verified — worth a quick check before starting, in case it holds a stale partial DB migration state that could confuse the real attempt.

## Rollback design

SonarQube DB schema migrations are one-way — there is no "downgrade" migration path. The only real rollback mechanism at the DB level is restoring from a backup taken immediately before each hop. Binary/install-directory rollback is separate and cheap if done right (never overwrite in place).

### One-time pre-flight (before touching anything)
- Azure VM disk snapshot of `sfcg-sonarqube` — cheapest, most complete fallback for the whole operation; covers anything not accounted for below.
- Full `pg_dump` of the `sonarqube` database (schema + data).
- **Resolved:** confirmed via `lsof` on the live PIDs (1201690/1201814/1201884) that the real, actively-used data directory is `/opt/ssd01/sonarq/sonarqube/data` (184M — ES7 index shards/translogs, `web/deploy/plugins/*`), the default relative location (`sonar.path.data`/`sonar.path.temp` are commented out, so they resolve to `<install home>/data`). The top-level `/opt/ssd01/sonarq/data/` (48K, only an empty `es8` skeleton + empty `web/deploy`, untouched since 2023-11-09) is **dead/orphaned** — no open file handles from the running process reference it. `es8` is a strong tell: SonarQube 10.x bundles Elasticsearch 8 (vs. ES7 for 9.9.3), so this is almost certainly debris from the abandoned `sonarqube-10/` upgrade attempt the user mentioned, not anything to preserve or worry about.
- **Backup target for data:** `/opt/ssd01/sonarq/sonarqube/data` (184M) — this holds the search index and installed plugin jars; back it up (tar/rsync) as part of the pre-flight and before each hop, alongside the `pg_dump`. `sonarqube/temp` (148M) is regenerable working state (exploded plugins, JNA libs) — not necessary to back up.
- Back up `sonar.properties`, nginx `sonar.conf`, and the `sonarqube.service` unit file (small, cheap, no excuse to skip).

### Per-hop rollback (repeated at 24.12, 26.1, and 26.9)
- **Never overwrite the currently-running version's directory in place.** Extract each new version into its own new directory (`sonarqube-24.12.0.100206/`, etc.), alongside the existing ones — the previous binary/install stays untouched as an instant fallback.
- Copy the real, already-configured `sonar.properties` (jdbc url/user, ports, `javaAdditionalOpts`) from the currently-active install into the new version's `conf/` — never hand-retype DB credentials.
- Take a **fresh `pg_dump` immediately before each hop**, not just once at the start — schema changes at every hop, so each needs its own restore point.
- Stop `sonarqube.service`, point it at the new version's directory (`WorkingDirectory=`/`ExecStart=`, or a symlink if one gets introduced), start it, tail `logs/sonar.log` and `logs/ce.log` for migration success/failure.
- **If it fails:** stop the service, point it back at the previous version's directory (still intact), restore the pg_dump taken immediately before this specific hop, restart. Returns to exact last-known-good state.
- Only delete/archive a previous version's directory after the next hop is confirmed stable (UI reachable, background tasks processing, no error spam) — keep each hop's own rollback available until superseded by the next confirmed-good one.

### Special handling for the Java/PostgreSQL bumps at the 26.1 hop
- **Java:** install JDK 21 alongside the existing JDK 17 (`update-alternatives`, don't uninstall 17) — a rollback to 24.12 after a failed 26.1 attempt still needs Java 17 available.
- **PostgreSQL:** the 13→15 major-version upgrade is its own harder-to-reverse operation (`pg_upgrade` or dump/restore into a fresh cluster) and deserves an explicit rollback plan of its own — keep the old PG 13 cluster/data directory intact and stopped (not deleted) until PG 15 + SonarQube 26.1 are both confirmed stable over a soak period, not just immediately after cutover.

## Host specs vs. requirements (confirmed, see `data/host_specs.txt`)

| Requirement (small-scale, up to 1M LOC) | Minimum | Host has | Verdict |
|---|---|---|---|
| CPU | 2 cores | 2 logical CPUs — but **1 physical core, hyperthreaded** (Xeon Platinum 8171M), not 2 real cores | Meets the letter of the requirement, no headroom; worth watching under load, not a hard blocker |
| RAM | 4GB | 7.7GB total, 4.9GB available | Comfortable |
| Disk | 30GB, 10% free min | 251GB total, 159GB avail (34% used) on `/opt/ssd01` | Comfortable — plenty of room to stage multiple versions during the upgrade |
| `vm.max_map_count` (Elasticsearch) | 262144 (typical ES minimum) | 552428 | Already well above, no OS tuning needed |
| Open file descriptors (Elasticsearch) | 65536 (typical) | 65536/65536 effective on the running process (systemd-set, overrides the plain user ulimit of 1024) | Already correctly configured |

No OS-level tuning required before the upgrade. The only real infra gaps remain the ones already identified: **JDK 21/25** (currently JRE-class Java 17) and **PostgreSQL 15+** (currently 13.15), both needed before the 26.1.0.118079 hop.

## OS upgrade requirement (new finding — changes the plan)

Checked whether Java 21 and PostgreSQL 15+ can simply be installed on the existing Ubuntu 20.04 without an OS upgrade:

- **Java 21:** workable via Adoptium/Temurin's own apt repo (Ubuntu's default 20.04 repos don't carry it) — lower risk, standard cross-distro approach.
- **PostgreSQL 15+: not clean anymore.** The official PGDG apt repository **stopped building/hosting packages for Ubuntu 20.04 (focal) as of July 2025** — that OS release is EOL on PGDG's side too. PG 15/16/17 packages are only reachable via an archive repo, which PGDG itself acknowledges has "dependency conflicts with the aging base system libraries" making installation unreliable.
- **Independently:** Ubuntu 20.04 reached end of standard support in April/May 2025 — over a year past EOL as of this investigation (2026-09-05), unless the host is enrolled in paid Ubuntu Pro/ESM (not yet confirmed).

**Pre-check confirmed (2026-09-05):** no Ubuntu Pro/ESM subscription attached (`pro status` — "This machine is not attached to an Ubuntu Pro subscription"). The mirror in use is `azure.archive.ubuntu.com` (Azure's own regional mirror), which still serves `focal` fine despite standard EOL — `apt-get update` works cleanly. `do-release-upgrade -c` confirms: `New release '22.04.5 LTS' available`.

**New risk, not covered in the original design:** five third-party apt repos are pinned specifically to `focal`: `ppa:deadsnakes`, Docker CE (`download.docker.com/linux/ubuntu focal`), Microsoft's Azure CLI repo (`packages.microsoft.com/ubuntu/20.04/prod focal`), Trivy, and **three Zabbix repos** (`zabbix-agent2-plugins`, `zabbix-tools`, `zabbix/6.0`, all suffixed `focal`). After the upgrade to `jammy` (22.04) these will 404 until re-pointed — `do-release-upgrade` will likely auto-disable them during the process (standard, safe behavior for unrecognized third-party sources), but they need manual re-pointing/re-enabling to `jammy` afterward. The already-running Zabbix agent won't stop working immediately, but it won't get updates until this is fixed — a mandatory follow-up given the explicit Zabbix requirement, not optional cleanup.

Confirmed via IMDS: subscription `0190fa7d-4ccf-4e3d-beb1-323b5780bfc8` (Smart IT - Grido), resource group `DEFAULTGROUP01`.

**Pre-flight snapshots taken (2026-09-05), both confirmed `Succeeded`:** `sfcg-sonarqube-osdisk-pre-osupgrade-20260905` (OS disk, `sfcg-sonarqube_disk1_5b73c015058a4087a30e4531abc729fc` — also covers the hop-1 pg_dump/data-tarball backups living in `/home/azureuser/`, since those are on the OS disk) and `sfcg-sonarqube-datadisk-pre-osupgrade-20260905` (data disk, `sfcg-sonarqube_DataDisk_0`, i.e. `/opt/ssd01`). Cleared to proceed with `do-release-upgrade`.

**Decision (user-confirmed):** upgrade the host OS **in place** (`do-release-upgrade`, 20.04 → 22.04 → 24.04 — Ubuntu's release-upgrade tool only allows hopping to the next LTS, not skipping one, so this is two sequential upgrades; verify this restriction still holds against current tooling before executing) rather than standing up a new VM. This is a higher-risk path on a live production host (touches nginx, systemd, every other installed package, not just SonarQube's dependencies) and needs its own rollback plan (the pre-flight VM snapshot already covers this — confirm the snapshot is taken immediately before the OS upgrade specifically, not just once at the very start of the whole project).

**Revised sequencing (isolates variables — one change at a time):**
1. `9.9.3 → 24.12.0.100206` first, on the **current** OS/Java 17/PostgreSQL 13.15 — validates the SonarQube-specific binary-swap/rollback procedure without conflating it with OS changes.
2. **OS upgrade** (20.04 → 22.04 → 24.04), its own dedicated maintenance window, with SonarQube 24.12 already running — verify SonarQube + PostgreSQL 13.15 + nginx all continue working correctly post-OS-upgrade before touching anything else. Isolates OS-upgrade breakage from SonarQube-upgrade breakage.
3. **Java 21/25 + PostgreSQL 15+ upgrade**, now cleanly available via the official PGDG/Adoptium repos on the new OS.
4. `24.12.0.100206 → 26.1.0.118079`.
5. `26.1.0.118079 → 26.9.0.129388`.

## Hop 1 complete: 9.9.3.79811 → 24.12.0.100206

Executed 2026-09-05. Sequence: pre-flight backups (pg_dump, data dir tarball, config backups) → downloaded/extracted 24.12.0.100206 → directory swap cutover (`sonarqube` → `sonarqube-9.9.3.79811`, new build → `sonarqube`) → service restart → manual DB migration via `POST /api/system/migrate_db` (confirmed: SonarQube does NOT auto-migrate on startup, waits in `DB_MIGRATION_NEEDED` state — applies to every future hop too) → verified.

**Verified healthy:** `GET /api/system/status` → `{"version":"24.12.0.100206","status":"UP"}`. Compute Engine started and processed real production `ISSUE_SYNC` tasks against real projects (`TEST.SmartFran.Cloud.*`) — confirms it's operating against the real DB, not an empty one. nginx→SonarQube end-to-end confirmed via local curl with a forced `Host` header (`HTTP 200`) — the direct public-hostname curl from the VM itself returned `000`, which turned out to be the VM being unable to resolve its own public DNS name (`getent hosts` empty), not an upgrade issue. **Lesson for future hops:** always verify via `curl -H "Host: sf-sonarqube.smartfran.com" https://127.0.0.1/` from the VM, not by curling the public hostname directly from the same host.

Benign, unrelated to the upgrade: one nginx `connect() refused` during the ~20s restart window (expected), and pre-existing background TLS scan noise in the nginx error log (random IPs, spans days before/after this change).

Zabbix Agent 2 (6.0.48) confirmed unaffected before and after this hop.

Permission note: `azureuser` has no direct write access to `/opt/ssd01/sonarq/` — every write there (`unzip`, `chown`, `cp`, `mv`) needs `sudo`. Also: `pg_dump ... -f <path>` fails if `<path>` isn't writable by the `postgres` OS user — use shell redirection (`pg_dump ... > <path>`) instead, which writes as the invoking user.

## OS upgrade in progress: real issues hit and root causes confirmed (2026-09-05)

`do-release-upgrade` to 22.04 completed userspace/package metadata changes (`/etc/os-release` reports jammy) but did **not** reach the final reboot — it exited after `dpkg` errors, leaving 237 packages "unpacked but not configured." Root has NOT been rebooted yet (`uptime` still shows the original 2026-06-18 boot). Three real per-package failures diagnosed via `/var/log/apt/term.log` (not just the generic "errors were encountered" summary, which doesn't include the actual reason):

1. **`dotnet-hostfxr-7.0`** — missing dependency `dotnet-host-7.0`, isolated to the .NET chain (only `dotnet-runtime-7.0` depends on it; nothing SonarQube/nginx/PostgreSQL/Zabbix-related). Root cause: Microsoft's dotnet apt repo is pinned to `focal` (exactly the pre-flagged third-party-repo risk) so the jammy transition couldn't resolve it from there — but Ubuntu's own jammy-updates/jammy-security repos carry a compatible `dotnet-host-7.0` directly. Fixed cleanly via `apt --fix-broken install`.
2. **`cron` / `at`** — real error: `error creating directory './var/spool/cron/crontabs': Operation not permitted` (and `.../atjobs` for `at`). Root cause: `/var/spool/cron` has the **immutable attribute** set (`lsattr -d` → `----ia--------e-------`) — a pre-existing, deliberate security hardening control on this host (not something the OS upgrade introduced), which blocks any structural change inside the directory even for root. Fix: temporarily `chattr -i`, let the packages configure, then `chattr +i` again afterward — must restore the hardening, not leave it disabled.
3. **`linux-azure-tools-5.15.0-1050`** — real error: `trying to overwrite '/usr/lib/libcpupower.so.5.15.0-1050', which is also in package linux-azure-5.15-tools-5.15.0-1050`. Root cause: a known Ubuntu kernel-package rename gap — this specific kernel build straddles the old focal-era naming (`linux-azure-5.15-tools-X`) and the new jammy-era naming (`linux-azure-tools-X`) without a `Replaces:` relationship covering it. Fix: remove the obsolete old-named package first.

**Update:** `cron`/`at` actually needed BOTH the immutable (`i`) AND append-only (`a`) attributes cleared from `/var/spool/cron` — clearing only `i` still left dpkg unable to finalize the extracted files (its rename-into-place step is blocked by append-only too, not just immutable). `chattr -ia /var/spool/cron` resolved it. The `linux-azure-tools-5.15.0-1050`/old-package conflict needed a direct `sudo dpkg --remove linux-azure-5.15-tools-5.15.0-1050` — `apt-get remove` alone refused to run at all while the package DB had any other broken/half-configured package present (a global-consistency check apt does before computing any plan), and the `apt-get install pkgname-` trailing-dash-for-removal syntax didn't survive copy/paste cleanly. After both fixes, `apt-get dist-upgrade` completed cleanly: `0 upgraded, 0 newly installed, 0 to remove and 0 not upgraded`.

Kept local (`N`) on all config-file prompts encountered: `/etc/sysctl.conf`, `/etc/nginx/nginx.conf`, `/etc/crontab` — each flagged as locally modified, each likely holding real host-specific customization not safe to overwrite with the maintainer's default. `/var/spool/cron`'s `chattr +ia` hardening restored and confirmed matching its original state.

**Package state fully clean, confirmed 2026-09-05:** `apt-get check` silent, `dpkg --configure -a` silent, `apt-get dist-upgrade --dry-run` → `0 upgraded, 0 newly installed, 0 to remove and 0 not upgraded`.

## OS upgrade hop 1 complete: 20.04 → 22.04.5 LTS (jammy)

Rebooted 2026-09-05 19:20 UTC. Fully verified post-reboot:
- Fresh boot confirmed (`uptime` "up 2 min" at check time), kernel `6.8.0-1065-azure` (new).
- SonarQube: all 4 sub-processes (app/ES/WebServer/CE) auto-started via `sonarqube.service` on boot with zero manual intervention. `GET /api/system/status` → `{"version":"24.12.0.100206","status":"UP"}`.
- PostgreSQL `postgresql@13-main`: active, `pg_isready` confirms accepting connections, SonarQube already holding multiple idle HikariCP connections to it (reconnected cleanly).
- nginx: active, end-to-end reachability confirmed via `HTTP 200` (Host-header trick, since this VM still can't resolve its own public DNS name).
- Zabbix Agent 2 (6.0.48): active, no interruption across the whole reboot.
- `/var/spool/cron` hardening (`chattr +ia`) confirmed intact post-reboot: `----ia--------e-------`, matching pre-upgrade state exactly.

**Zabbix repos fixed and verified (2026-09-05):** `do-release-upgrade` disabled `zabbix.list` and `zabbix-agent2-plugins.list` as expected, and had already pre-substituted `jammy` into the commented-out line (just needed uncommenting) — but it left `zabbix-tools.list` **fully active and still pointing at `focal`** (silently working only because Zabbix's repo happened to still serve that path). Fixed: uncommented the first two, rewrote `focal`→`jammy` in the third. `apt-get update` confirms all three now resolve cleanly against `jammy` (real `Get:` hits, no 404s).

**Correction:** Trivy's repo is NOT actually codename-pinned — its distribution field is literally `generic` (`https://aquasecurity.github.io/trivy-repo/deb generic main`), not `focal`. It was incorrectly included in the original "5 at-risk repos" list; it needs no fix and was never actually broken by the OS upgrade.

**Docker CE and Microsoft Azure CLI checked (2026-09-05):** both still active and still pinned to `focal`, untouched by `do-release-upgrade` (no auto-disable happened for either, unlike two of the three Zabbix repos). Azure CLI's repo is in the newer deb822 format (`azure-cli.sources`, `Suites: focal`), not the classic `.list` one-liner format.

Fixed: `focal`→`jammy` in `docker.list`, `Suites: focal`→`Suites: jammy` in `azure-cli.sources`. `apt-get update` confirms both now resolve cleanly against `jammy`.

**`ppa:deadsnakes` investigated and resolved (2026-09-05):** the repo was already auto-disabled by `do-release-upgrade`. Found its actual purpose on this host: a script `get-fq.py` (pulls Grido data into the Fabric bronze layer, hosted on this same VM — unrelated to SonarQube itself) needs **Python 3.10 specifically**, per the user. `python3.10` is now served natively from jammy's own default repos (priority 500) since jammy's native `python3` is 3.10, so deadsnakes is no longer needed for that. `python3.9`/`python3.9-minimal` were also installed but had zero identified consumers (no formal reverse-deps beyond each other, nothing in systemd/cron referencing them, nothing running) — purged, along with the deadsnakes repo file itself.

**`get-fq.py` note:** the user reports the OS/Python environment changes from this upgrade required a fix to this script, and confirms it has been re-tested and is working. Not independently verified by me (no test output seen) — recorded as user-confirmed, not independently confirmed.

**Real open risk carried into the next step:** `get-fq.py` needs Python 3.10 specifically. The upcoming `22.04 → 24.04` OS hop brings Python 3.12 natively, not 3.10 — need an explicit plan for how the script keeps its 3.10 dependency across that hop (deadsnakes re-enabled for 24.04's codename, a dedicated venv, or similar) before executing it, to avoid repeating the breakage that was just fixed.

## Scope decision: 24.04 hop dropped from this ticket

Re-checked whether 24.04 is actually required: **it isn't.** PGDG supports PostgreSQL 15/16/17 on Ubuntu 22.04 with no cutoff until well into 2029, and JDK 21 is cleanly available on 22.04 via Adoptium's repo — both blockers that justified the OS upgrade in the first place are already resolved at 22.04. Going further to 24.04 was only ever "available," never actually required.

This matters because of `get-fq.py`'s Python 3.10 dependency: the main deadsnakes PPA does **not** publish Python 3.10 for Ubuntu 24.04 (noble) — only their nightly/unstable channel does, which isn't appropriate for a production data pipeline (confirmed via web search, not assumption). 22.04 has no such problem (native `python3.10` from jammy's own repos, already established).

**`sonarqube.service` now explicitly pinned to `JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64`** via a systemd drop-in (`/etc/systemd/system/sonarqube.service.d/java-home.conf`) — done before installing JDK 21, since `sonar.sh` otherwise resolves `java` via PATH/`update-alternatives`, which installing a new JDK could silently repoint. Restarted and confirmed still `status: UP` on 24.12.0.100206, explicitly launching with the java-17 binary. This decouples SonarQube's JVM version from whatever `update-alternatives` does going forward — will just flip this one line at the 26.1 cutover instead of relying on system-wide defaults.

**JDK 21 installed (2026-09-05) via Adoptium/Temurin repo.** `update-alternatives` confirmed it DID switch the system default `java` to `temurin-21-jdk-amd64` (priority 2111, highest, over java-17's 1711). (Also found java-11 and java-13 already present on this host, unrelated/pre-existing, no action needed.)

**Correction — the `JAVA_HOME` systemd drop-in pin from earlier did NOT actually work, despite appearing to at the time.** Discovered when SonarQube was restarted after the PostgreSQL upgrade (below): its ElasticSearch/CE/WebServer sub-processes came up under `temurin-21-jdk-amd64`, not java-17, even though the drop-in was confirmed loaded and `JAVA_HOME` was confirmed present in the process's real environment (`/proc/PID/environ`). Root cause: `sonar.sh` doesn't check `JAVA_HOME` at all — it hardcodes `/usr/bin/java`, resolved via the system-wide `update-alternatives` symlink; and internally-spawned sub-processes inherit `java.home` from whatever JVM the main app process itself is running under, not from any environment variable. The earlier verification (right after setting the pin, before JDK 21 was installed) was a false positive — there was no alternative JVM yet for PATH resolution to conflict with, so it happened to "work" for reasons unrelated to the pin itself.

**Real fix:** `sudo update-alternatives --set java /usr/lib/jvm/java-17-openjdk-amd64/bin/java` (manual mode, not auto — survives future package installs without silently flipping again). Restarted, confirmed via live process inspection that every SonarQube sub-process now runs under java-17, and `GET /api/system/status` → `{"version":"24.12.0.100206","status":"UP"}`. **Trade-off accepted:** this changes the system-wide default `java` for anything else on this host that bare-calls `java`, not just SonarQube — acceptable since nothing else currently depends on 21 (just installed, nothing configured against it yet).

**Refinement found while prepping the 26.1 hop:** 26.1.0.118079's `sonar.sh` explicitly supports `SONAR_JAVA_PATH` as an override (`findjava()` checks it before falling back to PATH-resolved `java`) — a different, per-service mechanism than the `JAVA_HOME` approach that didn't work for 24.12. This is the correct way to pin Java going forward, instead of the blunt system-wide `update-alternatives` swap: set `SONAR_JAVA_PATH=/usr/lib/jvm/temurin-21-jdk-amd64/bin/java` in the systemd drop-in as part of the 26.1 cutover itself (not before, since setting it earlier risks 24.12 picking it up too if it happens to honor the same variable — untested, and moot now since 24.12 is about to be retired anyway). The `jres/` directory bundled in 26.1's install (`OpenJDK21U-jre-*` tarballs for multiple platforms) is for **scanner-side JRE auto-provisioning**, not the server's own runtime — unrelated to this.

## Hop 2 complete: 24.12.0.100206 → 26.1.0.118079

Executed 2026-09-05, same pattern as hop 1 (fresh pg_dump + data tarball backup, download/extract into new directory, directory-swap cutover, manual DB migration trigger). This time `SONAR_JAVA_PATH=/usr/lib/jvm/temurin-21-jdk-amd64/bin/java` (set via the systemd drop-in, replacing the ineffective `JAVA_HOME` line) worked correctly on the first attempt — confirmed via live process inspection that the main app process and Elasticsearch both launched under Temurin 21 immediately, no repeat of the hop-2-Java-pin incident from the PostgreSQL migration.

Confirmed via `sonar.log`: Elasticsearch config path is `data/es8/config` — this version uses Elasticsearch 8 (matches the earlier prediction from the orphaned `es8` skeleton left by the abandoned `sonarqube-10/` directory).

**Fully verified healthy:** `GET /api/system/status` → `{"version":"26.1.0.118079","status":"UP"}`, Compute Engine connected to the PostgreSQL 15 cluster, nginx end-to-end confirmed `HTTP 200` (Host-header trick), Zabbix Agent 2 continuously active throughout (no interruption, 1h22min uptime at check time). Old install preserved intact at `/opt/ssd01/sonarq/sonarqube-24.12.0.100206/` for rollback.

## Hop 3 in progress: 26.1.0.118079 → 26.9.0.129388

Confirmed `SONAR_JAVA_PATH` mechanism unchanged in this version's `sonar.sh` before cutover — same drop-in config carries over without modification. Config diff clean, same swap-directory cutover pattern.

**Real failure hit and fixed:** the initial start failed — `systemd` reported `status=203/EXEC`, `journalctl` showed the actual cause: `Permission denied` on `bin/linux-x86-64/sonar.sh`. `ls -la` confirmed it: `-rw-r--r--`, missing the executable bit — this specific release's zip archive didn't preserve Unix executable permissions on extraction (unlike the two previous downloads, which worked fine as-is). Fixed with `find .../bin .../elasticsearch/bin -type f -exec chmod +x {} \;` (broad, not just the one script, in case others were affected too), then `systemctl reset-failed` (needed — `Restart=always` had already hit systemd's start-rate limit after several automatic retry attempts) before starting again. **Lesson for future SonarQube version hops:** don't assume `unzip` preserves executable bits — verify or `chmod +x` proactively on `bin/` directories as a standard step, rather than reactively after a failed start.

**Hop 3 complete — final target reached.** Migration ran ~2 minutes (longest of the three hops, expected — largest schema delta). Fully verified: `GET /api/system/status` → `{"version":"26.9.0.129388","status":"UP"}`, nginx end-to-end confirmed `HTTP 200`, Zabbix Agent 2 continuously active throughout (1h31min uptime at check time, zero interruption across the entire multi-hour operation). Old install preserved intact at `/opt/ssd01/sonarq/sonarqube-26.1.0.118079/` for rollback.

## GITIN-1327 — all planned SonarQube/infra work complete

Full chain executed and verified end-to-end today (2026-09-05): SonarQube `9.9.3 → 24.12.0.100206 → 26.1.0.118079 → 26.9.0.129388`, OS `20.04 → 22.04.5 LTS`, Java `17 → 21` (via the correct `SONAR_JAVA_PATH` mechanism, after an initial `JAVA_HOME`-based attempt that didn't work), PostgreSQL `13.15 → 15.19`. Third-party repos (Zabbix ×3, Docker CE, Azure CLI) fixed and verified; `deadsnakes`/`python3.9` cleaned up; `get-fq.py` (unrelated data pipeline script sharing this host) fixed and confirmed working by the user; 24.04 explicitly dropped from scope.

**Remaining housekeeping (not urgent, no active risk):**
- Old PostgreSQL 13 cluster (`/opt/ssd01/postgresql/13/main`, stopped) — keep through a soak period before `pg_dropcluster 13 main`.
- Old SonarQube install directories (`sonarqube-9.9.3.79811/`, `sonarqube-9.6.1.59531/`, `sonarqube-24.12.0.100206/`, `sonarqube-26.1.0.118079/`) — safe to archive/remove once 26.9 has been observed stable for a while.
- `sonarqube-10/` (reported abandoned attempt) — never independently inspected in detail; low priority now that the real upgrade succeeded via a different path entirely.
- `scripts.sh` for this event — not yet created; the required fourth event file, still outstanding.

## PostgreSQL 13 → 15 upgrade in progress

Pre-check: PostgreSQL data directory is `/opt/ssd01/postgresql/13/main` (same disk as SonarQube's data, not the OS disk) — cluster `13/main`, port 5432, online. `pg_upgradecluster` (Debian/Ubuntu's purpose-built major-version-upgrade tool) is available via `postgresql-common`.

**Finding, unrelated to this upgrade:** the PGDG apt repo was found at `/etc/apt/sources.list.d/pgdg.list.disabled`, dated **2026-03-06** — disabled months before today, not something `do-release-upgrade` did. Content: `deb http://apt.postgresql.org/pub/repos/apt/ focal-pgdg main`. GPG key already present (`/etc/apt/trusted.gpg.d/apt.postgresql.org.gpg` → `postgresql-common`'s key). Fix: rename back to `.list`, repoint `focal-pgdg` → `jammy-pgdg`. Confirmed via `apt-cache policy` afterward: `postgresql-15` (15.19-1.pgdg22.04+2) now a real installable candidate.

**Migration completed (2026-09-05) via `pg_upgradecluster` — went cleanly, better than expected on the port question.** Sequence: fresh `pg_dump` backup → stopped `sonarqube.service` → `apt-get install postgresql-15` (auto-created an empty `15/main` on port 5433, as expected) → `pg_dropcluster 15 main --stop` (removed the auto-created empty one) → `pg_upgradecluster 13 main` (the real migration).

Result: **new `15/main` landed directly on port 5432** — no `sonar.properties` change needed, since that's exactly what its `jdbc.url` already expects. Old `13/main` automatically moved to port 5433, stopped, auto-start disabled, data directory intact at `/opt/ssd01/postgresql/13/main` (exactly matching the rollback plan — kept, not deleted). Verified the `sonarqube` database itself was genuinely migrated (not an empty schema): 21 projects, 102 tables, confirmed via direct `psql` query before restarting SonarQube.

`postgresql-common` package itself is still `260.pgdg20.04+1` (focal-built) — functioned fine for the upgrade, but worth a routine `apt upgrade` once convenient to pick up the jammy-native build.

**Old PG 13/main cluster:** per the rollback plan, keep it stopped-but-intact through a soak period before running `pg_dropcluster 13 main` — not done yet, intentionally.

**Decision: stop the OS-upgrade step at 22.04.5 LTS.** The `22.04 → 24.04` hop is dropped from this ticket's scope, not merely deferred-but-planned. If it's ever pursued later, `get-fq.py` should be containerized (Docker is already installed on this host) or otherwise decoupled from the system Python *before* that hop — recorded as a future, separate initiative, not a follow-up task of GITIN-1327.

**Lesson for future hosts/upgrades:** always get the actual per-package dpkg error from `/var/log/apt/term.log` (search for `dpkg: error processing archive ... (--unpack)` or `(--configure)`) before attempting any fix — the generic "Errors were encountered while processing: <list>" summary at the end of the run gives no root cause, and `apt-cache rdepends` only shows generic package-graph metadata, not what actually failed on this run.

**User requirement added:** Zabbix monitoring must keep working after every step. `sfcg-sonarqube` is already a monitored host on the shared Zabbix instance (`sf-monitoreo.smartfran.com`) — confirmed by the prior unrelated ticket `operations/events/20260720_sonarqube_disco_lleno/` (disk-space trigger on `/opt/ssd01`). Highest risk point: the OS upgrade (step 2) — `do-release-upgrade` can reconfigure/restart the Zabbix agent package, potentially resetting its config or interrupting reporting. Add a Zabbix-agent status check (`systemctl status zabbix-agent`/`zabbix-agent2`, confirm last-seen in Zabbix) to the verification step after each hop, and especially immediately after the OS upgrade.

Sources:
- https://docs.sonarsource.com/sonarqube-community-build/server-update-and-maintenance/update/determine-path
- https://community.sonarsource.com/t/upgrade-path-for-our-sonarqube-community-edition-9-9-3-instance/149250
- https://endoflife.date/sonarqube-community

## Open questions

- Final target version still needs a decision from the user (see "Upgrade path" section below) — the mandatory first hop (24.12.0.100206) isn't in question, but how far past it to go is.
- What `sonarqube-10/` actually is — a prior aborted upgrade attempt, or unrelated. Worth checking before assuming a clean upgrade path.
- Confirm the 9001/44639/32967 `java` processes are in fact SonarQube's Compute Engine/Search(Elasticsearch) sub-processes and not unrelated services.
- Backup/rollback plan before touching the running instance (DB dump, `/opt/ssd01/sonarq/sonarqube/data` snapshot, and a plan for reverting nginx/systemd if the new version fails to start).
- Minor/unrelated: `sonar.conf` and `sites-available/default` both declare `listen 80 default_server` — whether `default` is actually enabled (in `sites-enabled/`) isn't confirmed; if it is, that's a pre-existing nginx config ambiguity, not something introduced by this upgrade — flagged for awareness only, not pursued further here.

Noted but out of scope: two `code-*` processes on loopback ports (35553, 37119) are VS Code remote-tunnel/server processes, unrelated to SonarQube — not investigated further here.
