# Eventos — GITIN-2000

## 2026-09-08 09:31 — Apertura del ticket

He abierto el ticket a partir de un cambio propuesto en `api/package.json` de `concentrador-service` (bloque `overrides` para `tar` y `axios`), motivado por un scan de Trivy.

## 2026-09-08 09:50 — Análisis del reporte de Trivy

He recibido y persistido el reporte de Trivy (`data/trivy_scan.zip`, `data/trivy_vuln.json`). He confirmado que el override de `tar` (`^7.5.21`) resuelve las 9 CVEs encontradas (1 CRITICAL, 8 HIGH). He confirmado que el override de `axios` (`"$axios"`) solo resuelve 2 de las ~10 CVEs HIGH encontradas, ya que fuerza la resolución transitiva al valor top-level (`~1.13.5`) sin elevarlo — las CVEs que requieren `1.15.1`–`1.16.0` quedan abiertas.

## 2026-09-08 10:05 — Verificación del origen de la dependencia axios

He verificado contra el registro de npm que `mongoose@7.8.7` y todo su subárbol de dependencias no referencian `axios` en ningún punto — descarto la hipótesis inicial de que `mongoose` fijaba esa versión. He confirmado que el único consumidor de `axios` en el árbol, además del código propio, es `@sendgrid/client@^7.7.0` (declara `axios: ^0.26.0`), consistente con la versión `0.26.1` detectada por Trivy.

## 2026-09-08 10:20 — Análisis de impacto de actualizar axios a 1.16.0

He revisado el código fuente de `concentrador-service` (~85 call sites en `branch.js`, más usos puntuales en otros cuatro archivos) y he contrastado los cambios de comportamiento documentados por axios entre `1.14.0` y `1.16.0` contra los patrones de uso reales. No he encontrado incompatibilidades conocidas: no hay proxy configurado, no hay URLs con credenciales embebidas, no se usa el adaptador fetch, y los headers solo contienen tokens Bearer opacos o strings estáticos. Persisto el detalle completo en `data/axios-1160-impact-analysis.md` y actualizo `investigation.md` y `ops.md` con el hallazgo.

## 2026-09-08 14:55 — Confirmación post-fix con un nuevo scan de Trivy

He confirmado, con un nuevo scan de Trivy sobre la rama `ope` (14:53), que el override de `axios` funciona como esperaba: solo queda reportada la versión `1.13.6`, la duplicada `0.26.1` desapareció. He seguido encontrando `tar` con sus 9 CVEs originales, junto con nuevos hallazgos en `brace-expansion`, `cross-spawn`, `glob`, `ip-address`, `minimatch`, `pacote` y `sigstore`. He verificado, vía el campo `PkgPath` del reporte, que todos viven en `/usr/local/lib/node_modules/npm/node_modules/...` — la instalación interna de npm empaquetada en la imagen base `node:20.20-alpine`, no el árbol de dependencias de la aplicación. He persistido el reporte en `data/trivy_vuln_ope_20260908_1453.txt`.

## 2026-09-08 15:05 — Evaluación de imagen base como posible mitigación

He verificado, contra el índice oficial de releases de Node.js y las versiones de npm publicadas en el registro, que Node 20.x empaqueta npm `10.8.2` de forma fija en toda la línea LTS (mismo `tar ^6.2.1` vulnerable en cualquier tag). Node 22 empaqueta npm `10.9.8` (`tar ^7.5.11`, todavía insuficiente) y Node 24 empaqueta npm `11.19.0` (`tar ^7.5.19`, resuelve la CVE CRITICAL pero deja una HIGH abierta). He concluido que ninguna opción cierra esto con solo un cambio de tag de imagen — requeriría un salto de versión mayor de Node, con su propio riesgo de compatibilidad. He actualizado `investigation.md` con esta comparación.

## 2026-09-08 15:20 — Comunicación a PM y nuevo comando de status report

He redactado un correo detallado y uno de estado corto para PM, cubriendo GITIN-2000 y GITIN-2002 de forma consolidada, incluyendo la corrección del hallazgo crítico (alcance app vs. herramienta interna del entorno) y la aclaración de que la actualización de axios a `1.16.0` es viable pero requiere revisión de impacto de código antes de aplicarse. He creado el comando cross-project `/status-report` (`​.claude/commands/status-report.md`) para reutilizar este formato corto en futuros tickets de cualquier proyecto.
