# [OPE] Graylog SWAP Alert

**Tags:** `Operaciones`, `Graylog`, `Obserbavilidad`, `SRE`

## Resumen

El host del stack de Graylog (Graylog, Logstash, OpenSearch y MongoDB; hostname `sfcloud-monitoreo`) disparó una alerta por uso de swap. El host tiene 31 GiB de RAM y contaba con 4 GiB de swap, de los cuales se usaban 3.4 GiB. Se amplió el swap a 8 GiB con un swap file adicional de 4 GiB y se analizó el origen del uso de swap. La actividad de swap en vivo es prácticamente nula, por lo que el swap en uso corresponde, con alta probabilidad, a páginas frías y no a presión de memoria sostenida. Queda pendiente confirmar qué mide exactamente el trigger de la alerta.

## Tabla resumen

| Campo | Valor |
|---|---|
| Ticket Jira | [GITIN-2167](https://smartit-ar.atlassian.net/browse/GITIN-2167) |
| ID alerta | Graylog SWAP Alert (trigger por confirmar) |
| Sistema | Host `sfcloud-monitoreo` (Graylog / OpenSearch / Logstash / MongoDB) |
| Severidad | Por confirmar |
| Detectado | 2026-10-05 |
| Resuelto | Pendiente de confirmar que la alerta se normalice |
| Responsable | SRE — Operaciones |

## Causa raíz

Todavía no hay una causa raíz confirmada. Lo observado es consistente con páginas de memoria de los procesos Java (logstash, graylog y opensearch) que se movieron a swap en algún momento anterior y no volvieron a ser accedidas. Con `vm.swappiness` en 10 y `si`/`so` de 0–3 KB/s en las muestras de `vmstat`, no hay evidencia de paginación activa en este momento. No se verificó cuándo ni por qué esas páginas pasaron a swap.

## Hallazgos

| # | Hallazgo | Riesgo |
|---|---|---|
| H1 | El host usa 3.4 GiB de swap con 11 GiB de RAM disponible (cache reclamable incluida). El swap en uso se reparte entre logstash (~1.76 GB), graylog (~1.2 GB), opensearch (~0.41 GB) y mongod (~0.10 GB). | Medio |
| H2 | La actividad de swap en vivo es prácticamente nula (`si`/`so` 0–3 KB/s en 5 muestras, `wa` ≤ 1 %), por lo que el uso de swap actual no indica presión de memoria sostenida. | Bajo |
| H3 | Presupuesto de heap: logstash 4 GB, graylog 4 GB y opensearch 12 GB (confirmado por la API de OpenSearch, `heap.percent` 37) suman 20 GB sobre 31 GiB, lo que deja unos 11 GB para page cache. | Bajo |
| H4 | La línea de comandos de OpenSearch contiene los flags `-Xms1g -Xmx1g` (valor por defecto del paquete, en `/etc/opensearch/jvm.options`) y `-Xms12g -Xmx12g` (override en `/etc/opensearch/jvm.options.d/heap.options`). Es el patrón de override estándar de OpenSearch; el último valor prevalece y el heap efectivo es 12 GB. No requiere cambios. | Bajo |
| H5 | El swap file adicional se ubicó en el volumen XFS de MongoDB (`/var/lib/mongodb`), montado con `nofail`: si ese volumen no monta en el arranque, ese swap no se activa, aunque el sistema arranca igual. | Bajo |

## Recursos afectados

| Recurso | Detalle |
|---|---|
| Host del stack de Graylog | `sfcloud-monitoreo`, 31 GiB de RAM |
| Procesos con swap | logstash, graylog, opensearch, mongod |
| Volumen `/var/lib/mongodb` | XFS; aloja el swap file adicional de 4 GiB |

## Comandos ejecutados

Detalle y outputs en `scripts.sh` y en `data/`.

| # | Comando / Script | Propósito |
|---|---|---|
| C1 | `free -h` | Estado de memoria y swap |
| C2 | swappiness y VmSwap por proceso | Identificar qué procesos tienen memoria en swap |
| C3 | Mapeo de PIDs Java + `vmstat 5 6` | Asociar procesos Java a servicios y medir actividad de swap en vivo |
| C4 | Flags `-Xm*` de OpenSearch + `jcmd` | Determinar el heap configurado (`jcmd` falló por attach) |
| C5 | `_cat/nodes` de OpenSearch | Confirmar heap efectivo y uso |
| C6 | `cat /etc/fstab` | Verificar persistencia de ambos swap |
| C7 ⚠️ | `dd` + `chmod` + `mkswap` + `swapon` | Crear y activar swap file de 4 GiB |
| C8 | `hostname` y `grep` de flags `-Xm*` | Confirmar hostname y ubicar el origen de los flags de heap duplicados |

## Acciones propuestas

1. (SRE) Ampliar el swap con un swap file de 4 GiB en `/var/lib/mongodb/swapfile` y activarlo — completado: el swap total pasó a 8 GiB (4 GiB existentes + 4 GiB nuevos). Ambas entradas figuran en `/etc/fstab`.
2. (SRE) Revisar la definición del trigger de Zabbix de esta alerta (item, expresión y umbral) para confirmar si mide porcentaje de swap usado o cualquier uso de swap. Si es porcentaje, el uso actual (3.4 GiB de 8 GiB) debería quedar por debajo del umbral anterior; si es cualquier uso, el swap frío mantendrá la alerta activa.
3. (SRE) Verificar con `swapon --show` que ambas áreas de swap estén activas y confirmar que la alerta se normaliza.
4. (SRE) Evaluar recuperar las páginas frías (`swapoff`/`swapon`) o ajustar el trigger, según el resultado de la acción 2.

## Hallazgos secundarios

- El swap file adicional comparte volumen con los datos de MongoDB. Si la ubicación se considera inadecuada, puede reubicarse en `/swapfile` del disco raíz.
