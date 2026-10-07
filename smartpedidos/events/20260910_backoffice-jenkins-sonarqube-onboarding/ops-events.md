# Eventos — 20260910_backoffice-jenkins-sonarqube-onboarding

## 2026-09-10 10:00 — Relevamiento de la estructura Jenkins existente

He revisado `sf-devops/jenkins/SF-PEDIDOS/smartpedidos.md` y los jenkinsfiles de Concentrador y Platform (`jenkinsfiles/develop/`) como referencia. He confirmado que ninguno de los dos incluye una etapa de deploy — ambos terminan en Trivy + notificación a Google Chat. También he revisado el `Jenkinsfile` propio del repo `dev-src-smartPedidos-backOffice` (en `develop`) y he encontrado marcadores de conflicto de merge sin resolver (`<<<<<<< HEAD` / `=======` / `>>>>>>> master`) comprometidos en el archivo — lo he descartado como plantilla, usándolo solo como referencia para los buckets S3 y distribution IDs de CloudFront.

## 2026-09-10 10:30 — Creación del nuevo pipeline para backOffice

He creado `sf-devops/jenkins/SF-PEDIDOS/jenkinsfiles/develop/dev-src-pedidos-backoffice.jenkinsfile`, basado en la plantilla de Concentrador (la más actualizada), adaptado para: sin etapa de Docker Build (backOffice despliega a S3/CloudFront, no a ECS), rutas apuntando a `app/` en vez de `api/`, `SONAR_POJECT_NAME = "DEVELOP.SmartPedidos.BackOffice"`, y un token de `GenericTrigger` nuevo generado con `openssl rand -hex 32`.

## 2026-09-10 10:45 — Ajuste de Trivy a filesystem scan

He cambiado la etapa Trivy de `trivy image` (no aplica, no se construye imagen) a `trivy fs` contra `./app`, inicialmente con `--scanners vuln`. He agregado `secret` (`--scanners vuln,secret`) dado que backOffice es una SPA con más superficie de exposición accidental de credenciales que un servicio backend.

## 2026-09-10 11:00 — Primer run real en Jenkins — falla en NPM install

Se pegó el log de la primera ejecución real del job (`SF-Pedidos/develop/dev-src-smartpedidos-backoffice`), persistido en `data/jenkins_build_log_first_run_failed.txt`. He confirmado que el job no estaba ejecutando el archivo corregido, sino un borrador con rutas `api/` (inexistentes en backOffice) y `SONAR_CRED_ID` mal configurado con el project key en lugar del credential ID. El fallo (`cd: can't cd to api/`) ocurrió en la etapa NPM install, y todas las etapas posteriores (Sonar, Docker Build, Quality Gate, Trivy) se saltearon en cascada.

## 2026-09-10 11:15 — Proyecto SonarQube creado

Se creó el proyecto SonarQube `DEVELOP.SmartPedidos.BackOffice` (tipo JS/TS & Web), coincidiendo con la variable `SONAR_POJECT_NAME` del nuevo jenkinsfile.

## 2026-09-10 11:30 — Usuario reporta pipeline funcionando

Se reportó que, tras corregir la configuración del job en Jenkins, las etapas de Jenkinsfile, Sonar y Trivy están funcionando. No he verificado esto de forma independiente contra un log de build exitoso — no se pegó ni persistió evidencia de un run exitoso en esta sesión.
