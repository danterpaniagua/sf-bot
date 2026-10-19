Source: https://docs.sonarsource.com/sonarqube-community-build/server-update-and-maintenance/update/determine-path
(pasted directly from the official "Update path examples" table)

| From version | To version | Update path |
|---|---|---|
| 25.10.0.x | 26.1.0.x | 25.10.0.x > 26.1.0.x (direct) |
| 25.3.0.x | 25.9.0.x | 25.3.0.x > 25.9.0.x (direct) |
| 25.9.0.x | 26.3.0.x | 25.9.0.x > 25.12.0.x > 26.3.0.x (one intermediate step) |
| 10.6 | 25.4.0.x | 10.6 > 24.12.0.100206 > 25.4.0.x (one intermediate step) |
| 9.9 LTA (Community Edition) | 25.4.0.x | 9.9 LTA > 24.12.0.100206 > 25.4.0.x (one intermediate step) |
| 8.9 LTA (Community Edition) | 25.4.0.x | 8.9 LTA > 9.9 LTA > 24.12.0.100206 > 25.4.0.x (two intermediate steps) |

Pattern observed: any pre-2024 (edition-based-versioning) source requires a stop at 24.12.0.100206 before reaching a 2025+ release. Crossing a calendar-year boundary within the new CalVer scheme (e.g. 25.9 -> 26.3) requires a stop at that December's release (25.12.0.x) first.

Additional note pasted from the same docs page: "After 10.7, Community Edition has been renamed to Community Build with a new versioning scheme." Confirms the rename cutover point is version 10.7 specifically.
