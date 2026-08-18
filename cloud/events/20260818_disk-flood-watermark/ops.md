# Flood-stage watermark de disco en sfcloud-monitoreo — pérdida de mensajes en journal

**Tags:** `SmartCloud`, `Graylog`, `Azure`, `PROD`

**Resumen:** el nodo único OpenSearch de `sfcloud-monitoreo` (Graylog SmartCloud) supera el flood-stage watermark de disco, lo que fuerza un bloqueo `read_only_allow_delete` en los 12 índices con shards en ese nodo. Como consecuencia, Graylog no puede escribir a esos índices, la rotación del índice `dev__3` falla, y el journal comienza a descartar mensajes no comprometidos — pérdida de datos en curso al momento de detectarse las alertas. El disco de 128gb desplegado (`phase=pilot` en Terraform) resulta insuficiente frente al volumen real acumulado por los índices rotados de Sales y Business.

## Tabla resumen

| Campo | Valor |
|---|---|
| Ticket Jira | Pendiente — solicitar al usuario |
| ID alerta | Uncommited messages deleted from journal / Journal utilization is too high / Error rotating index set / Indices blocked / Indexer disk watermark (flood/high/low) |
| Sistema | OpenSearch 2.18+ / Graylog 7.1.3 (bare metal, `sfcloud-monitoreo`) |
| Severidad | Alta — pérdida de datos en curso |
| Detectado | 2026-08-15/16 (alertas con "triggered 2-3 días atrás" al momento de la primera revisión, 2026-08-18) |
| Resuelto | 2026-08-18 — cerrado. Bloqueo levantado, ~18gb liberados, disco resizeado a 512gb (confirmado 23% de uso, 400gb libres), `dev__3` rotado sin alertas activas (H10). Cluster `yellow`/shards unassigned confirmado como el issue cosmético preexistente de réplicas en single-node, no relacionado a este incidente. Reconciliación de Terraform (H11) queda como único seguimiento abierto, no bloqueante |
| Responsable | Dante Paniagua (SRE) |

## Causa raíz

El disco OpenSearch desplegado (128gb, `phase=pilot` en `terraform.tfstate` de `cloud-graylog`) fue dimensionado originalmente solo para el volumen de Sales. Los índices rotados de Sales (`sales__1`–`__4`, 42.5gb) y Business (`business__6`–`__9`, 48.4gb) acumulados desde julio suman el 80% de los 114.3gb de índices en disco — no la carga de Catalog del onboarding fleet-wide del 2026-08-12, que pese a dominar la tasa de mensajes (87% de una ventana muestreada, por verbosidad de `AppServiceConsoleLogs`, no tráfico real) es un solo índice de apenas 14.9gb.

La política de retención de Sales/Business (`DeletionRetentionStrategy`, `max_number_of_indices: 20`) no es la causa: con solo 4 índices por set, no purgaría nada en un plazo útil (~2 años al ritmo de rotación actual, `TimeBasedSizeOptimizingStrategy` P30D-P40D). El cap de 20 índices, a los tamaños actuales por índice (5-27gb), implica un footprint teórico de cientos de GB por index set — dimensionado, con alta probabilidad, para el disco `phase=full` (1024gb) que nunca llegó a desplegarse.

El disco físico fue posteriormente resizeado a 512gb por el usuario (fuera de Terraform), lo que da margen estructural frente a este mismo escenario a futuro, pendiente de reconciliar en el estado de Terraform.

## Hallazgos

| # | Hallazgo | Riesgo |
|---|---|---|
| H1 | 12 índices bloqueados con `index.blocks.read_only_allow_delete` | Alto |
| H2 | Falla de rotación de índice: no se pudo crear `dev__3` | Alto |
| H3 | Mensajes "uncommitted" descartados del journal antes de ser escritos al Indexer — pérdida de datos activa | Alto |
| H4 | Nodo `sfcloud-monitoreo` por encima de flood/high/low watermark de disco | Alto |
| H5 | Disco OpenSearch desplegado (128gb, `phase=pilot`) nunca escalado a `phase=full` (1024gb) — contexto estructural, no driver proximal | Medio |
| H6 | Índices rotados de Sales (42.5gb) y Business (48.4gb) suman 80% del uso de disco — driver proximal real | Alto |
| H7 | Bloqueo `read_only_allow_delete` seguía activo pese a que el uso ya había bajado del flood watermark (95%) — no se levanta solo | Alto |
| H8 | Graylog 7.1.4 disponible — 7.1.3 desplegado está desactualizado | Bajo |
| H9 | `business__9` y `sales__4` (índices activos de escritura) muestran `begin`/`end` epoch (`1970-01-01`) en `/api/system/indices/ranges` — un filtro ingenuo por antigüedad los marca como "más viejos que 15 días", falso positivo detectado y corregido antes de ejecutar el `DELETE` | Alto — evitado |
| H10 | Alerta "Error rotating index set — could not create new target index `dev__3`" | Resuelto — `dev__3` confirmado `green`/activo (31.866 docs, 152.7mb) y `GET /api/system/notifications` sin alertas activas |
| H11 | Disco resizeado manualmente en Azure (128gb → 512gb) fuera de Terraform — `terraform.tfstate` sigue declarando `phase=pilot`/128gb, deriva (drift) entre estado real y estado de Terraform | Medio — pendiente reconciliar |

## Recursos afectados

| Recurso | Detalle |
|---|---|
| VM | `smartfran-graylog-pro` (`sfcloud-monitoreo`), Standard_D8s_v6, East US 2 |
| Disco OpenSearch | `smartfran-graylog-pro-disk-opensearch`, resizeado de 128gb a 512gb, Premium_LRS, LUN 0, filesystem XFS |
| Índices bloqueados (resuelto) | person__0, platform__0, catalog__0, dev__2, gl-events_0, sales__4, pos__0, admin__0, orders__0, graylog_3, gl-system-events_4, business__9 |
| Índices eliminados | sales__1, sales__2, business__6 (~18gb liberados) |
| Repo Terraform | `cloud-graylog/terraform/` — `main.tf` (`local.phase_config`), pendiente reconciliar con el resize manual |

## Comandos ejecutados

| # | Comando / Script | Propósito |
|---|---|---|
| C1 | `df -h` / `_cat/allocation` | Uso real de disco |
| C2 ⚠️ | Lift de `index.blocks.read_only_allow_delete` (`PUT _all/_settings`) | Restablecer escritura |
| C3 | `_cat/indices?s=store.size:desc` | Identificar índices más grandes |
| C4 | `GET /system/indices/index_sets` (Sales/Business) | Confirmar `retention_strategy`/`rotation_strategy` |
| C5 | `GET /system/indices/ranges` (Sales/Business) | Fechas reales `begin`/`end` por índice — detectar falsos positivos epoch |
| C6 ⚠️ | `DELETE /system/indexer/indices/{index}` × 3 (`sales__1`, `sales__2`, `business__6`) | Liberar espacio |
| C7 | `lsblk` / `lsblk -f` | Confirmar tamaño de disco/partición y tipo de filesystem tras el resize en Azure |
| C8 ⚠️ | `growpart /dev/nvme0n3 1` + `xfs_growfs /var/lib/opensearch` | Expandir partición y filesystem al nuevo tamaño de disco (512gb) |

Ver `scripts.sh` para el detalle completo.

## Acciones propuestas

1. **(SRE)** — Completado. Bloqueo `read_only_allow_delete` levantado (C2), confirmado con crecimiento de `docs.count` en `catalog__0`/`business__9`.
2. **(SRE)** — Completado. Eliminados `sales__1`, `sales__2`, `business__6` (C6) tras confirmar fechas reales vía C5 y descartar los falsos positivos epoch de H9 — ~18gb liberados, disco de 92% a 80%.
3. **(SRE)** — Completado. Disco OpenSearch resizeado de 128gb a 512gb en Azure (fuera de Terraform), partición y filesystem XFS expandidos (C7, C8) — confirmado 4x en sectores/data blocks, sin downtime.
4. **(SRE)** — Pendiente. Reconciliar `terraform.tfstate`/`main.tf` (`cloud-graylog`) con el disco real de 512gb — evitar que un futuro `terraform apply` genere conflicto (H11).
5. **(SRE)** — Completado. `dev__3` confirmado creado y `green` tras el lift del bloqueo; `GET /api/system/notifications` sin alertas activas — H10 cerrado.
6. **(SRE)** — Pendiente, no bloqueante. Reevaluar si `max_number_of_indices: 20` en Sales/Business sigue siendo razonable con el disco de 512gb.

## Hallazgos secundarios

- Actualización Graylog 7.1.3 → 7.1.4 disponible (H8) — evaluar en una ventana futura, no bloqueante.
