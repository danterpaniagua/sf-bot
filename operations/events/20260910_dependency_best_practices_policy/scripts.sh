#!/usr/bin/env bash
# Event: 20260910_dependency_best_practices_policy
# Commands are grouped by phase: Investigation / Audit
# Read-only throughout — no state-changing commands in this event.

# === INVESTIGATION ===

# C1 — locate every npm/NuGet manifest across the local read-only repo clones
find /home/dpaniagua/Documentos/git/bots/smartpedidos/repo -iname "package.json" -not -path "*/node_modules/*"
find /home/dpaniagua/Documentos/git/bots/loyalty/repo -iname "*.csproj" -o -iname "packages.config"
find /home/dpaniagua/Documentos/git/bots/cloud/repo -iname "*.csproj" -o -iname "packages.config"

# C2 — extract npm dependencies (name + version) from each SmartPedidos package.json
python3 -c "
import json
d = json.load(open('<package.json path>'))
for k, v in sorted(d.get('dependencies', {}).items()):
    print(k, v)
"

# C3 — extract unique NuGet packages from SmartLoyalty packages.config files (.NET Framework)
find /home/dpaniagua/Documentos/git/bots/loyalty/repo/dev-src-sol-smartloyalty -iname "packages.config" -exec cat {} \; \
  | grep -oE '<package id="[^"]*" version="[^"]*"' \
  | sed -E 's/<package id="([^"]*)" version="([^"]*)"/\1 \2/' \
  | sort -u

# C4 — extract unique NuGet PackageReference entries from SmartFran Cloud .csproj files (SDK-style)
find /home/dpaniagua/Documentos/git/bots/cloud/repo/SmartFran.Cloud -iname "*.csproj" -exec cat {} \; \
  | grep -oE '<PackageReference Include="[^"]*" Version="[^"]*"' \
  | sed -E 's/<PackageReference Include="([^"]*)" Version="([^"]*)"/\1 \2/' \
  | sort -u

# === AUDIT ===

# C5 — confirm whether any existing CI/CD pipeline already runs dependency/license scanning
grep -rliE "trivy|snyk|socket\.dev|dependabot" /home/dpaniagua/Documentos/git/bots/cloud/repo/SmartFran.Cloud/.github/
find /home/dpaniagua/Documentos/git/bots/*/repo -iname "dependabot.yml" -o -iname "renovate.json"
grep -iE "trivy|snyk|socket|dependabot|npm audit" \
  /home/dpaniagua/Documentos/git/bots/smartpedidos/repo/dev-src-smartPedidos-backOffice/Jenkinsfile \
  /home/dpaniagua/Documentos/git/bots/smartpedidos/repo/dev-src-smartPedidos-concentradorService/Jenkinsfile
# OUTPUT (2026-09-10): zero matches across every check above — no dependency/license
# scanning tool wired into any pipeline in any of the three projects, and no
# dependabot.yml/renovate.json in any repo clone.

# C6 — verify license/deprecation/maintenance-status claims against authoritative sources
# (npm registry API for querystring/xlsx; web search for AutoMapper/EPPlus/iTextSharp
# licensing changes and Moment.js maintenance-mode status — see investigation.md for
# the confirmed facts and their sources)
curl -s https://registry.npmjs.org/querystring
curl -s https://registry.npmjs.org/xlsx
