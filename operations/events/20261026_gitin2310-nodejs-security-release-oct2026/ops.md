# GITIN-2310 [OPE] Node vulnerability

**Tags:** Operaciones, SEGURIDAD, SRE

## Qué pasó
- El 21/10 el proyecto Node.js publicó un release de seguridad con 10 vulnerabilidades (4 altas, 3 medias, 3 bajas) corregidas en las líneas 26, 24 y 22 (26.12.1, 24.22.1 y 22.23.4).
- Node 20 no figura entre las líneas corregidas. Los servicios `platformsService` y `concentradorService` de SmartPedidos construyen su imagen sobre `node:20.20-alpine` en la rama `develop`.

## Resumen
SmartPedidos ejecuta dos servicios Node, `platformsService` y `concentradorService`, sobre una imagen base de Node 20, una línea que el aviso de seguridad del 21/10 no corrige. El aviso indica que las versiones sin soporte siempre quedan afectadas por un release de seguridad y no publica corrección ni mitigación para ellas. El 26/10 se revisó la exposición: el código propio de ambos servicios no usa los módulos afectados, pero `axios` usa por defecto el descompresor Brotli de Node (CVE-2026-111497, severidad alta), por lo que ese componente se alcanza de forma indirecta. SmartLoyalty y SmartCloud no usan Node en sus servicios (son .NET). Por ahora no hay corrección posible sin cambiar la línea de Node de las imágenes.

## Tabla resumen

| Campo | Valor |
|---|---|
| Ticket Jira | [GITIN-2310](https://smartit-ar.atlassian.net/browse/GITIN-2310) |
| ID alerta | NA |
| Sistema | SmartPedidos: `platformsService` y `concentradorService` (imagen `node:20.20-alpine`) |
| Severidad | Alta según el aviso de Node (4 de 10 vulnerabilidades); exposición propia no determinada |
| Detectado | Publicación del aviso: 2026-10-21; revisión: 2026-10-26 |
| Resuelto | Pendiente |
| Responsable | SRE |

## Causa raíz
NA

## Hallazgos

| # | Hallazgo | Riesgo |
|---|---|---|
| H1 | Los dos servicios construyen su imagen sobre `node:20.20-alpine` (rama `develop`, que según lo indicado por el equipo es la que se despliega en producción). Node 20 no recibe corrección. La versión que corre dentro del contenedor en producción no se verificó. | Alto |
| H2 | El código propio de ambos servicios no usa Brotli, `zlib`, `dns.resolve`, `dns.reverse`, `tls.checkServerIdentity`, `randomUUID` ni las opciones de permisos o snapshots de Node. | Bajo |
| H3 | `axios` (`~1.20.0`), usado por ambos servicios, descomprime con `zlib.createBrotliDecompress` las respuestas con `content-encoding: br` y anuncia `br` en `Accept-Encoding` por defecto, salvo que se use `decompress: false`. Ningún servicio cambia esas opciones. El riesgo es una respuesta maliciosa de un servidor al que nos conectamos (por ejemplo una plataforma de delivery), no tráfico entrante. Se leyó el código de la rama `v1.x` de `axios`; la versión instalada no se verificó (no hay lockfile). | Medio |
| H4 | Las vulnerabilidades de TLS y DNS requieren condiciones que no están en el código (hosts como IP escrita en formatos no canónicos; validar un nombre y luego resolverlo con `dns.resolve*`). Los hosts configurados fuera del código (SSM, variables de entorno) no se revisaron. | Bajo |
| H5 | Trivy no cubre estas fallas: revisa los paquetes de Alpine y de `node_modules`, no el runtime de Node. La versión de Node de la imagen la define la línea `FROM` del Dockerfile. | Medio |
| H6 | SmartLoyalty y SmartCloud no usan Node en sus servicios (son .NET). El uso de Node en herramientas y pipelines (agentes de Jenkins, builds de front) no se relevó. | Bajo |
| H7 | En el código propio de ambos servicios no hay usos de APIs eliminadas en Node 22 (`crypto.createCipher`, `new Buffer`, `fs.exists`, `punycode`, `util.is*`). La compatibilidad de las dependencias con Node 22 no se evaluó. | Bajo |

Las 10 vulnerabilidades del aviso:

| CVE | Severidad | Componente | Líneas afectadas |
|---|---|---|---|
| CVE-2026-111497 | Alta | Descompresor Brotli (`node:zlib`): escritura fuera del buffer con datos Brotli inválidos | 26, 24, 22 |
| CVE-2026-105482 | Alta | `dns.resolve*()`: corta los nombres en un byte nulo | 26, 24, 22 |
| CVE-2026-105483 | Alta | `tls.checkServerIdentity()`: host con dígitos de ancho completo no se reconoce como IP | 26, 24 |
| CVE-2026-106069 | Alta | `tls.checkServerIdentity()`: IPv4 con ceros a la izquierda; depende del resolvedor del sistema | 26, 24, 22 |
| CVE-2026-105481 | Media | Sockets keep-alive del agente HTTP | 26, 24, 22 |
| CVE-2026-106072 | Media | `tls.checkServerIdentity()`: IPv4 en formatos no canónicos | 26, 24, 22 |
| CVE-2026-106074 | Media | `crypto.randomUUID()` y `randomInt()` en snapshots y SEA | 26, 24, 22 |
| CVE-2026-106070 | Baja | `zlib.ZipFile` | 26 |
| CVE-2026-106071 | Baja | Modelo de permisos: comodín en `--allow-fs-read` | 26 |
| CVE-2026-106073 | Baja | Modelo de permisos: `fs.realpathSync()` | 26, 24, 22 |

## Acciones Tomadas

| # | Hora (UTC) | Acción |
|---|---|---|
| 1 | 2026-10-26 | Se revisó el aviso oficial de Node.js del 21/10 y fuentes secundarias. |
| 2 | 2026-10-26 | Se revisaron los Dockerfile, las dependencias declaradas y el código de `develop` de `platformsService` y `concentradorService`, incluido el comportamiento de `axios` frente a Brotli según su código fuente. |
| 3 | 2026-10-26 | Se preparó un correo para Operaciones con el detalle de las vulnerabilidades, la exposición de cada plataforma y las opciones de migración. |

## Recursos afectados

| Recurso | Tipo | Detalle |
|---|---|---|
| `platformsService` | Servicio Node (SmartPedidos) | Imagen base `node:20.20-alpine`; usa `axios ~1.20.0` |
| `concentradorService` | Servicio Node (SmartPedidos) | Imagen base `node:20.20-alpine`; usa `axios ~1.20.0` |

## Acciones propuestas

| # | Responsable | Acción | Estado |
|---|---|---|---|
| 1 | SRE | Confirmar que la imagen de producción de ambos servicios se construyó con el `FROM` de `develop` (Node 20). | Pendiente |
| 2 | SRE | Migrar ambos servicios a una línea con soporte cambiando las dos líneas `FROM` del `Dockerfile` de `api/` en `develop`: `node:22.23.4-alpine` (menor esfuerzo; corrige las 7 vulnerabilidades que afectan a la línea 22, ya que CVE-2026-105483, CVE-2026-106070 y CVE-2026-106071 no la afectan) o `node:24.22.1-alpine` (corrige las 8 que afectan a la línea 24, ya que CVE-2026-106070 y CVE-2026-106071 solo aplican a la 26; más margen de soporte). | Por decidir |
| 3 | SRE | Verificar que los tags de la imagen elegida existan en Docker Hub. | Pendiente |
| 4 | Dev | Evaluar la compatibilidad de las dependencias con Node 22 (por ejemplo `winston-mongodb`, `node-cron` y `mongoose 7.8`) y probar ambos servicios en el entorno de test antes de promover el cambio. | Pendiente |
| 5 | SRE | Confirmar la versión instalada de `axios` en las imágenes y su manejo de Brotli. | Pendiente |
| 6 | Dev | Mitigación temporal para Brotli mientras Node 20 no tenga corrección, a evaluar y probar: en `axios`, `decompress: false` o un `Accept-Encoding` propio sin `br`; en el proxy inverso, quitar `Content-Encoding: br` de solicitudes no confiables, y `inflate: false` en `body-parser`. Viene de fuentes secundarias ([Qualys](https://blog.qualys.com/product-tech/2026/10/23/node-js-patches-brotli-remote-code-execution-flaw-find-vulnerable-runtimes-before-attackers-do)); el aviso oficial no publica mitigaciones. | Por decidir |
| 7 | SRE | Relevar el uso de Node en herramientas y pipelines de Operaciones (agentes de Jenkins, builds de front). | Pendiente |
