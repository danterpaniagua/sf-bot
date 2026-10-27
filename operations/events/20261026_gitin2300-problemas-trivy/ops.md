# GITIN-2300 [OPE] Problemas Trivy

**Tags:** Operaciones, Jenkins, SRE

## Qué pasó
- El 26/10 a las 11:48 UTC el build de `dev-src-pedidos-platform` (rama `develop`) falló en la etapa de Trivy.
- Trivy 0.74.0 terminó con `Failed to acquire cache or database lock` y `cache may be in use by another process: timeout`, antes de analizar la imagen.

## Resumen
Los pipelines de SmartPedidos en Jenkins ejecutan Trivy sobre las imágenes que construyen, y ninguno de los 10 comandos configuraba el directorio de caché, por lo que todos usaban el predeterminado del agente. El 26/10 a las 11:48 UTC el build de `dev-src-pedidos-platform` (`develop`) falló en esa etapa por un bloqueo del caché, y la imagen quedó sin reporte de vulnerabilidades. Unos 16 minutos después, a las 12:04 UTC, los escaneos de `platform` y `concentrador` terminaron correctamente con solo cuatro segundos de diferencia. La causa del bloqueo no está confirmada. Se preparó un cambio que da a cada build su propio directorio de caché. Los reportes que se generaron muestran 8 hallazgos de severidad alta en `platform` y 5 en `concentrador`, todos en paquetes de `node_modules`.

## Tabla resumen

| Campo | Valor |
|---|---|
| Ticket Jira | [GITIN-2300](https://smartit-ar.atlassian.net/browse/GITIN-2300) |
| ID alerta | NA |
| Sistema | Jenkins, pipelines de SmartPedidos (Trivy 0.74.0) |
| Severidad | No definida |
| Detectado | 2026-10-26 11:48 UTC |
| Resuelto | Pendiente: el cambio no se ejecutó todavía en Jenkins |
| Responsable | SRE |

## Causa raíz
NA

## Hallazgos

| # | Hallazgo | Riesgo |
|---|---|---|
| H1 | El build de `dev-src-pedidos-platform:develop` falló a las 11:48 UTC por el bloqueo del caché de Trivy; el análisis no llegó a la imagen. Los avisos de `--vuln-type` y `--template` son de opciones obsoletas o ignoradas y no son la causa. | Medio |
| H2 | Los 10 comandos `trivy image` y `trivy fs` de los 5 Jenkinsfiles de SmartPedidos (`develop`: platform, concentrador, backoffice; `ope`: platform, concentrador) no definían `--cache-dir`, por lo que todos compartían el caché predeterminado del agente. | Medio |
| H3 | A las 12:04 UTC los escaneos de `platform` (12:04:46) y `concentrador` (12:04:50) terminaron sin error, con cuatro segundos de diferencia. Es compatible con que los escaneos en paralelo ya no se bloqueen, pero no lo prueba: no se sabe si esos builds ya tenían `--cache-dir`. | Bajo |
| H4 | Los reportes de las imágenes `develop` no muestran vulnerabilidades en los paquetes de Alpine 3.23.4. En `node_modules` hay hallazgos de severidad alta: 8 en `platform` y 5 en `concentrador` (detalle abajo). | Alto |
| H5 | `platformsService` declara `express-jwt ^5.3.1` y `jsonwebtoken ^8.3.0`, que explican 2 de sus hallazgos; `concentradorService` ya declara `express-jwt ^8.5.1` y `jsonwebtoken ^9.0.3`. Ninguno de los dos servicios tiene lockfile, por lo que cada build instala las versiones que permiten los rangos ese día. | Medio |
| H6 | Trivy no reporta el runtime de Node: lee la base de paquetes de Alpine y los paquetes de `node_modules`, y el binario de Node no es ninguno de los dos. La versión de Node de las imágenes (`node:20.20-alpine`) la define la línea `FROM` del Dockerfile. | Medio |

Hallazgos de severidad alta en `node_modules`:

| Paquete | CVE | Instalada | Corregida en | platform | concentrador |
|---|---|---|---|---|---|
| `brace-expansion` | CVE-2026-102276 | 5.0.9 | 5.0.10 (también 3.0.7, 2.1.5, 1.1.19) | Sí | Sí |
| `brace-expansion` | CVE-2026-102278 | 5.0.9 | 5.0.11 (también 3.0.8, 2.1.6, 1.1.20) | Sí | Sí |
| `http-cache-semantics` | CVE-2026-93748 | 4.2.0 | Sin versión corregida listada | Sí | Sí |
| `undici` | CVE-2026-109869 | 6.28.0 | 6.29.1, 7.30.1, 8.12.2 | Sí | Sí |
| `undici` | CVE-2026-19534 | 6.28.0 | 6.28.1, 7.29.1, 8.10.2 | Sí | Sí |
| `express-jwt` | CVE-2020-15084 | 5.3.3 | 6.0.0 | Sí | No |
| `jsonwebtoken` | CVE-2022-23539 | 8.5.1 | 9.0.0 | Sí | No |
| `lodash.set` | CVE-2020-8203 | 4.3.2 | Sin versión corregida listada | Sí | No |

`undici`, `brace-expansion`, `http-cache-semantics` y `lodash.set` no están declarados en ningún `package.json`: llegan como dependencias indirectas, y no se determinó cuál paquete las trae.

## Acciones Tomadas

| # | Hora (UTC) | Acción |
|---|---|---|
| 1 | 2026-10-26 | Se agregó `--cache-dir "$WORKSPACE/.trivycache"` a los 10 comandos `trivy image` y `trivy fs` de los 5 Jenkinsfiles de SmartPedidos, en la copia local de los pipelines. El cambio queda guardado como parche. |
| 2 | 2026-10-26 | Se revisaron los reportes de Trivy de las imágenes `dev-src-pedidos-platform:develop` y `dev-src-pedidos-concentrador:develop`, y se cruzaron con las dependencias declaradas en el código de `develop` de ambos servicios. |

## Recursos afectados

| Recurso | Tipo | Detalle |
|---|---|---|
| `dev-src-pedidos-platform.jenkinsfile` (`develop` y `ope`) | Pipeline Jenkins | Etapa de Trivy con `trivy image` |
| `dev-src-pedidos-concentrador.jenkinsfile` (`develop` y `ope`) | Pipeline Jenkins | Etapa de Trivy con `trivy image` |
| `dev-src-pedidos-backoffice.jenkinsfile` (`develop`) | Pipeline Jenkins | Etapa de Trivy con `trivy fs` |
| `dev-src-pedidos-platform:develop` | Imagen Docker | 8 hallazgos de severidad alta en `node_modules` |
| `dev-src-pedidos-concentrador:develop` | Imagen Docker | 5 hallazgos de severidad alta en `node_modules` |

## Acciones propuestas

| # | Responsable | Acción | Estado |
|---|---|---|---|
| 1 | SRE | Hacer commit del cambio de `--cache-dir` en los 5 Jenkinsfiles. | Pendiente |
| 2 | SRE | Ejecutar el build `develop` de `platform` con el cambio y revisar la salida de la etapa de Trivy. | Pendiente |
| 3 | SRE | Si el bloqueo persiste, recolectar en el agente los procesos `trivy` en ejecución y el listado del directorio de caché. | Pendiente, condicionada a la acción 2 |
| 4 | SRE | Reemplazar `--vuln-type` por `--pkg-types` y agregar `--skip-version-check` en los mismos comandos. | Por decidir |
| 5 | Dev | Identificar qué paquete trae `undici`, `brace-expansion`, `http-cache-semantics` y `lodash.set` en cada servicio, y la actualización mínima para cada uno. | Pendiente |
| 6 | Dev | Actualizar `express-jwt` (5 a 6 o superior) y `jsonwebtoken` (8 a 9 o superior) en `platformsService`; son cambios de versión mayor y requieren pruebas de autenticación antes de aplicarse. | Por decidir |
| 7 | Dev | Evaluar agregar un lockfile en ambos servicios para que los builds sean reproducibles. | Por decidir |
