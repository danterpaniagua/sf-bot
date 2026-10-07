# 20260908_gitin2014-sonar-masked-asterisks

**Tags:** Operaciones, SEGURIDAD, SRE

## Resumen

En SonarQube (`sfcg-sonarqube`), el contenido de ciertos archivos aparecía completamente reemplazado por asteriscos tanto en la vista de código como en la API de fuente cruda, sin causa conocida al momento de abrir el ticket — no había forma de saber si era un bug del visor, un problema de renderizado, o comportamiento esperado. Se confirmó que es una funcionalidad nueva de detección de secretos, introducida en la versión exacta a la que se actualizó esta instancia días atrás — no es un bug ni un problema a corregir en SonarQube.

## Tabla resumen

| Campo | Valor |
|---|---|
| Ticket Jira | [GITIN-2014](https://smartit-ar.atlassian.net/browse/GITIN-2014) |
| ID alerta | N/A |
| Sistema | SonarQube (`sfcg-sonarqube.smartfran.com`), Community Edition 26.9.0.129388 |
| Severidad | Baja — comportamiento esperado, no una falla |
| Detectado | 2026-09-08 |
| Resuelto | Sí — causa raíz confirmada (comportamiento esperado de la versión 26.9.0.129388), ambos secretos puntuales identificados (`development.js` ya trackeado, `branch.js` identificado en esta sesión). Mecanismo exacto de persistencia tras re-análisis y corrección de hostname en documentación quedan como seguimiento, no bloquean el cierre |
| Responsable | SRE |

## Causa raíz

La versión 26.9.0.129388 de SonarQube (a la que esta instancia se actualizó el 2026-09-05) introdujo el enmascarado de valores de secretos detectados en las respuestas de su Web API: el rango detectado se reemplaza por `*` en las vistas de código fuente y en las respuestas de la API, preservando el largo del texto original; cuando no puede determinar una ubicación segura, enmascara la línea completa o el archivo entero. Confirmado contra las release notes oficiales de SonarSource. No es un bug — es la herramienta rechazando mostrar contenido que detecta como secreto.

## Hallazgos

| # | Hallazgo | Riesgo |
|---|---|---|
| H1 | `development.js` enmascarado — explicado en su totalidad: contiene credenciales reales hardcodeadas (Mongo Atlas, AWS, token estático), ya documentadas en `smartpedidos/events/20260720_credenciales-mongodb-hardcodeadas/` | Resuelto — hallazgo ya trackeado en otro ticket |
| H2 | `branch.js` también enmascarado — secreto puntual identificado: `branch.js:3755`/`:3776` (duplicado en el bloque de log de error) hardcodea un par de credenciales Basic Auth (`username`/`password`) usado para autenticar contra la integración de la plataforma de delivery "Toque" (`case 11` de `branchRejectOrder`). Ninguno de los dos campos aparece en Hotspots ni en Issues de tipo Vulnerability — el motor de detección de secretos que dispara el enmascarado opera independiente de ese sistema | Medio — credencial real hardcodeada, aunque de valor débil/adivinable |
| H3 | El runbook de operaciones (`sonarqube_upgrade_runbook.md`) y la config de nginx en el host referencian el hostname `sf-sonarqube.smartfran.com`, pero el hostname real configurado en el propio SonarQube (`sonar.core.serverBaseURL`) es `sfcg-sonarqube.smartfran.com` — causó un `HTTP_STATUS:000` real durante esta investigación | Bajo — desprolijidad de documentación, no afecta el servicio |
| H4 | Un token de tipo "Global" (Analysis Token) devuelve `403` contra `api/sources/raw` — ese tipo de token solo tiene permiso de "Execute Analysis", no de "Browse"/"See Source Code" | Resuelto — se identificó el tipo de token correcto (User Token) |

## Recursos afectados

| Componente | Impacto |
|---|---|
| SonarQube (`sfcg-sonarqube`) | Ninguno — comportamiento nuevo esperado tras la actualización a 26.9.0.129388 |
| `concentrador-service` | Dos archivos (`development.js`, `branch.js`) muestran contenido enmascarado en SonarQube — no bloquea el análisis ni el reporte de otros hallazgos (Bugs) sobre esos mismos archivos, que se revisaron normalmente durante esta misma sesión |

## Comandos ejecutados

| # | Comando / Script | Propósito |
|---|---|---|
| C1 | `curl api/system/info` | Confirmar versión de SonarQube y hostname real configurado |
| C2 | `ssh ... grep web.log/ce.log` | Buscar actividad de enmascarado en logs — sin resultados, descartado como vía de diagnóstico |
| C3 | `curl api/sources/raw` (×3: `development.js`, `branch.js`, `country.js`) | Confirmar si el enmascarado ocurre en la API cruda (server-side) o solo en el visor (client-side), y si es por-archivo o global al proyecto |
| C4 | `curl api/hotspots/search` / `api/issues/search?types=VULNERABILITY` sobre `branch.js` | Buscar el hallazgo puntual que dispara el enmascarado — sin resultados |
| C5 | `ssh ... cat /etc/nginx/conf.d/sonar.conf` | Descartar enmascarado a nivel de proxy/WAF |
| C6 | ⚠️ `curl api/settings/set key=sonar.text.activate value=false` (global) | Prueba: desactivar detección de secretos para verificar si el enmascarado se revierte tras un nuevo análisis |
| C7 | `curl api/sources/raw` sobre `development.js`, post re-análisis | Verificar resultado de la prueba — el archivo siguió enmascarado (`HTTP_STATUS:200`, contenido idéntico en asteriscos) |
| C8 | ⚠️ `curl api/settings/reset keys=sonar.text.activate` (global) | Revertir la prueba — confirmado `HTTP_STATUS:204` |

## Acciones propuestas

Ticket cerrado — causa raíz confirmada y ambos secretos puntuales identificados. Los siguientes puntos quedan como seguimiento, no bloquean el cierre:

1. (Dev) Sacar del código fuente la credencial Basic Auth hardcodeada de la integración "Toque" (`branch.js:3755`, introducida en el commit `1d2d2546d`, 2026-06-26; y `branch.js:3776`, duplicada en el bloque de log de error, commit `4ba1b3227`, 2026-02-18 — anterior a la de la línea 3755). Evaluar si corresponde agregarla como hallazgo adicional en `20260720_credenciales-mongodb-hardcodeadas` o abrir un ticket propio.
2. (SRE) Corregir el hostname desactualizado (`sf-sonarqube.smartfran.com` → `sfcg-sonarqube.smartfran.com`) en `sonarqube_upgrade_runbook.md` y en la config de nginx del host.
3. (SRE/Dev) Sin acción sobre `development.js` en este ticket — su remediación ya está trackeada en `20260720_credenciales-mongodb-hardcodeadas` (SEC-103/SEC-114).
4. Comunicar al equipo que este enmascarado es esperado, no un bug de SonarQube, para evitar que se reporte de nuevo como incidente.
5. (SRE, opcional) Entender por qué desactivar la detección y re-analizar no revirtió el enmascarado (probar con un cambio real de contenido, o consultar con soporte de SonarSource) — no bloqueante, la causa raíz de fondo ya está confirmada y documentada.

## Hallazgos secundarios

Ninguno adicional al alcance de este ticket.
