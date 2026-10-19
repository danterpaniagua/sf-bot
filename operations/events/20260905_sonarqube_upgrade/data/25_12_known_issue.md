Sources:
- https://community.sonarsource.com/t/sonarqube-community-build-25-12-0-117093-released/153805
- https://community.sonarsource.com/t/sonarqube-community-build-26-1-0-118079-released/172488
- https://community.sonarsource.com/t/elactissearch-error-on-upgrade-to-sonarqube-25-12-0-117093-community/180823
- https://community.sonarsource.com/t/upgrade-to-sonarqube-community-build-version-from-25-12-to-26-5-0-is-failing/183637

Finding: SonarQube Community Build 25.12.0.117093 has a known database-migration bug. The following 26.1.0.118079 release notes state it resolves "issues with database migrations that some users encountered when updating to version 25.12.0.117093." Because of this, 26.1.0.118079 is documented as usable as a substitute intermediate version instead of 25.12.0.117093 when it would otherwise be a required hop.

Corroborating reports of real failures on 25.12.0.117093:
- "ElasticSearch error on upgrade to sonarqube:25.12.0.117093-community" (community thread)
- "Upgrade to Sonarqube community build version from 25.12 to 26.5.0 is failing" (community thread) — a different downstream failure, but reinforces that 25.12 is a rough version to sit on mid-upgrade.

Separate, unrelated note also surfaced from the 25.12 release notes: Java 17 is deprecated as a supported *scanner* runtime starting this release; scanner-side support ends July 2026 (Java 21+ required going forward for scanners). This is about the analysis scanner client, not necessarily the SonarQube server JVM itself — relevant to check separately for the 26.9 server-side Java requirement, not yet confirmed.

Recommendation: substitute 26.1.0.118079 for 25.12.0.117093 as the year-boundary bridge hop.
