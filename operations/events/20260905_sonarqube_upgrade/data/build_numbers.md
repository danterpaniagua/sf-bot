Sources:
- https://docs.sonarsource.com/sonarqube-community-build/server-update-and-maintenance/release-notes
- https://community.sonarsource.com/t/sonarqube-community-build-24-12-0-100206-released/131515
- https://community.sonarsource.com/t/sonarqube-community-build-25-12-0-117093-released (implied by build number)
- https://community.sonarsource.com/t/sonarqube-community-build-26-1-0-118079-released/172488

Confirmed exact build numbers for the decided upgrade path:

| Hop | Version | Full build |
|---|---|---|
| 1 (mandatory bridge) | 24.12 | 24.12.0.100206 |
| 2 (year-boundary bridge) | 25.12 | 25.12.0.117093 |
| 3 (final target) | 26.9 | 26.9.0.129388 |

26.9.0.129388 confirmed as the current latest Community Build release (per the docs' release-notes page "Latest release" listing).

Open risk (from an earlier general search, not yet independently verified against the 25.12 release-notes/changelog page itself): a prior search result mentioned "known issues in the December 2025 release (25.12.0.117093)" serious enough that some guidance suggested using the January 2026 build (26.1.0.118079) as a substitute intermediate hop instead. Not yet confirmed what the issue actually is or whether it affects a transient upgrade-through (vs. staying on 25.12 long-term). Needs a direct check of the 25.12.0.117093 release-notes/changelog before executing the real upgrade.
