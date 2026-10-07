# 20260908_gitin2011-ope-jenkins-scope

**Tags:** SmartPedidos, Jenkins, Concentrador, Platform, SRE

## Resumen

Antes de esta tarea, la rama `ope` de los repositorios `dev-src-smartPedidos-concentradorService` y `dev-scr-smartPedidos-platformsService` no contaba con ningún job de Jenkins asociado en `sf-devops` (solo existían el scope `develop`, con pipeline completo, y `stg`, vacío) — no había forma automatizada de verificar, mediante un escaneo real de la imagen construida, si las correcciones de dependencias aplicadas en GITIN-2000/GITIN-2002 (upgrade de `axios`/`tar`) efectivamente eliminaban las vulnerabilidades reportadas. Se creó un nuevo scope `ope` con un pipeline reducido, enfocado exclusivamente en ese escaneo (Trivy).

## Tabla resumen

| Campo | Valor |
|---|---|
| Ticket Jira | [GITIN-2011](https://smartit-ar.atlassian.net/browse/GITIN-2011), parent [GITIN-1857](https://smartit-ar.atlassian.net/browse/GITIN-1857) |
| ID alerta | N/A — mejora de tooling, no incidente |
| Sistema | Jenkins (`sf-devops`) — SF-PEDIDOS, jobs `ope` para Concentrador y Platform |
| Severidad | Baja |
| Detectado | 2026-09-08 |
| Resuelto | Sí, 2026-09-08 — alcance cumplido (pipeline `ope` creado y verificado con Trivy); activación automática vía webhook y commit de los archivos quedan como seguimiento, no bloquean el cierre |
| Responsable | SRE |

## Causa raíz

La rama `ope` no tenía ningún Jenkinsfile asociado. Los únicos scopes existentes eran `develop` (pipeline completo, 8 stages) y `stg` (directorio vacío, sin jenkinsfiles). Sin un pipeline propio, no existía manera de correr un escaneo de vulnerabilidades sobre la imagen Docker construida específicamente desde esa rama.

## Hallazgos

| # | Hallazgo | Riesgo |
|---|---|---|
| H1 | Pipelines `ope` creados para Concentrador y Platform, con alcance intencionalmente reducido a 3 stages (Cloning Repo, Docker Build, Test with Trivy) — no busca paridad con los 8 stages de `develop` (Bugs Report, Changelog, NPM install, Sonarqube, Quality Gate quedan fuera de alcance) | Bajo |
| H2 | El token del `GenericTrigger` sigue como placeholder (`REPLACE_WITH_NEW_GENERIC_WEBHOOK_TOKEN`) en ambos Jenkinsfiles — el disparo automático por push/PR a `ope` no puede funcionar hasta generar un token dedicado y no reutilizar el de `develop` | Medio — bloquea la activación automática; no afecta las corridas manuales ya realizadas |
| H3 | No se confirmó si el webhook de GitHub de ambos repositorios tiene habilitado el evento "Pull requests" además de "push" — sin eso, la mitad del trigger basada en PR no se dispararía aunque el token se resuelva | Bajo — pendiente de verificar |
| H4 | Ambos Jenkinsfiles de `ope` están sin versionar en `sf-devops` (`git status` los muestra como untracked) | Bajo |

## Recursos afectados

| Componente | Impacto |
|---|---|
| Jenkins (`sf-devops`, SF-PEDIDOS) | Nuevo scope `ope` agregado — 2 jobs (Concentrador, Platform) |
| Concentrador | Imágenes Docker de la rama `ope` ahora escaneadas con Trivy |
| Platform | Ídem |

## Comandos ejecutados

No aplica — el trabajo consistió en la creación de los dos archivos Jenkinsfile (no en comandos o scripts ejecutados y capturados en este ticket). Las corridas de prueba que produjeron los reportes de Trivy se realizaron directamente en la interfaz de Jenkins.

## Acciones propuestas

Ticket cerrado — el objetivo (verificación puntual vía Trivy del post-upgrade de GITIN-2000/GITIN-2002) ya se cumplió con las corridas manuales. Los siguientes puntos quedan como seguimiento, no bloquean el cierre:

1. (SRE) Generar un token dedicado para el webhook de GitHub del scope `ope` (Concentrador y Platform) y reemplazar el placeholder en ambos Jenkinsfiles — no reutilizar el token de `develop`.
2. (SRE) Confirmar que el webhook de GitHub de ambos repositorios tiene habilitado el evento "Pull requests" además de "push".
3. (SRE) Commitear los dos Jenkinsfiles de `ope` en `sf-devops` — actualmente sin versionar.

## Hallazgos secundarios

- El scope `stg` existe como directorio en `sf-devops/jenkins/SF-PEDIDOS/jenkinsfiles/` pero está vacío, sin jenkinsfiles — no forma parte de este ticket, mencionado solo por ser un directorio hermano en la misma ubicación.
