#!/usr/bin/env bash
# Event: 20261007_gitin2187-eslint-test
# Ejecutados por el usuario vía SSH en el host sonarqube-srv (solo lectura salvo escritura en /tmp y ~/.npm)

# === INVESTIGATION ===
# C1 — ESLint del proyecto (6.4.0) sobre api/, reporte JSON
# cd <ws>/dev-src-pedidos-platform/api && ./node_modules/.bin/eslint . -f json -o /tmp/eslint-platform-api.json
# C2 — Resumen del reporte (python3: totales, reglas más frecuentes, errores por regla, mensajes fatales)
# C3 — ESLint 8.57.1 vía binario cacheado de npx: node ~/.npm/_npx/<hash>/node_modules/eslint/bin/eslint.js . --parser-options=ecmaVersion:2022 -f json -o /tmp/eslint-platform-api-v8.json
# C4 — Resumen del reporte 8.x

# === JENKINS (sf-devops, cambios locales sin commit) ===
# C5 — Stage 'ESLint Report' + -Dsonar.eslint.reportPaths en develop/dev-src-pedidos-{concentrador,platform,backoffice}.jenkinsfile
# C6 — RUN_BUGS_REPORT (default false) + when-guard en develop/pruebas.jenkinsfile
# ⚠️ C7 — options { skipDefaultCheckout(true) } en los 6 jenkinsfiles de SF-PEDIDOS + commit/push a smartit-ar/sf-devops (main)
# ⚠️ C8 — Jenkins UI (pendiente): Definition → Pipeline script from SCM en cada job (repo sf-devops, rama */main, Script Path por job)

# === SONARQUBE / REPOS (solo lectura salvo indicación) ===
# C7 — Proyectos SonarQube de SmartPedidos (GET /api/projects/search) → data/sonar-smartpedidos-projects.tsv
# C8 — Líneas de código por lenguaje (GET /api/measures/component, ncloc_language_distribution) → data/sonar-ncloc-by-language.txt
# C9 — Comprobación del endpoint de badges sin token (SVG 'Project has not been found') → data/sonar-badge-check.txt
# ⚠️ C10 — README con sección Operaciones y badges (token de badge del proyecto) en Platform, Concentrador y Backoffice
# ⚠️ C11 — Dockerfile (npm@11.20.0, apk upgrade) y package.json (axios ~1.20.0, overrides) traídos de ope a develop en Platform y Concentrador
