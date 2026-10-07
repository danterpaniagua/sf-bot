#!/usr/bin/env bash
# Event: 20261007_gitin2194-checkutc-propuesta
# Solo lectura. Salidas en data/.

# === INVESTIGATION ===
# C1 — Offsets actuales por zona IANA con Node local (Intl longOffset) + versión de tzdata → data/tzdata-offsets-check.txt
# node -e '<const z={Argentina:"America/Argentina/Buenos_Aires",Peru:"America/Lima",Uruguay:"America/Montevideo",Paraguay:"America/Asuncion",Chile:"America/Santiago"}; imprime offsets y process.versions.tz>'
# C2 — Versión de Node y tzdata de la imagen de producción → data/tzdata-container-check.txt
# docker run --rm node:20.20-alpine node -e 'console.log("node",process.version,"tzdata",process.versions.tz)'

# === GRAYLOG (solo lectura; API http://sf-monitoreo.smartfran.com:9000, token en $SML_GRAYLOG_API_KEY / $GRAYLOG_API_KEY) ===
# C3 — Comprobación de acceso a la API: curl -u "<token>:token" http://sf-monitoreo.smartfran.com:9000/api/system → data/graylog-direct-auth-check.txt (http=200)
# C4 — Búsqueda legacy (CSV) de 30 días: query=checkUTC, fields=timestamp,source,message → data/graylog-checkutc-executions.json (es CSV)
#      curl -sS -G -u "<token>:token" http://sf-monitoreo.smartfran.com:9000/api/search/universal/relative --data-urlencode 'query=checkUTC' --data-urlencode 'range=2592000' --data-urlencode 'limit=500' --data-urlencode 'fields=timestamp,source,message'
# C5 — Misma búsqueda con query=timezonedb → data/graylog-timezonedb-all.csv (solo las mismas 43 ejecuciones; sin líneas de error de la API)
# C6 — Resúmenes (Python, local): data/graylog-checkutc-summary.txt, data/graylog-timezonedb-summary.txt
