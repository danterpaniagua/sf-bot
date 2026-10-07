# GITIN-1969 — Línea base de tráfico Req/s para MobileAppService (SFCG-MOBI-01/02)

**Tags:** SmartLoyalty, MobileAppService, Obserbavilidad, PROD, SRE

## Resumen

No existía una línea base histórica de tráfico GET/POST por fin de semana para `SFCG-MOBI-01`/`SFCG-MOBI-02` (MobileAppService), lo que impedía juzgar cuantitativamente si un pico de tráfico observado en un fin de semana puntual era anómalo o estaba dentro de la variación normal. GITIN-1965 es el ticket padre del trabajo de revisión de alertas Req/s en la flota, desprendido en dos tickets hijos: GITIN-1966 (auditoría de triggers/umbrales a nivel flota, `loyalty/events/20260830_reqs_alerts_zabbix_audit/`) y este ticket, GITIN-1969, que cubre específicamente el análisis de línea base de tráfico para MobileAppService. Durante el análisis se detectó tráfico real elevado en `SFCG-MOBI-02` el fin de semana del 2026-08-29/30, y se identificó una inconsistencia de retención de historial en los ítems de CPU/RAM de ambos hosts, corregida como parte de este ticket.

## Tabla resumen

| Campo | Valor |
|---|---|
| Ticket Jira | GITIN-1969 |
| ID alerta | N/A — análisis proactivo, no originado por una alerta puntual |
| Sistema | SmartLoyalty MobileAppService (`SFCG-MOBI-01`, `SFCG-MOBI-02`) |
| Severidad | Media — análisis de observabilidad y ajuste de retención, sin caída de servicio |
| Detectado | N/A — trabajo proactivo |
| Resuelto | 2026-08-31 |
| Responsable | Dante Paniagua |

## Causa raíz

No existía una línea base cuantitativa de tráfico Req/s por fin de semana para MobileAppService, por lo que un operador que observara tráfico elevado en un momento puntual no tenía forma de compararlo contra el comportamiento típico de fines de semana anteriores. Por separado, los ítems de CPU/RAM utilization en ambos hosts quedaron con una retención de historial de solo 7 días desde su creación, sin alinearse con la retención de 180 días ya configurada en los ítems GET/POST de los mismos hosts — una inconsistencia de configuración, no un incidente.

## Hallazgos

| # | Hallazgo | Riesgo |
|---|---|---|
| H1 | No existía línea base histórica de tráfico GET/POST por fin de semana para Mobi01/Mobi02, dificultando distinguir tráfico anómalo de variación normal | Medio |
| H2 | El fin de semana 2026-08-29/30 mostró tráfico elevado en `SFCG-MOBI-02`, concentrado en un pico puntual sábado 16:00-17:00 hora local (~2,5-5x el mismo horario en los 3 fines de semana previos); el total del servicio (Mobi01+Mobi02) cerró un 34% por encima del promedio base | Medio |
| H3 | Los ítems de CPU/RAM utilization en ambos hosts tenían retención de historial de solo 7 días, inconsistente con los ítems GET/POST (180 días) de los mismos hosts | Bajo |
| H4 | La duda sobre si los triggers de GITIN-1918 enrutaban correctamente sus alertas (por un posible desajuste de tag `EMAIL`/`MAIL` en la acción 10) quedó resuelta como no aplicable — según `docs/zabbix_observability.md` (GITIN-1961/GITIN-1966), la acción fue corregida y habilitada el 2026-08-28. No se re-ejecutó `action.get` en este ticket; se tomó como fuente la documentación ya existente | Bajo |
| H5 | La brecha de umbral ~13x entre Mobi01 y Mobi02 en los triggers de Spike (hallazgo abierto en GITIN-1966) es consistente con la diferencia real de tráfico entre ambos hosts, no con un error de copy-paste — confirmado cruzando los datos de línea base de este ticket contra el hallazgo documentado en GITIN-1966 | Bajo |
| H6 | No se verificó si los triggers de Spike de `SFCG-MOBI-02` (26745-26747) dispararon efectivamente durante la ventana de pico del sábado 2026-08-29 16:00-18:00 hora local | Bajo |

## Recursos afectados

| Recurso | Detalle |
|---|---|
| Host | `SFCG-MOBI-01` |
| Host | `SFCG-MOBI-02` |
| Ítem Zabbix | `IIS: Method GET/POST requests per second` (`_Total`), itemids 52784/52792 (Mobi01), 52742/52750 (Mobi02) |
| Ítem Zabbix | `Windows: CPU utilization`, itemids 50609 (Mobi01), 50665 (Mobi02) |
| Ítem Zabbix | `Windows: Memory utilization`, itemids 50616 (Mobi01), 50672 (Mobi02) |

## Comandos ejecutados

| # | Comando / Script | Propósito |
|---|---|---|
| C1 | `item.get` sobre ambos hosts | Inventario completo de ítems — localizar los ítems GET/POST reales y detectar duplicados |
| C2 | `item.get` (history/trends) | Confirmar retención de historial de los ítems GET/POST antes de usarlos en comparaciones now-Nw |
| C3 | `analyze_weekend_get_post.py` | Estadísticas por host/servicio y desglose hora a hora (sáb/dom, hora local), sobre datos ya obtenidos |
| C4 | `fetch_get_post_weeks.sh` | Pull dinámico de historial GET/POST (now, now-1w, now-2w, now-3w) — script escrito, aún no ejecutado contra Zabbix en vivo (ver acción 5) |
| C5 | `item.get` (history/trends) | Verificar retención de historial de los ítems CPU/RAM |
| C6 | ⚠️ `item.update` — retención CPU/RAM | Elevar retención de historial de 7d a 180d en los 4 ítems CPU/RAM |
| C7 | `item.get` (history/trends) | Confirmar que C6 se aplicó correctamente |

Detalle completo en `scripts.sh`, incluyendo nota de procedencia: los datos de línea base analizados en C3 fueron obtenidos originalmente con dos scripts ya reemplazados (ambos ejecutados en su momento contra Zabbix en vivo), luego consolidados en `fetch_get_post_weeks.sh` (C4) sin volver a correr el pull end-to-end todavía. `trigger.get`/`action.get` no se ejecutaron en este ticket — los hallazgos H4/H5 provienen de `docs/zabbix_observability.md` (GITIN-1961/GITIN-1966).

## Acciones propuestas

1. **(SRE) Completado** — Construcción de scripts reutilizables (`fetch_get_post_weeks.sh`, `analyze_weekend_get_post.py`) para calcular la línea base de tráfico GET/POST de MobileAppService de forma dinámica (now/now-1w/now-2w/now-3w), sin fechas fijas.
2. **(SRE) Completado** — Elevación de la retención de historial de los ítems CPU/RAM utilization de `SFCG-MOBI-01`/`SFCG-MOBI-02` de 7 a 180 días, alineada con los ítems GET/POST de los mismos hosts.
3. **(SRE) Completado** — Confirmación de que los triggers de GITIN-1918 enrutan correctamente sus alertas (acción 10 corregida y habilitada desde GITIN-1961); no requiere acción adicional.
4. **(SRE) Completado** — Verificación de que la brecha de umbral ~13x entre Mobi01 y Mobi02 (hallazgo abierto en GITIN-1966) es consistente con la diferencia real de tráfico entre ambos hosts; a comunicar como respuesta a ese hallazgo en GITIN-1966.
5. **(SRE) Pendiente** — Verificar mediante `problem.get` si los triggers de Spike de Mobi02 (26745-26747) dispararon durante la ventana de pico del sábado 2026-08-29 16:00-18:00 hora local.
6. **(SRE) Pendiente** — Ejecutar `fetch_get_post_weeks.sh` contra Zabbix en vivo para validar el pull dinámico end-to-end; los datos analizados en este ticket fueron obtenidos con las versiones anteriores de los scripts (ya reemplazadas), no con esta versión consolidada.
7. **(SRE) Pendiente, fuera de alcance de este ticket** — Si se desea una alerta permanente de comparación semana a semana, diseñarla como parte de la limpieza de GITIN-1966, replicando la lógica explícita de manejo de huecos de datos usada en `analyze_weekend_get_post.py` (Zabbix no puede expresar esa lógica de forma nativa con `avg()`).

## Hallazgos secundarios

Si el tráfico elevado del fin de semana 2026-08-29/30 corresponde a un evento de negocio específico ("apertura de temporada") no pudo confirmarse ni descartarse con los datos disponibles — solo se confirmó la elevación de tráfico en sí, no su causa de negocio.
