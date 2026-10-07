# Eventos — 20260827_jenkins-bugreport-toggle-branch-filter

## 2026-08-27 — Diagnóstico inicial y toggle del stage Bugs Report

He leído los Jenkinsfiles de Concentrador y Platform en `sf-devops` tal como fueron pasteados desde la configuración viva de Jenkins. He confirmado que ambos ejecutan el stage `Bugs Report` sin ninguna condición, en cada build. He agregado el parámetro `RUN_BUGS_REPORT` (default `false`) y un bloque `when` en el stage `Bugs Report` de ambos Jenkinsfiles, de forma que el stage quede deshabilitado por defecto en builds disparados por webhook.

## 2026-08-27 — Filtro de rama en el Generic Webhook Trigger

He confirmado que el `GenericTrigger` de ambos jobs se dispara ante cualquier push al repositorio, sin filtrar por rama. He agregado `genericVariables` para extraer `ref` del payload de GitHub y `regexpFilterExpression` para que el trigger solo dispare el build cuando el push corresponde a `LOCAL_GIT_BRANCH`. He centralizado el nombre de la rama en una variable Groovy (`TARGET_BRANCH`) compartida entre el trigger y `LOCAL_GIT_BRANCH` en ambos archivos.

## 2026-08-27 — Corrección de rama en Platform

He verificado que `TARGET_BRANCH` en Platform apuntaba a la rama de feature `mejorasLogsTestTokenHeaders`. El filtro debía apuntar a `develop`, así que he actualizado `TARGET_BRANCH` a `develop` en `dev-src-pedidos-platform.jenkinsfile`.

## 2026-08-27 — Aplicación confirmada

Ambos Jenkinsfiles actualizados fueron pegados en la configuración de los jobs de Jenkins; los cambios están activos.
