# GITIN-2228 — [OPE] Graylog: nvme0n3. Alta latencia

**Tags:** `SmartCloud`, `Graylog`, `Obserbavilidad`, `SRE`, `PROD`

## Qué pasó

- Zabbix generó una alerta en el host "Cloud Graylog": "nvme0n3: Disk read/write request responses are too high (read > 20 ms for 15m or write > 20 ms for 15m)".
- La alerta estuvo activa de las 08:33:01 a las 08:38:04 (5 minutos 3 segundos) del 2026-10-15 y se resolvió sola. No se indicó la zona horaria de las horas de la alerta.
- La alerta muestra los valores "2 ms, 63,0535 ms"; se asume que son lectura y escritura, en ese orden, y que lo alto es la escritura.
- El trigger se abrió y se recuperó al menos 11 veces el 2026-10-15 entre las 07:36 y las 14:56 (hora local, -03:00, asumida); cada episodio duró de unos minutos a unos 40 minutos.
- `nvme0n3` es el disco de datos de OpenSearch de la VM de Graylog (partición montada en `/var/lib/opensearch`); la relación con la VM es una inferencia por el layout y los tamaños.

## Resumen

El disco de datos de OpenSearch de la VM de Graylog SmartCloud tiene latencia alta de lectura y escritura de forma recurrente, lo que dispara repetidamente la alerta de Zabbix desde el 2026-10-15. Además, las búsquedas de Graylog no tenían límite de rango de tiempo ni de duración, y el disco estaba al 79 % de uso el 2026-10-15 (con unos 7 días de margen al ritmo de ingesta de ese día). La causa no está confirmada. Las lecturas y capturas de esta investigación descartan que se alcancen los límites provisionados de Azure y muestran que las ráfagas de lectura las genera el propio proceso de OpenSearch; la latencia por operación del disco es alta incluso con poca carga en varias muestras. Se aplicó un límite de duración y de rango de tiempo a las búsquedas, y quedan por decidir las pruebas sobre el disco y la política de retención de logs.

## Tabla resumen

| Campo | Valor |
|---|---|
| Ticket Jira | [GITIN-2228](https://smartit-ar.atlassian.net/browse/GITIN-2228) |
| ID alerta | No registrado |
| Sistema | Graylog SmartCloud (VM de Graylog y OpenSearch, Azure) |
| Severidad | Por definir |
| Detectado | 2026-10-15 08:33 (zona horaria no indicada) |
| Resuelto | No: el problema continúa abierto |
| Responsable | SRE |

## Causa raíz

NA

## Hallazgos

| # | Hallazgo | Riesgo |
|---|---|---|
| H1 | La alerta no fue un episodio aislado: el 2026-10-15 hubo al menos 11 episodios. En una ventana de 2 horas la latencia de escritura tuvo mediana de 31 ms (105 de 120 puntos por encima de 20 ms); la lectura superó 20 ms en 16 de 120 puntos, con picos cortos de hasta 259 ms. | Medio |
| H2 | Azure no muestra límites alcanzados a resolución de un minuto: el disco (P30, 5.000 IOPS y 200 MB/s provisionados, sin bursting) tuvo como máximo 400 lecturas/s, 222 escrituras/s y 47,5 MB/s de escritura, y la VM como máximo 10 % de IOPS y 20 % de ancho de banda sin caché. La métrica de porcentaje consumido del propio disco no está disponible, y un micro-pico dentro de un minuto no es visible. | Bajo |
| H3 | La latencia por operación del disco de OpenSearch es alta con poca carga: escrituras de 63 a 67 ms con 13 a 40 escrituras/s, frente a 1,5 a 12 ms en el disco de MongoDB de la misma VM (P6, caché de host ReadWrite; el de OpenSearch es P30 con caché ReadOnly). En una muestra del 2026-10-21 las latencias fueron de 4 a 6 ms, así que no es constante. No se probó qué diferencia entre los dos discos lo explica. | Medio |
| H4 | En una captura de una hora (2026-10-20) hubo ráfagas de lectura de hasta 470 lecturas/s y 86 MB/s, con latencia de lectura de hasta 1,8 s, de escritura de hasta 2,4 s y cola de hasta 743. Quien lee es el proceso de OpenSearch; Graylog y MongoDB casi no leen. | Medio |
| H5 | Una de las ráfagas (18:14:58 UTC) coincidió con una búsqueda interactiva desde la interfaz de Graylog, con tres tareas de búsqueda en ejecución en OpenSearch. Las ráfagas anteriores de esa hora (desde 17:56 UTC) no tuvieron ninguna petición de interfaz ni tareas de búsqueda. Quién hizo la búsqueda no está identificado; se informó que fue uso normal, sin verificar. | Medio |
| H6 | `read_ahead_kb` vale 65.536 (64 MB; lo habitual es 128 KB) en los tres discos NVMe de la VM y no se encontró dónde se define. En las ráfagas la lectura promedio fue de unos 215 kB, compatible con lectura ampliada por esa configuración; no se probó. | Medio |
| H7 | Las búsquedas no tenían límites: `query_time_range_limit` en `PT0S`, `cancel_after_seconds` en 0 y las opciones rápidas incluían "30 days" y "all messages". | Medio |
| H8 | Espacio: el 2026-10-15 el sistema de archivos de OpenSearch estaba al 79 % (601 GB de 768 GB), con 145 GB más que el 2026-10-09 (ritmo de ingesta de 21 a 24 GB/día). Graylog informa 583 GB entre sus index sets, 445,8 GB en los de las 8 aplicaciones (Business 226,7 y Orders 117,8 GB, el 60 % del total). La retención actual de esos sets es de 30 a 40 días. | Alto |
| H9 | En una pasada de solo lectura (sin borrar) sobre los índices de las 8 aplicaciones: 79,0 millones de documentos, de los cuales 50,7 millones (64 %) son de nivel Information con más de 7 días. Por proporción de documentos (no medido en bytes) serían unos 286 GB de los 446 GB. Los registros sin nivel (Unknown) son el registro HTTP, que ya está en index sets de 7 a 9 días. | Medio |

## Acciones Tomadas

| # | Hora (UTC) | Acción |
|---|---|---|
| 1 | 2026-10-21 14:57 | Configuré en Graylog `cancel_after_seconds` en 60 y `query_time_range_limit` en `P30D` (antes 0 y `PT0S`). Verifiqué por lectura posterior; las demás claves de esa configuración no cambiaron. |
| 2 | 2026-10-21 15:08 | Bajé `query_time_range_limit` a `P15D`. Verifiqué por lectura posterior; `cancel_after_seconds` sigue en 60. Reversión disponible llevando el valor otra vez a `P30D`. |

No he verificado todavía el efecto de estos límites en las ráfagas ni en las alertas, ni que Graylog los aplique también a usuarios administradores.

## Recursos afectados

| Recurso | Detalle |
|---|---|
| VM de Graylog SmartCloud | `sfcloud-monitoreo` (en Azure, `smartfran-graylog-pro`, `Standard_D8s_v6`; la relación entre ambos nombres se infiere por tamaño de disco) |
| Disco de datos de OpenSearch | `smartfran-graylog-pro-disk-opensearch`, 768 GB, Premium P30, caché de host ReadOnly (`nvme0n3`) |
| Configuración de búsqueda de Graylog | `SearchesClusterConfig` |
| Index sets de las aplicaciones de negocio | Admin, Business, Catalog, Orders, Person, Platform, Pos y Sales |

## Acciones propuestas

| # | Responsable | Acción | Estado |
|---|---|---|---|
| 1 | SRE | Bajar `read_ahead_kb` de `nvme0n3` a 128 en caliente (reversible, se pierde al reiniciar) y repetir la captura de una hora con búsquedas normales para comparar. | Por decidir (línea base tomada, sin aplicar) |
| 2 | SRE | Evaluar cambiar el caché de host del disco de OpenSearch de ReadOnly a None. Es un cambio en producción; antes hay que verificar en la documentación de Azure cómo se aplica y si interrumpe el disco. | Por decidir |
| 3 | SRE, PM | Decidir la retención: Information y Unknown 7 días, Warning o superior 30 días. Opción A: streams e index sets por nivel. Opción B: tarea diaria que borra los Information con más de 7 días sobre la estructura actual. SRE propone la opción B por el bajo uso en esta etapa. En ambas el borrado es definitivo. | Por decidir (confirmación pendiente) |
| 4 | SRE | Si se elige la opción B: escribir la tarea con modo de prueba por defecto, tandas de un día limitadas, fuera de horas pico, empezando por un servicio chico y con control de la latencia del disco. | Pendiente |
| 5 | SRE | Verificar que el límite de 60 segundos y de 15 días no corta búsquedas legítimas, y decidir qué hacer con que Warning o superior se conserve 30 días pero las búsquedas lleguen a 15. | Pendiente |

## Hallazgos secundarios

- El index set por defecto de Graylog guarda 20,6 GB (12 millones de documentos) de mensajes que ningún stream reclama; no se revisó qué son.
- Los sets de Business y Sales tienen 1 réplica en un solo nodo, por lo que sus réplicas quedan sin asignar (24 shards sin asignar el 2026-10-15) y esos índices figuran en amarillo.
