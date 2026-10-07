# 02-09-2026_export-s3-update

**Tags:** SmartPedidos, MongoDB, AWS, DEPLOY, PROD

## Resumen

Durante el trabajo de GITIN-1874 (construcción del ETL redactado hacia Grido), se detectó que `mongo-to-s3-CFN-ScheduledMongoToS3-1EZXBGD94CJVO` nunca enviaba a S3 tres campos (`order.originalId`, `order.displayId`, `order.details[].canje`) pese a estar presentes y 100% poblados en los documentos de MongoDB — `orderMapper()` simplemente no los copiaba a la salida. El export corría exitosamente todos los días; los campos quedaban omitidos en silencio, sin error. Se corrigió `orderMapper()` para incluirlos, junto con un fix menor de configuración (`region` hardcodeado en lugar de leer `process.env.REGION`). El cambio fue desplegado y validado contra una exportación real de producción.

## Tabla resumen

| Campo | Valor |
|---|---|
| Ticket Jira | [GITIN-1983](https://smartit-ar.atlassian.net/browse/GITIN-1983) |
| Ticket padre | GITIN-1872 |
| ID alerta | — (encontrado durante la construcción de GITIN-1874, sin alerta automática) |
| Sistema | mongo-to-s3-CFN-ScheduledMongoToS3-1EZXBGD94CJVO (Lambda, SmartPedidos) |
| Severidad | Media (datos operativos ausentes, sin PII involucrada, sin interrupción del servicio) |
| Detectado | 2026-09-01, durante la construcción de GITIN-1874 |
| Resuelto | 2026-09-02 — desplegado y validado contra datos reales de producción |
| Responsable | Dante Paniagua, SRE |

## Causa raíz

`orderMapper()` (en `app.js`, el archivo de lógica real de la Lambda — no confundir con `handler.js`, el wrapper delgado del entry point) construye el objeto exportado copiando campo por campo desde el documento crudo de MongoDB. Tres campos nunca se copiaron: `order.originalId`, `order.displayId` y `details[].canje` — código incompleto desde el origen del mapper, no un cambio reciente que rompió algo. Al no lanzar error (los campos simplemente no se agregaban al objeto de salida), pasó desapercibido en el uso normal del export hasta que se contrastó explícitamente contra un allow-list de campos requerido por GITIN-1874.

## Hallazgos

| # | Hallazgo | Riesgo |
|---|---|---|
| H1 | `order.originalId`/`order.displayId`/`details[].canje` ausentes del 100% de los registros exportados, pese a estar 100% poblados en el origen (confirmado por consulta directa a MongoDB, 5000/5000 documentos muestreados). Confirmado en una exportación real de producción del 01/09 antes del fix: `originalid`/`displayid` ausentes en el 100% de 18.769 (UTC0) y 19.240 (`-3`) registros. | Medio |
| H2 | `region` en `AWS.config.update()` estaba hardcodeado al string literal `'us-east-1'` en lugar de leer `process.env.REGION` (declarada pero nunca usada) — funcionalmente correcto pero no configurable. | Bajo |
| H3 | Corrección desplegada y confirmada: exportación real posterior al despliegue (`news20260901-3.json`, 19.101 registros) muestra `originalid`/`displayid` presentes en el 100% de los registros. `canje` presente/ausente según la tasa de población real del campo en el origen (ausencia = `undefined`, omitido por `JSON.stringify`, no es un error). | — (corrección validada) |

## Recursos afectados

| Componente | Impacto |
|---|---|
| mongo-to-s3-CFN-ScheduledMongoToS3-1EZXBGD94CJVO (Lambda) | `orderMapper()` actualizado; desplegado y validado |
| S3 (`smartfranbkp/news/`) | Exportaciones anteriores al despliegue (02/09/2026) carecen de estos tres campos de forma permanente — no se re-procesan retroactivamente como parte de este ticket |
| GITIN-1874 (ETL redactado hacia Grido) | Depende de estos campos (`originalId`/`displayId` están en el pedido de campos de Grido) — desbloqueado por esta corrección |

## Comandos ejecutados

Detalle completo en `20260831_lambda-s3-export-utc3/investigation.md` y `data/` — este ticket referencia esa evidencia, no la duplica.

| # | Comando / Script | Propósito |
|---|---|---|
| C1 | `mongosh` — conteo de población de `originalId`/`displayId`/`canje` | Confirmar que los campos existen y están poblados en el origen, no es un problema de datos faltantes en Mongo |
| C2 | `aws s3 cp` + análisis en Python (antes y después del despliegue) | Confirmar la ausencia de los campos en producción antes del fix, y su presencia después |

## Acciones propuestas

1. Ninguna pendiente — corrección desplegada y validada. Este ticket es de registro.
2. **(Dev, opcional)** Evaluar si vale la pena reprocesar retroactivamente el historial de S3 para agregar estos tres campos a exportaciones anteriores al 02/09/2026 — no solicitado, no realizado como parte de este ticket.

## Hallazgos secundarios

Ninguno — los demás hallazgos de la misma remediación (bugs de conexión, memoria, límite de día UTC-3, el vacío de datos permanente del 16/08) pertenecen a GITIN-1970 y están documentados allí, no en este ticket.
