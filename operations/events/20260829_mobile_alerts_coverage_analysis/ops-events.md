# Eventos — 20260829_mobile_alerts_coverage_analysis

## 2026-08-29 10:00 — Inventario completo de ítems Zabbix (Mobi01/Mobi02)

**Comando:** C1 — `item.get` sobre ambos hosts
**Resultado:**
He obtenido el inventario completo de ítems de `SFCG-MOBI-01` y `SFCG-MOBI-02`, guardado en `data/c2_all_items.json`.

He identificado los ítems GET/POST reales sobre la instancia `_Total` (52784/52792 en Mobi01, 52742/52750 en Mobi02) a usar como línea base, y he detectado un par duplicado más nuevo sobre la instancia `{$IIS.APP.NAME}` (53257-53260) además de dos ítems agregados personalizados (53249/53250, 53735) — duplicación que he dejado registrada como hallazgo secundario, fuera del alcance de este ticket.

## 2026-08-29 — Obtención de historial GET/POST (3 fines de semana previos + fin de semana actual)

**Resultado:**
He obtenido el historial de las 4 métricas (GET/POST x Mobi01/Mobi02) para los fines de semana 2026-08-08/09, 08-15/16, 08-22/23 y 08-29/30, mediante scripts de pull dedicados a cada fecha. Los datos crudos quedaron persistidos en `data/`. Esos scripts iniciales fueron reemplazados el 2026-08-31 por el `fetch_get_post_weeks.sh` consolidado (ver entrada más abajo).

## 2026-08-29/31 — Análisis estadístico y desglose horario

**Comando:** C3 — `analyze_weekend_get_post.py`
**Resultado:**
He calculado percentiles por host/métrica, el total por servicio (Mobi01+Mobi02 combinado) y el desglose hora a hora (sábado/domingo, hora local UTC-3) para las 4 semanas obtenidas.

He confirmado tráfico elevado en Mobi02 el fin de semana 2026-08-29/30, concentrado en un pico puntual sábado 16:00-17:00 (~2,5-5x el mismo horario en los 3 fines de semana previos), con el total del servicio un 34% por encima del promedio base. No he podido confirmar ni descartar si ese tráfico corresponde a un evento de negocio específico — solo la elevación de tráfico en sí queda confirmada.

## 2026-08-31 — Refactor de los scripts a forma dinámica (now/now-1w/now-2w/now-3w)

**Resultado:**
He consolidado los scripts de pull en `fetch_get_post_weeks.sh`, que calcula el sábado más reciente de forma relativa a la fecha de ejecución y obtiene esa semana más N fines de semana previos, sin fechas fijas. He adaptado `analyze_weekend_get_post.py` para descubrir los fines de semana disponibles en `data/` a partir del contenido de cada archivo (no del nombre), tratando el más reciente como punto de comparación. He verificado que el analizador reproduce exactamente los mismos números sobre los datos ya obtenidos. `fetch_get_post_weeks.sh` en sí todavía no se ejecutó contra Zabbix en vivo en esta sesión — queda como acción pendiente.

## 2026-08-31 — Confirmación de retención de historial en ítems GET/POST

**Comando:** C2 — `item.get` (history/trends)
**Resultado:**
He confirmado que los 4 ítems GET/POST tienen retención de historial de 180 días (trends 730 días) — suficiente para cualquier comparación now-Nw dentro de un rango de varios meses, descartando la retención como limitante para este análisis.

## 2026-08-31 — Revisión de diseño: comparación semana a semana no debe implementarse como ítem calculado de Zabbix

**Resultado:**
He evaluado la posibilidad de implementar la comparación now vs now-Nw como ítems calculados nativos de Zabbix (con shift `now-Nw`) y la he descartado por dos motivos: sumaría un cuarto esquema de alertas superpuesto sobre Mobi01/Mobi02 (ya señalados con 3 esquemas no coordinados en GITIN-1966), y la función `avg()` nativa no puede distinguir entre "sin tráfico" y "sin datos" durante los apagones nocturnos de Mobi02 — la lógica explícita de manejo de huecos que sí implementa `analyze_weekend_get_post.py` no es expresable de forma nativa en Zabbix.

## 2026-08-31 — Verificación y corrección de retención de historial en ítems CPU/RAM

**Comando:** C5, C6, C7 — `item.get` / ⚠️ `item.update` / `item.get`
**Resultado:**
He encontrado que los ítems de CPU/RAM utilization en ambos hosts tenían retención de historial de solo 7 días, inconsistente con los ítems GET/POST (180 días) de los mismos hosts. He elevado la retención de los 4 ítems (50609, 50616, 50665, 50672) a 180 días mediante `item.update`, y he confirmado el cambio con un `item.get` posterior — los 4 ítems quedaron con `history=180d`, `trends=365d`.

## 2026-08-31 — Redacción del ticket

**Resultado:**
He redactado `ops.md` y este archivo a partir del estado convergido de `investigation.md`. He dejado pendiente verificar si los triggers de Spike de Mobi02 (26745-26747) dispararon durante la ventana de pico observada, y ejecutar `fetch_get_post_weeks.sh` contra Zabbix en vivo para validar el pull dinámico end-to-end.
