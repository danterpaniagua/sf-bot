# GITIN-2317 [SP] Platform update 20->22

**Tags:** SmartPedidos, Platform, SEGURIDAD, SRE

## Qué pasó
- El servicio `platforms-service` de SmartPedidos construye su imagen sobre `node:20.20-alpine`.
- El release de seguridad de Node.js del 21/10 corrigió las líneas 26, 24 y 22 (26.12.1, 24.22.1 y 22.23.4). Node 20 no figura entre ellas: el aviso indica que las versiones sin soporte siempre quedan afectadas y no publica corrección para ellas.
## Resumen
La imagen de `platforms-service` se construía sobre Node 20, una línea que el aviso de seguridad del 21/10 no corrige. Se cambió el `Dockerfile` a Node 22.23.4 (la versión corregida de la línea 22) y a npm 12.2.1, y la instalación de la etapa final a `npm ci --omit=dev`; el cambio está en la rama `ope`, ya subida al repositorio, pero no en `develop` ni desplegado. En una imagen local se verificó Node v22.23.4 y npm 12.2.1, y el servicio arrancó con la configuración de staging sin errores atribuibles a Node 22. Quedan 4 hallazgos de severidad alta en el escaneo local de Trivy, de los cuales ninguno es del binario de Node. El job de Jenkins de la rama `ope` no se disparó con el push. No se probaron pedidos entrantes ni la cola SQS.

## Tabla resumen

| Campo | Valor |
|---|---|
| Ticket Jira | [GITIN-2317](https://smartit-ar.atlassian.net/browse/GITIN-2317) (subtarea de [GITIN-2315](https://smartit-ar.atlassian.net/browse/GITIN-2315)) |
| ID alerta | NA |
| Sistema | SmartPedidos: `platforms-service` (`api/Dockerfile`) |
| Severidad | Alta según el aviso de Node (4 de 10 vulnerabilidades); exposición propia no determinada |
| Detectado | Publicación del aviso: 2026-10-21; revisión: 2026-10-26 |
| Resuelto | Pendiente (cambio en la rama `ope`; no está en `develop` ni desplegado) |
| Responsable | SRE |

## Causa raíz
La imagen base `node:20.20-alpine` corresponde a una línea que el aviso de seguridad del 21/10 no corrige ni da mitigación.

## Hallazgos

| # | Hallazgo | Riesgo |
|---|---|---|
| H1 | En la imagen local construida con el cambio: Node `v22.23.4`, npm `12.2.1` y `body-parser` 1.20.9. | Informativo |
| H2 | Arranque con `serve:stg` en Node 22: conecta a la base de staging, inicializa las plataformas y el servidor queda escuchando. Errores vistos: PedidosYa HTTP 401 y Rappi HTTP 404, sin evidencia de relación con Node (no se corrió una línea base en Node 20). | Bajo |
| H3 | Escaneo de Trivy (alta y crítica) de la imagen local: 4 hallazgos de severidad alta y 0 críticos. `undici` 6.29.0 (CVE-2026-109869, corregido en 6.29.1) está incluido dentro de npm y ninguna versión publicada de npm incluye la corrección. `express-jwt` 5.3.3 (CVE-2020-15084, corregido en 6.0.0), `jsonwebtoken` 8.5.1 (CVE-2022-23539, corregido en 9.0.0) y `lodash.set` 4.3.2 (CVE-2020-8203, sin versión corregida) son dependencias del servicio. | Medio |
| H4 | `body-parser` (CVE-2026-111181, corregido en 1.20.9, publicado el 2026-10-22) se resuelve a 1.20.9 en una instalación nueva aun con el rango anterior; se subió el piso a `^1.20.9`. Un build con la capa de `npm install` en caché puede conservar una versión anterior. | Medio |
| H5 | El job de Jenkins de la rama `ope` se dispara solo con un webhook genérico y su token es un valor de reemplazo (`REPLACE_WITH_NEW_GENERIC_WEBHOOK_TOKEN`); el push a `ope` no inició un build (la ejecución #17 fue manual). | Medio |
| H6 | Trivy no revisa el binario de Node, por lo que el escaneo no comprueba las CVE de octubre; la comprobación de esas es la versión de Node dentro de la imagen (H1). | Informativo |

## Recursos afectados

| Recurso | Detalle |
|---|---|
| `platforms-service` (`api/Dockerfile`, `api/package.json`) | Cambios en la rama `ope`. |
| Job de Jenkins de la rama `ope` (SmartPedidos, platform) | Sin disparo automático. |

## Acciones Tomadas

| # | Hora (UTC) | Acción |
|---|---|---|
| 1 | 2026-10-26 18:59 | Escaneo de Trivy de la imagen local `platforms-service` en Node 22 (alta y crítica): 4 hallazgos de severidad alta. |
| 2 | 2026-10-26 19:00 | Verificación de las versiones dentro de la imagen local: Node `v22.23.4`, npm `12.2.1`. |
| 3 | 2026-10-26 19:02 | Arranque de la imagen con `serve:stg` durante 90 segundos con la configuración de staging. |
| 4 | 2026-10-26 19:24 | Commit del `Dockerfile` en la rama `ope`: `node:22.23.4-alpine` en ambas etapas, npm `12.2.1` y `npm ci --omit=dev` en la etapa final. |
| 5 | 2026-10-26 19:38 | Inspección de solo lectura de las versiones de los paquetes instalados dentro de la imagen local, antes de eliminarla. |
| 6 | 2026-10-26 19:42 a 19:57 | Commits en la rama `ope` que dejan, en neto, `body-parser` con piso `^1.20.9`; rama `ope` subida al repositorio (verificado en el remoto: `b76ef87`). |

## Acciones propuestas

| # | Responsable | Acción | Estado |
|---|---|---|---|
| 1 | SRE | Reemplazar el token de reemplazo del job de Jenkins de `ope` y agregar el webhook de GitHub con los eventos push y pull request; verificar con un push a `ope`. | Pendiente |
| 2 | SRE | Revisar el resultado del primer build y del escaneo de Trivy del job con el commit actual de `ope`. | Pendiente |
| 3 | SRE | Probar el servicio en un entorno no productivo con pedidos entrantes y la cola SQS en Node 22. | Pendiente |
| 4 | Dev | Decidir qué hacer con `express-jwt` (6.0.0), `jsonwebtoken` (9.0.0) y `lodash.set` (sin corrección), que requieren revisar el código. | Por definir |
| 5 | SRE | Volver a evaluar `undici` cuando npm publique una versión que incluya 6.29.1 o posterior. | Pendiente |
| 6 | SRE | Llevar el cambio de `ope` a `develop` por el flujo habitual y confirmar que producción se despliega desde `develop` con Node 20 hoy. | Pendiente |

## Hallazgos secundarios
- La configuración de staging del repositorio contiene credenciales en texto plano; una imagen construida desde el árbol de trabajo las incluye en una capa, por lo que esas imágenes no deben subirse a un registro.
