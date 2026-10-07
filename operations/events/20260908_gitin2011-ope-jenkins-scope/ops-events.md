# Eventos — 20260908_gitin2011-ope-jenkins-scope

## 2026-09-08 11:30 — Apertura de investigación

He abierto la investigación para GITIN-2011 (parent GITIN-1857) sobre el nuevo scope `ope` de Jenkins en `sf-devops` para SF-PEDIDOS. He confirmado que la carpeta `ope/` contiene dos Jenkinsfiles nuevos (Concentrador, Platform), sin versionar en git, cada uno con 3 stages (Cloning Repo, Docker Build, Test with Trivy) frente a los 8 stages del scope `develop`.

## 2026-09-08 11:40 — Confirmación de alcance intencional

He confirmado que el alcance reducido a Trivy es intencional, no un estado parcial pendiente de completar hacia paridad con `develop`: ambos pipelines ya fueron desplegados y probados, generando reportes de Trivy sobre el `package.json` posterior al upgrade de dependencias de GITIN-2000/GITIN-2002. He descartado la necesidad de agregar los stages de Bugs Report, Changelog, NPM install, Sonarqube y Quality Gate a este scope.

## 2026-09-08 11:45 — Redacción del ticket

He redactado `ops.md` con el estado consolidado: pipelines creados y probados manualmente, token del webhook todavía como placeholder (bloqueando la activación automática por push/PR), configuración de eventos del webhook de GitHub sin confirmar, y ambos archivos sin commitear en `sf-devops`.

## 2026-09-08 12:00 — Cierre del ticket

He cerrado el ticket: el objetivo (verificación puntual vía Trivy del post-upgrade de GITIN-2000/GITIN-2002) ya está cumplido con las corridas manuales. He dejado la generación del token del webhook, la confirmación del evento "Pull requests" en GitHub, y el commit de los Jenkinsfiles como seguimiento, sin que bloqueen este cierre.
