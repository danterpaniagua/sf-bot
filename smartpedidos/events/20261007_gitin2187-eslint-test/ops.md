# [SP] ESLINT Test en SmartPedidos

**Tags:** `SmartPedidos`, `Jenkins`, `SRE`

## Resumen

Los pipelines de SmartPedidos (Platform, Concentrador y Backoffice) analizaban el código solo con SonarQube, sin incorporar los resultados de ESLint; los jobs se ejecutaban como "Pipeline script" definido dentro de Jenkins en lugar de leerse desde el repositorio; y los README de los tres repositorios no documentaban cómo ejecutar el contenedor ni mostraban el estado de calidad. Se evaluó ESLint sobre Platform en el host de SonarQube, se agregó a los Jenkinsfiles un stage que genera el reporte y lo importa a SonarQube, se prepararon los Jenkinsfiles para ejecutarse desde SCM, se actualizaron los README con una sección "Operaciones — Documentación" y los badges de SonarQube, y se llevaron a `develop` las actualizaciones de Dockerfile y paquetes que estaban en `ope` (Platform y Concentrador). Falta ejecutar los builds con los cambios y migrar los jobs a "Pipeline script from SCM".

## Tabla resumen

| Campo | Valor |
|---|---|
| Ticket Jira | [GITIN-2187](https://smartit-ar.atlassian.net/browse/GITIN-2187) |
| ID alerta | N/A |
| Sistema | Jenkins, SonarQube y repositorios de Platform, Concentrador y Backoffice (SmartPedidos) |
| Severidad | N/A |
| Detectado | 2026-10-07 |
| Resuelto | Parcial: cambios publicados en los repositorios; builds y migración de jobs pendientes |
| Responsable | SRE — Operaciones |

## Causa raíz

NA

## Hallazgos

| # | Hallazgo | Riesgo |
|---|---|---|
| H1 | Platform, con ESLint 6.x: 121 archivos, 39 errores y 478 advertencias; 37 archivos con error fatal de parseo (`Unexpected token .`, `=` o `?`), por lo que no fueron analizados. Por los mensajes se infiere que la versión 6.x del proyecto no reconoce encadenamiento opcional, `??` ni campos de clase. | Medio |
| H2 | Platform, con ESLint 8.57.1 y `ecmaVersion` 2022: 121 archivos sin errores de parseo, 4 errores (todos `new-cap`) y 1971 advertencias (890 `function-paren-newline`, 619 `quotes`, 249 `max-len`, 119 `semi`, 94 `no-unused-vars`). La configuración actual es casi toda de estilo; no se revisaron las ubicaciones de `new-cap` ni `no-unused-vars`. | Bajo |
| H3 | En la primera ejecución en Jenkins del Concentrador, ESLint falló porque su configuración extiende `google` y esa configuración no se resolvía; sin reporte, el stage falló y se omitieron los siguientes. El stage se ajustó (instala `eslint-config-google`, usa una copia de la configuración y, si ESLint no genera reporte, usa uno vacío con una advertencia). El ajuste no fue probado en Jenkins. | Medio |
| H4 | El scanner de SonarQube corre en Docker con el código montado en `/usr/src`; el reporte de ESLint trae rutas absolutas del host, por lo que el stage las reescribe. Sin esa reescritura los issues no se asociarían a archivos. No verificado todavía en un build real. | Medio |
| H5 | Backoffice es un proyecto Angular con TSLint y sin configuración de ESLint, y su código es 63,4 % TypeScript, 33,6 % HTML y 0,3 % JavaScript (SonarQube). El stage de ESLint probablemente genere un reporte vacío. Platform y Concentrador son 99,9 % JavaScript. | Bajo |
| H6 | `RUN_BUGS_REPORT` (por defecto `false`, protege el stage `Bugs Report`) ya existía en Platform, Concentrador y Backoffice; `pruebas.jenkinsfile` ejecutaba el stage siempre y ahora tiene el parámetro y la guarda. | Bajo |
| H7 | Los Jenkinsfiles de SF-PEDIDOS clonan por su cuenta el repositorio de la aplicación en el workspace. Para ejecutarlos desde SCM se agregó `skipDefaultCheckout(true)` a los seis Jenkinsfiles, para evitar que el checkout implícito del repositorio de pipelines interfiera (comportamiento documentado de Jenkins, no probado aquí). | Medio |
| H8 | SonarQube exige autenticación: una llamada anónima a su API responde 401 y el endpoint de badges sin token devuelve "Project has not been found", aunque los tres proyectos existen y son públicos. Los badges de los README usan por eso el token de badge de cada proyecto, que queda en texto plano en los README y en el historial de los repositorios. No se verificó que los badges se vean desde GitHub. | Medio |
| H9 | Los README de Platform y Concentrador eran marcadores (`# test 1`, `Hola mundo`) y el de Backoffice solo tenía las notas de Angular. Ahora los tres tienen la sección "Operaciones — Documentación": cómo construir y ejecutar la imagen en local con `<ENVIRON>` (`testing` o `staging`, sin `production`) y los badges de SonarQube. Los comandos no se probaron construyendo las imágenes. En Concentrador se eliminó el `Readme.md` duplicado. | Bajo |
| H10 | En `ope` están las actualizaciones de Dockerfile (`npm@11.20.0` y `apk upgrade`) y de paquetes (`axios` de `~1.13.5` a `~1.20.0`; en Platform, además, `overrides` de `axios` y `tar`). Se llevaron a `develop` en Platform y Concentrador mediante commits directos, no por pull request. Backoffice no tiene cambios de Dockerfile ni de paquetes: su Dockerfile sigue en `node:10-alpine`. | Medio |
| H11 | `ope` y `develop` están divergidos en Platform y Concentrador: `ope` no tiene los commits de MercadoPago de `develop`. En Backoffice, `ope` no tiene el movimiento del README a la raíz. | Bajo |
| H12 | Los datos de SonarQube muestran las líneas de código por lenguaje (Platform 14.549, Concentrador 12.984, Backoffice 19.773) y se recalculan en cada análisis. Solo hay un badge del total de líneas, no uno por lenguaje. | Bajo |

## Recursos afectados

| Recurso | Detalle |
|---|---|
| Jenkins | Jobs SF-PEDIDOS: Platform, Concentrador, Backoffice (develop), `pruebas`, Platform y Concentrador (ope) |
| SonarQube | Proyectos `DEVELOP.SmartPedidos.Platform`, `.Concentrador` y `.BackOffice` |
| Host `sonarqube-srv` | Ubuntu 22.04, Node 12.22.9; ejecuta los stages y el análisis |
| Repositorios de aplicación | Platform y Concentrador (ramas `develop` y `ope`), Backoffice (`develop` y `ope`) |
| Repositorio de pipelines | Jenkinsfiles de `SF-PEDIDOS` (`develop/` y `ope/`), rama `main` |

## Comandos ejecutados

Detalle en `scripts.sh` y resultados en `data/`.

| # | Comando / Script | Propósito |
|---|---|---|
| C1 | ESLint 6.x del proyecto sobre `api/` (reporte JSON) | Medir el estado de lint de Platform |
| C2 | Resumen del reporte | Interpretar C1 |
| C3 | ESLint 8.57.1 desde el caché de `npx`, con `ecmaVersion` 2022 | Analizar los 121 archivos |
| C4 | Resumen del reporte de ESLint 8 | Interpretar C3 |
| C5 ⚠️ | Stage `ESLint Report` y `-Dsonar.eslint.reportPaths` en los Jenkinsfiles de develop | Importar el reporte a SonarQube |
| C6 ⚠️ | `RUN_BUGS_REPORT` por defecto en `false` y guarda en `pruebas.jenkinsfile` | Homogeneizar el parámetro |
| C7 | `GET /api/projects/search` de SonarQube | Confirmar las claves de los proyectos |
| C8 | `GET /api/measures/component` (`ncloc_language_distribution`) | Líneas de código por lenguaje |
| C9 | Llamada al endpoint de badges sin token | Diagnosticar el error "Project has not been found" |
| C10 ⚠️ | README con sección Operaciones y badges en los tres repositorios | Documentar la ejecución local y mostrar la calidad |
| C11 ⚠️ | Dockerfile y `package.json` de `ope` llevados a `develop` en Platform y Concentrador | Aplicar las actualizaciones de Docker y paquetes |
| C12 ⚠️ | `skipDefaultCheckout(true)` en los seis Jenkinsfiles, commit y push a `main` | Preparar la ejecución desde SCM |

## Acciones propuestas

1. (SRE) Agregar a los Jenkinsfiles de Platform, Concentrador y Backoffice (develop) el stage `ESLint Report` y la propiedad `sonar.eslint.reportPaths` — completado en el repositorio de pipelines; no ejecutado todavía en Jenkins.
2. (SRE) Dejar `RUN_BUGS_REPORT` en `false` por defecto en todos los Jenkinsfiles de develop — completado en el repositorio de pipelines.
3. (SRE) Agregar `skipDefaultCheckout(true)` a los seis Jenkinsfiles y publicarlos en `main` — completado; la publicación se verificó por referencia local.
4. (SRE) Actualizar los README de Platform, Concentrador y Backoffice con la sección "Operaciones — Documentación" y los badges de SonarQube — completado en los tres repositorios; en Backoffice, el movimiento del README a la raíz estaba pendiente de commit al último control.
5. (SRE) Llevar a `develop` las actualizaciones de Dockerfile y paquetes de `ope` — completado en Platform y Concentrador; no aplica a Backoffice, que no las tiene.
6. (SRE) Ejecutar un build de develop de Platform, Concentrador y Backoffice y verificar: el primer build con el Dockerfile nuevo (`Docker Build` y Trivy), la importación de issues de ESLint en el log del scanner y que los issues se asocien a archivos.
7. (SRE) Migrar un job de prueba (`pruebas`) a "Pipeline script from SCM" (repositorio de pipelines por SSH, rama `main`, Script Path del Jenkinsfile del job, credencial SSH de solo lectura) y validar que no haya un checkout adicional sobre el workspace de la aplicación; luego migrar el resto de los jobs.
8. (SRE) Definir con el equipo si el stage de ESLint se mantiene en Backoffice (TypeScript, TSLint) y si se importan las ~1971 advertencias de estilo o solo reglas de tipo defecto (`no-unused-vars`, `new-cap`); revisar los 4 `new-cap` y los 94 `no-unused-vars`.
9. (SRE) Alinear `ope` con `develop` en Platform, Concentrador y Backoffice, y evaluar si Backoffice requiere sus propias actualizaciones de Dockerfile y paquetes (stack Angular con base Node 10, tarea aparte).
10. (SRE) Decidir si los tokens de badge de SonarQube pueden quedar en los README o se reemplazan, y revisar su exposición en el repositorio de pipelines, cuyo README también los contiene.

## Hallazgos secundarios

- El historial del repositorio de pipelines muestra dos commits con el mismo mensaje del cambio de ESLint; no se investigó la causa.
