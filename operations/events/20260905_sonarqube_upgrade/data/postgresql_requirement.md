Sources:
- https://community.sonarsource.com/t/postgresql-compatibility-for-sonarqube-upgrade-from-9-9-3-to-25-4/145051
- https://docs.sonarsource.com/sonarqube-community-build/server-update-and-maintenance/release-notes
- https://community.sonarsource.com/t/sonar-comunity-edition-supports-postgres-17-7-database-or-not/154025

Findings:
- Up through 24.12.0.100206, PostgreSQL 12.7 (and by extension the host's current 13.15) remains compatible — no DB change needed for hop 1.
- As of 25.1.0.102122, PostgreSQL 11 support was dropped; supported range became 13-17. Host's current 13.15 is still fine at this stage.
- Later in the 25.x/26.x line, the supported floor moved again: 13 was dropped (range became 14-18), then 14 was dropped (range became 15-18, current as of the latest checked release notes).
- Net result for this host: PostgreSQL 13.15 will stop being supported partway through the 25.x/26.x line and MUST be upgraded to at least PostgreSQL 15 before reaching the 26.1.0.118079 hop (confirmed 26.x range is 15-18).
- Exact SonarQube build number where each PostgreSQL floor bump took effect (13 dropped, then 14 dropped) not pinned down precisely — recommend re-checking each specific release's upgrade notes (24.12, 26.1) immediately before executing, since community/release-notes pages get updated.
- Community best-practice cited: do the PostgreSQL major-version upgrade DURING one of the SonarQube version hops rather than as a separate standalone step, to minimize total downtime/maintenance windows.
