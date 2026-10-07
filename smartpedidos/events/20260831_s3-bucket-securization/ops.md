# GITIN-1880 — Securización de S3

## Resumen

Como parte del pipeline de exportación de datos de SmartPedidos hacia Grido (ticket padre GITIN-1872), se creó un bucket S3 dedicado (`smartpedidos-orders`) para alojar los datos filtrados/redactados destinados a Grido, y se aplicó una política de acceso restringida por IP para proteger su contenido. El pipeline de transformación de datos (Lambda Python, filtrado y redacción de campos) fue construido bajo GITIN-1874 — este ticket cubre exclusivamente la creación del bucket y su seguridad de acceso.

## Tabla resumen

| Campo | Valor |
|---|---|
| Ticket Jira | [GITIN-1880](https://smartit-ar.atlassian.net/browse/GITIN-1880) |
| Sistema | AWS S3 (`smartpedidos-orders`, `us-east-1`) |
| Severidad | Media |
| Detectado | 2026-08-31 |
| Resuelto | 2026-09-16 |
| Responsable | Dante Paniagua (SRE) |

## Causa raíz

No aplica — este no es un ticket de incidente, sino de implementación: creación de infraestructura nueva (bucket) y su securización de acceso.

## Hallazgos

| # | Hallazgo | Riesgo |
|---|---|---|
| H1 | Bucket `smartpedidos-orders` creado en estado por defecto (acceso público bloqueado, sin política) | — resuelto en Fase 1 |
| H2 | Bucket recibiendo datos diarios de forma automática (pipeline de GITIN-1874, no de este ticket) — confirmado vía listado real de objetos | — informativo |
| H3 | Fase 2 (restricción de acceso por IP) sin aplicar — bloqueaba el cierre de este ticket | Alto — **resuelto** |
| H4 | IP de origen de Grido confirmada por su equipo de integración: `40.121.111.127` (runtime `IntegrationRuntimeComercial`) | — insumo necesario para H3 |
| H5 | Verificación funcional: solicitud anónima desde una IP no autorizada devuelve `403` — confirma que la restricción está realmente aplicada, no solo declarada en la política | — resuelto |

## Recursos afectados

| Componente | Impacto |
|---|---|
| Bucket S3 `smartpedidos-orders` | Política de acceso pública restringida por IP aplicada sobre el prefijo `grido/*` |

## Comandos ejecutados

| # | Comando / Script | Propósito |
|---|---|---|
| C1 | `aws s3api create-bucket` | Creación del bucket (2026-08-31) |
| C2 | `aws s3api list-objects-v2` | Confirmar actividad reciente del bucket antes de aplicar la política de acceso |
| C3 | `aws s3api put-public-access-block` | Habilitar la posibilidad de aplicar una política pública (desactivar los 4 bloqueos por defecto) |
| C4 | `aws s3api put-bucket-policy` | Aplicar la política de Fase 2 (`data/bucket-policy-grido.json`) |
| C5 | `aws s3api get-bucket-policy` | Confirmar que la política quedó aplicada correctamente |

Detalle completo y resultados en `data/`.

## Acciones propuestas

1. **(SRE)** — Bucket `smartpedidos-orders` creado y en estado inicial. Aplicado (2026-08-31).
2. **(SRE)** — Política de acceso Fase 2 aplicada: lectura pública sobre `grido/*`, denegada fuera de la IP `40.121.111.127/32`. Aplicado y verificado funcionalmente (2026-09-16).
3. **(SRE)** — Notificar a Grido que el acceso está listo, junto con el patrón de URL para consumir los archivos diarios. Email enviado (2026-09-16, `email_client.md`).
4. **(SRE)** — Si Grido solicita habilitar una IP adicional o rotar la actual, agregar un nuevo statement `Deny`/`NotIpAddress` o ampliar el CIDR existente — no se sobrescribe, se extiende.

## Hallazgos secundarios

Persiste, fuera del alcance de este ticket, la exposición de PII sin redactar en el bucket existente `smartfranbkp/news/` (Lambda Node.js original, no tocado por este pipeline). Sin ticket asignado aún — pendiente de decisión sobre si/cómo se aborda.

## Archivos de evidencia

| Archivo | Contenido |
|---|---|
| `data/create_bucket_result.json` | Resultado de la creación del bucket |
| `data/smartpedidos-orders_recent_objects.txt` | Listado de objetos recientes, confirma actividad del pipeline de GITIN-1874 |
| `data/bucket-policy-grido.json` | Política de acceso Fase 2 aplicada |
| `data/put_public_access_block_result.json`, `data/get_bucket_policy_confirm.json` | Confirmación de aplicación de la política |
| `email_client.md` | Borrador de email a Grido confirmando el acceso |
