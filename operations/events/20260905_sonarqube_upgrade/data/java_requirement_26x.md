Sources:
- https://community.sonarsource.com/t/sonarqube-community-build-26-2-0-119303-released/177334
- https://docs.sonarsource.com/sonarqube-community-build/server-installation/server-host-requirements

Finding: since the January 2026 release (26.1.x onward), SonarQube Community Build's server runtime requires a full **JDK 21 or 25** (a JRE alone is no longer sufficient) for ZIP-file installations. This is a hard blocker for our path: the host currently has OpenJDK 17.0.15 (need to confirm whether it's a JDK or JRE-only package) — must upgrade to JDK 21/25 before reaching 26.1.0.118079 (our revised second hop) or 26.9.0.129388 (final target). 24.12.0.100206 (first hop) still runs fine on the existing Java 17.

Also confirmed general host requirements (server-host-requirements page):
- Small-scale (up to 1M LOC): 4GB RAM min, 2 CPU cores, 30GB disk, 10% free disk space minimum.
- Large-scale (up to 50M LOC): 16GB RAM, 8 CPU cores.
- Elasticsearch-related Linux prerequisites (vm.max_map_count etc.) must be satisfiable on the host OS — explicitly NOT supported on Azure App Service, AWS App Runner, AWS Fargate. Our host is a plain Azure VM (Ubuntu), so this restriction doesn't apply, but the actual vm.max_map_count/ulimit values on sfcg-sonarqube haven't been checked yet against current requirements.
- PostgreSQL version requirement for 26.x not yet confirmed (page fetch didn't surface it) — still need to check against the current 13.15 on this host.
