## Resumen

Un scan de Trivy sobre la imagen `dev-src-pedidos-platform:develop` (generado 2026-09-03) detectó vulnerabilidades en las dependencias `tar` y `axios` de `platforms-service`, con hallazgos idénticos en sustancia a los de GITIN-2000 (concentrador-service): mismo `tar` desactualizado y mismo origen de `axios` desactualizado vía `@sendgrid/client`. Se aplicó el mismo `overrides` en `api/package.json` (rama `ope`) que en GITIN-2000: fija `tar` al tag `latest` y fuerza la resolución transitiva de `axios` al valor top-level. Ambas tareas son subtareas de GITIN-1306.

## Tabla resumen

| Campo | Valor |
|---|---|
| Ticket Jira | GITIN-2002 |
| Ticket padre | GITIN-1306 |
| Ticket hermano | GITIN-2000 (mismo fix, concentrador-service) |
| Componente | platforms-service |
| Severidad | Alta (1 CVE CRITICAL en tar, múltiples HIGH en tar/axios) |
| Detectado | 2026-09-03 (Trivy scan), recibido 2026-09-08 |
| Resuelto | Parcial — ver Acciones propuestas |
| Responsable | SRE |

## Origen

Trivy scan sobre `dev-src-pedidos-platform:develop`, generado 2026-09-03. Reporte completo persistido en `data/trivy_scan.zip` / `data/trivy_vuln.json`.

## Hallazgos

| # | Hallazgo | Riesgo |
|---|---|---|
| H1 | `tar` instalado en `6.2.1` (transitiva a la app), 9 CVEs (1 CRITICAL — DoS por gzip bomb; 8 HIGH). Fix máximo requerido: `7.5.21`. El override aplicado (`tar: "latest"`) resuelve por completo el uso de `tar` en el árbol de dependencias **de la propia aplicación**, y evita un nuevo ticket por cada CVE futura de `tar`. | Alto (resuelto, alcance app) |
| H2 | `axios` instalado en dos versiones distintas: `0.26.1` (transitiva, vía `@sendgrid/client@^7.7.0`, que declara `axios: ^0.26.0` — mismo origen confirmado en GITIN-2000) y `1.13.6` (vía el rango directo `~1.13.5`). Cada una con ~10 CVEs HIGH propios. **Confirmado por el scan posterior (2026-09-08 14:21, `data/trivy_vuln.json`)**: solo queda reportada la versión `1.13.6` — la duplicada `0.26.1` desapareció, el override funciona como se esperaba. | Alto (parcialmente resuelto) |
| H3 | El override aplicado (`axios: "$axios"`) solo fuerza la resolución de `@sendgrid/client` a coincidir con el valor top-level (`~1.13.5`) — no eleva ese techo. Las CVEs que requieren `1.15.1`–`1.16.0` quedan sin resolver tras este cambio, mismo estado que GITIN-2000. El análisis de impacto de subir a `1.16.0` (ver GITIN-2000 → `data/axios-1160-impact-analysis.md`) se hizo sobre el código fuente de concentrador-service — **todavía no se repitió sobre el código de platforms-service**, por lo que acá la viabilidad de esa actualización sigue sin confirmarse específicamente para este servicio. | Medio — pendiente de decisión y de análisis propio |
| H4 | **Confirmado, mismo mecanismo que GITIN-2000**: además de `tar`, el scan reporta `brace-expansion`, `cross-spawn`, `glob`, `ip-address`, `minimatch`, `pacote` y `sigstore` con CVEs HIGH. Verificado vía `PkgPath` en `data/trivy_vuln.json`: todos viven en `/usr/local/lib/node_modules/npm/node_modules/...` — parte de la instalación interna de npm empaquetada en `node:20.20-alpine`, no del árbol de dependencias de la aplicación. Ver GITIN-2000 para el detalle completo de por qué actualizar la imagen base o npm no cierra esto de forma limpia; se evalúa documentar como riesgo residual aceptado. | Medio — decisión pendiente |
| H5 | **Hallazgo propio de este servicio, no presente en GITIN-2000**: el scan reporta además `express-jwt@5.3.3` (fix `6.0.0`), `jsonwebtoken@8.5.1` (fix `9.0.0`) y `lodash.set@4.3.2` (sin fix publicado por sus autores). Los primeros dos exigen un salto de versión mayor con cambio de superficie de API (no una simple actualización de versión) y requieren revisión de código antes de aplicarse. `lodash.set` no tiene corrección disponible en absoluto — la única solución real es dejar de depender de él (identificar y reemplazar lo que lo trae de forma transitiva). Ninguno de los tres fue abordado en este ticket. | Medio — pendiente, alcance mayor al de este ticket |
| H6 | Se detectó un cambio adicional en `api/Dockerfile` en la misma rama (`apk update && apk upgrade` antes de `apk add ca-certificates`), sin respaldo en el reporte de Trivy — ninguno de los dos reportes (GITIN-2000 ni GITIN-2002) incluye un target de paquetes del sistema operativo. Se recomienda excluir este cambio del alcance de este ticket: aborda una superficie distinta (paquetes OS de Alpine, no dependencias npm) y un `apk upgrade` sin versión fijada compromete la reproducibilidad del build. Si se busca endurecimiento a nivel de OS, debería ser un ticket propio respaldado por un scan de Trivy en modo imagen completa. | Bajo — decisión pendiente del usuario |

## Recursos afectados

| Componente | Impacto |
|---|---|
| platforms-service | `api/package.json` — override de `tar`/`axios` aplicado en rama `ope`; upgrade completo de `axios` pendiente de decisión; cambio de Dockerfile pendiente de resolución (ver H4) |
| concentrador-service | No afectado por este ticket — ver GITIN-2000 para su propio fix |

## Comandos ejecutados

| # | Comando / Script | Propósito |
|---|---|---|
| C1 | Extracción y análisis del reporte de Trivy (`data/trivy_vuln.json`) + verificación de `@sendgrid/mail`/`axios` en `api/package.json` | Confirmar hallazgos y origen de la dependencia vulnerable |

## Acciones propuestas

1. Mantener el override aplicado en `api/package.json` (rama `ope`) — resuelve `tar` por completo (Dev).
2. Decidir si el upgrade de `dependencies.axios` a `1.16.0` (o superior) se trata en este ticket o en uno de seguimiento — mismo estado pendiente que GITIN-2000 (Dev/SRE).
3. Resolver el cambio de `api/Dockerfile` (H4) por separado del alcance de este ticket — no está respaldado por evidencia de Trivy (SRE).

## Hallazgos secundarios

Ninguno.
