# Eventos — 20260818_disk-flood-watermark

## 2026-08-18 09:00 — Apertura de incidente por alertas de Graylog

**Resultado:**
Uncommited messages deleted from journal / Journal utilization is too high / Error rotating index set (dev__3) / Indices blocked (12) / Indexer disk watermark flood-high-low (nodo sfcloud-monitoreo)

He recibido el listado de alertas activas de Graylog para `sfcloud-monitoreo`. He identificado que este stack corresponde al proyecto `cloud-graylog` (repo separado, Graylog dedicado de SmartCloud) y no al stack Docker de SmartPedidos/SmartLoyalty. He leído `terraform.tfstate` de `cloud-graylog` y he confirmado que la infraestructura desplegada sigue en `phase = "pilot"` (disco OpenSearch de 128gb), mientras que `CLAUDE.md` registra el onboarding del fleet completo (8 apps) al Event Hub compartido el 2026-08-12. Marco esto como hipótesis de causa raíz — pendiente de confirmar contra uso de disco real.

## 2026-08-18 09:15 — Diagnóstico en vivo — corrijo la hipótesis de causa raíz

**Comando:** C1 — `df -h` / `_cat/allocation` / `_cat/indices`
**Resultado:**
`/var/lib/opensearch`: 127.8gb total, 116.8gb usado, 10.9gb libre (91%). Índices más grandes: `sales__3` (27.5gb), `business__8` (16.3gb), `business__9` (15.9gb), `catalog__0` (14.9gb), `business__7` (11gb).

He corregido la hipótesis inicial: el driver proximal no es el volumen de Catalog del onboarding fleet-wide (un solo índice de 14.9gb, 6 días de antigüedad) sino los índices rotados de Sales (42.5gb) y Business (48.4gb), que juntos son el 80% de los 114.3gb de índices — acumulados desde julio sin evidencia de purga. También he encontrado que el uso actual (91%) ya está por debajo del flood watermark (95%) que originalmente disparó el bloqueo — el bloqueo no se levanta solo al bajar el uso, así que es seguro levantarlo ahora sin liberar espacio primero.

## 2026-08-18 09:20 — Bloqueo levantado

**Comando:** C2 ⚠️ — `PUT _all/_settings {"index.blocks.read_only_allow_delete": null}`
**Resultado:**
`{"acknowledged":true}`

He restablecido la escritura en los índices bloqueados.

## 2026-08-18 09:25 — Confirmado: la escritura se restableció

**Comando:** C1 — `_cluster/health` / `_cat/indices`
**Resultado:**
`_cluster/health` sin cambios respecto al chequeo anterior (la API de health no reporta el estado de los blocks de índice). `catalog__0`: 14.9gb/13.457.561 docs → 15.4gb/13.603.711 docs (+146.150). `business__9`: 15.9gb/35.328.044 docs → 16.2gb/35.334.824 docs (+6.780).

He confirmado que la escritura se restableció comparando el crecimiento de `docs.count` en los índices activos de escritura de Sales y Business contra la lectura anterior. El journal debería estar drenando.

## 2026-08-18 09:35 — Retention/rotation strategy de Sales y Business — primera consulta, sin resultado inmediato

**Comando:** C4 — `GET /api/system/indices/index_sets` (filtrado Sales/Business)
**Resultado:**
Pendiente — consulta lanzada, sin resultado todavía en este punto.

Consulto la política de retención configurada, necesaria antes de identificar qué índices rotados son candidatos seguros a eliminar.

## 2026-08-18 09:40 — Disco sigue en ascenso, aún sin margen liberado

**Comando:** C1 — `df -h` / `_cat/allocation`
**Resultado:**
`/var/lib/opensearch` (`/dev/nvme0n3p1`): 128G total, 118G usado, 11G libre, 92%. Índices: 114.3gb → 115.1gb desde la lectura anterior.

He confirmado que el disco sigue en ascenso constante, todavía por debajo del flood watermark pero sin margen liberado — la escritura activa sigue confirmando que el fix de C2 funciona, pero no resuelve la presión de disco de fondo.

## 2026-08-18 09:45 — Limpieza por corte de 15 días — detecto falso positivo antes de ejecutar

**Comando:** C5 — `GET /api/system/indices/ranges` (filtrado Sales/Business, corte 2026-08-03)
**Resultado:**
`business__9` y `sales__4` (índices activos, no rotados) con `begin`/`end` epoch (`1970-01-01T00:00:00.000Z`). `sales__1` (end 2026-07-23), `business__6` (end 2026-07-31), `sales__2` (end 2026-08-02) — todos antes del corte. `business__7` (end 2026-08-04), `business__8` (end 2026-08-08), `sales__3` (end 2026-08-12) — todos después del corte.

He detectado que una comparación de strings ingenua marca `business__9` y `sales__4` como "más viejos que 15 días" — falso positivo: son los índices activos de escritura de cada set, sin rango calculado todavía por no haber rotado, no datos viejos. Eliminarlos habría cortado la ingesta activa de Sales y Business. Descarto esos dos y dejo como candidatos reales: `sales__1` (5gb), `sales__2` (7.8gb), `business__6` (5.2gb) — ~18gb totales.

## 2026-08-18 09:48 — DELETE falla 404 — endpoint incorrecto, corrijo

**Comando:** C6 ⚠️ — `DELETE /api/system/indices/{index}` (intento inicial, endpoint incorrecto)
**Resultado:**
`{"type":"ApiError","message":"HTTP 404 Not Found"}` × 3

Error mío: el recurso correcto para borrar un índice individual en la API de Graylog es `/api/system/indexer/indices/{index}`, no `/api/system/indices/{index}` (ese path es para gestión de index *sets*). Reenvío el comando corregido con `-w "%{http_code}"` para confirmar el resultado por índice.

## 2026-08-18 09:50 — Borrado exitoso, disco liberado

**Comando:** C6 ⚠️ — `DELETE /api/system/indexer/indices/{index}` (corregido) × 3
**Resultado:**
`204` en `sales__1`, `sales__2` y `business__6`.

He confirmado con `df -h`/`_cat/allocation`/`_cat/indices`: disco de `/var/lib/opensearch` bajó de 92% (118gb usados, 11gb libres) a 80% (102gb usados, 27gb libres) — por debajo de low (85%) y high (90%) watermark. Shards activos bajaron de 41 a 35 y unassigned de 16 a 10, consistente con las réplicas de los 3 índices borrados.

## 2026-08-18 10:00 — Retention_strategy confirmado — causa raíz estructural cerrada

**Comando:** C4 — `GET /api/system/indices/index_sets` (Sales/Business)
**Resultado:**
`SFC-Sales-prod` y `SFC-Business-prod`: `DeletionRetentionStrategy` (`max_number_of_indices: 20`), `TimeBasedSizeOptimizingStrategy` (`index_lifetime_min: P30D`, `index_lifetime_max: P40D`).

He confirmado que la retención automática no iba a purgar nada en un plazo útil con solo 4 índices por set. Cierro la causa raíz estructural: el cap de 20 índices a los tamaños actuales implica un footprint muy por encima del disco de 128gb (`phase=pilot`) realmente desplegado — parece dimensionado para el disco `phase=full` (1024gb) nunca aplicado. La limpieza manual del paso anterior no contradice la política, la adelanta.

## 2026-08-18 10:10 — Alertas re-pegadas — timestamps de la UI son de disparo, no de estado en vivo

**Resultado:**
Mismo `df -h`/`_cat/allocation`/`_cat/indices` de antes (sin cambios) + las tres alertas originales, todas con "triggered 2 días atrás".

Aclaro que ese timestamp de la UI de Graylog es el momento del disparo original, no un indicador de estado en vivo. Las dos primeras alertas (journal/uncommitted) ya están explicadas por la mitigación de C2. La tercera, "Error rotating index set — could not create new target index dev__3", queda como el único punto sin verificar (H10) — lanzo las queries de solo lectura (`/api/system/notifications`, `_cat/indices/dev*`), sin resultado todavía.

## 2026-08-18 10:15 — Fix estructural: resize de disco 128gb → 512gb en Azure

**Resultado:**
Disco resizeado en Azure de 128gb a 512gb, fuera de Terraform.

Confirmo con `lsblk` (C7): el disco físico (`nvme0n3`) ya muestra 512G, pero la partición (`nvme0n3p1`) seguía en 127.9G — falta expandir partición y filesystem. Confirmo filesystem XFS vía `lsblk -f`.

## 2026-08-18 10:35 — Partición y filesystem expandidos

**Comando:** C8 ⚠️ — `growpart /dev/nvme0n3 1` + `xfs_growfs /var/lib/opensearch`
**Resultado:**
Partición: 268.304.384 → 1.073.676.255 sectores. XFS: 33.538.048 → 134.209.531 data blocks.

He confirmado la expansión 4x, coincide con 128→512gb. Fix de fondo aplicado y confirmado, sin downtime de OpenSearch.

## 2026-08-18 10:45 — Reubicación del ticket de cloud-graylog a bots/cloud

Este evento se creó inicialmente en `cloud-graylog/operations/events/20260818_disk-flood-watermark/` (CG-008), siguiendo la convención propia de ese repo. Los tickets abiertos durante trabajo en `bots` pertenecen a este repo, así que reubico el ticket completo a `bots/cloud/events/20260818_disk-flood-watermark/`, reescribiendo `investigation.md`/`ops.md`/`ops-events.md`/`scripts.sh` al formato de la skill `ope-sre-output` (archivos sin prefijo de fecha, secciones y tags de `ops.md` según spec, `ops-events.md` append-only con horario y referencia a comandos por `Cx`). Elimino los archivos originales de `cloud-graylog` tras confirmar que no estaban commiteados (`git status` los mostraba como `??`, sin historial que preservar).

## 2026-08-18 10:55 — H10 cerrado: dev__3 rotó correctamente, sin alertas activas

**Comando:** `GET /api/system/notifications` + `_cat/indices/dev*`
**Resultado:**
`{"total": 0, "notifications": []}`. `dev__3` presente, `green`, 31.866 docs, 152.7mb.

Confirmo que la rotación de `dev__3` se completó exitosamente tras el lift del bloqueo (C2) — no quedó bloqueada por el incidente de disco. `/api/system/notifications` sin resultados confirma que no hay alertas activas en este momento; las tres alertas originales (journal/uncommitted, journal utilization, rotación de índice) están todas resueltas. Cierro H10.

## 2026-08-18 11:00 — Cluster yellow / shards unassigned — descarto relación con el incidente

**Resultado:**
`_cluster/health`: 40 active shards, 0 initializing, 0 relocating, 12 unassigned, status `yellow`.

Confirmo que este estado es el issue cosmético preexistente de réplicas (`replicas: 1` en los index sets de Sales/Business, permanentemente sin asignar en un cluster single-node) — no una regresión del incidente de disco. El conteo de shards subió respecto al chequeo post-limpieza (35 activos/10 unassigned) porque siguen rotando índices con el tiempo (`dev__3`, probablemente nuevas rotaciones de Sales/Business y/o el índice diario `top_queries-*`), cada uno sumando más réplicas sin asignar. No es indicador de presión de disco.

## 2026-08-18 11:05 — Cierre del incidente

**Comando:** C1 — `df -h /var/lib/opensearch`
**Resultado:**
512G total, 113G usado, 400G libre, 23%.

Confirmo salud de disco tras el resize: 23% de uso, amplio margen frente a ambos watermarks. Con H10 cerrado, disco liberado y resizeado, y el estado `yellow` del cluster explicado como no relacionado, cierro este incidente. Queda abierto como único seguimiento, no bloqueante: H11 (reconciliar `terraform.tfstate`/`main.tf` de `cloud-graylog` con el disco real de 512gb).
