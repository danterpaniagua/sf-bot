# GITIN-1866 — Salud de queries durante campaña de marketing de Club Grido (2026-08-16)

## Resumen

El domingo 2026-08-16, Club Grido envió una campaña masiva de marketing que generó un pico de tráfico reportado de hasta 80 req/s POST y 100 req/s GET sobre MobileAppService (`SFCG-MOBI-01/02`). Se investigó la salud de las queries en `PNSSRL` (base monitoreada, refleja actividad sobre `SmartFran.Solution.SmartLoyalty`) durante la ventana de tráfico real confirmada por Graylog (16:00–21:00 UTC). El lado de base de datos se mantuvo saludable durante toda la ventana. Sin embargo, el análisis de logs IIS de MobileAppService reveló una tasa sostenida de respuestas 400 (Bad Request) y un evento aislado de latencia/500 al final de la ventana — hallazgos no visibles desde el lado de base de datos. La causa raíz de la tasa de 400 y la capacidad disponible para una campaña de mayor escala quedan como líneas de investigación abiertas (ver "Acciones propuestas").

## Tabla resumen

| Campo | Valor |
|---|---|
| Ticket Jira | [GITIN-1866](https://smartit-ar.atlassian.net/browse/GITIN-1866) |
| Caso | Salud de queries — campaña Club Grido 2026-08-16 |
| Base de datos | `SmartFran.Solution.SmartLoyalty` (monitoreo vía `PNSSRL`) |
| Severidad | Media |
| Detectado | 2026-08-18 (análisis retrospectivo del evento ocurrido 2026-08-16) |
| Resuelto | No aplica — ticket abierto, ver acciones propuestas |
| Responsable | Dante Paniagua, SRE |

## Causa raíz

No se identificó ninguna causa raíz de incidente en `PNSSRL`: no se detectó bloqueo alguno en la ventana investigada y el costo de CPU atribuible a MobileAppService fue marginal en todo momento. La causa de la tasa sostenida de respuestas 400 en los endpoints de autenticación/alta (`Login`, `SaveNewMember`, `RecoveryPassword`) **no está confirmada** — puede tratarse de comportamiento esperado a escala (errores de usuario, cuentas ya registradas) o de un defecto de validación amplificado por el tráfico de campaña; no se puede distinguir con los códigos de estado HTTP solamente.

## Hallazgos

| # | Hallazgo | Riesgo |
|---|---|---|
| H1 | Sin bloqueos en `PNSSRL` durante toda la ventana de pico real (16:00–21:00 UTC, cubierta en dos tramos: 15:00–20:00 y 20:00–21:00) | Bajo |
| H2 | MobileAppService (`SFCG-MOBI-01/02`) generó el mayor volumen de sesiones/conexiones de cualquier host, pero con costo de CPU marginal por query (~8.6ms promedio) — sin estrés medible sobre `PNSSRL` | Bajo |
| H3 | Tasa sostenida de respuestas 400 en logs IIS de MobileAppService: 21.7% del tráfico total (65.796 de 302.748 requests). Concentrada en `SaveNewMember` (66.5%), `Login` (52.1%) y `RecoveryPassword` (33.6%). Presente desde el inicio de la ventana, no es un pico puntual. Causa no confirmada | Medio |
| H4 | Único evento aislado de degradación: bucket 20:55–20:58 UTC con la peor latencia de cola de toda la ventana (máx. 6.573ms) y el único error 500 de las 302.748 requests (`GetCustomerProfile`, `SFCG-MOBI-02`). Coincide en el tiempo (no confirmado como relacionado) con un pico de intensidad de CPU en `SFCG-WEBS-03`, host distinto al de MobileAppService | Bajo |
| H5 | Volumen sostenido pico observado (~30 req/s en el bucket de 5 min más cargado) está por debajo del pico reportado de 80 POST + 100 GET req/s combinados — no reconciliado; puede tratarse de un pico de sub-5 minutos no resuelto por la granularidad usada, o de una estimación | Bajo |

## Métricas del evento

| Métrica | Valor |
|---|---|
| Ventana investigada (GMT/UTC) | 2026-08-16 15:00–21:00 |
| Ventana de pico real confirmada (Graylog) | 2026-08-16 16:00–21:00 UTC |
| Snapshots `PNSSRL_AuditSysprocesses` cubiertos | 72 (60 + 12, ~5 min de cadencia, sin huecos) |
| Bloqueos detectados | 0 |
| Requests IIS totales (MobileAppService) | 302.748 |
| Respuestas 200 | 236.201 |
| Respuestas 400 | 65.796 (21.7%) |
| Respuestas 404 | 750 |
| Respuestas 500 | 1 |
| Pico sostenido observado | ~30 req/s (bucket de 5 min más cargado, 16:05 UTC) |
| CPU total (todos los hosts, ventana 15:00–20:00) | 584.929 ms |
| CPU atribuible a MobileAppService (`MOBI-01/02`) | 14.185 ms (2.4% del total) |

## Consultas ejecutadas

| # | Query | Propósito |
|---|---|---|
| Q1 | Disponibilidad de datos (ventana principal) | Confirmar cobertura de snapshots 15:00–20:00 UTC |
| Q2 | Delta de CPU por SPID (top 50) | Identificar las sesiones con mayor consumo de CPU en la ventana |
| Q3 | Desglose de CPU por host | Atribuir el consumo de CPU a cada servicio/aplicación |
| Q4 | Verificación de bloqueos | Confirmar ausencia de bloqueos en toda la ventana |
| Q5 | Top sesiones por CPU con texto de query (`PNSSRL_TempdbProc`) | Identificar la query responsable del consumo en `SFCG-CLUB-01` (Query077) |
| Q6 | Chequeo de hora faltante (20:00–21:00 UTC) | Cerrar la cobertura hasta el final de la ventana de pico real confirmada por Graylog |

Ver `scripts.sql`.

## Acciones propuestas

1. Extraer una muestra de cuerpos de respuesta/motivos de error de las respuestas 400 en `Login`, `SaveNewMember` y `RecoveryPassword` para determinar si la tasa observada (21.7% general, hasta 66.5% en `SaveNewMember`) corresponde a comportamiento esperado a escala o a un defecto de validación — no evaluado en este ticket.
2. Análisis de capacidad/límites de `PNSSRL` ante una campaña de mayor escala que la del 2026-08-16 (día frío de invierno, de bajo impacto según lo confirmado en conversación) — evaluar reutilizar precedentes existentes de pruebas de carga en `events/` (`20260727_cpu_peaks_loadtest`, `20260803_cpu_peaks_loadtest`, `20260723_bloqueo_customerpointslog_loadtest`) en lugar de partir de cero. No evaluado en este ticket.

## Archivos de evidencia

| Archivo | Contenido |
|---|---|
| `investigation.md` | Notas de trabajo completas, en inglés — teoría de trabajo, hallazgos y conclusión final |
| `scripts.sql` | Las 6 queries ejecutadas contra `PNSSRL` durante la investigación |
| `Untitled-Message-Table-search-result(1).csv` | Exportación cruda de logs IIS de Graylog (302.748 filas, `SFCG-MOBI-01/02`, ventana 15:25–20:55 UTC) |

## Hallazgos secundarios

- `SFCG-CLUB-01` (sitio Club Grido) ejecutó repetidamente **Query077** (`AvailablePromotion`, `Domain\Query\Query077-sql.xml` en `SmartLoyalty.WebService`) — 14+ veces en la ventana, ~4.000–6.700ms de CPU y ~12.000 lecturas lógicas cada vez, vía `PNSSRL_TempdbProc`. Costo explicado por un `CROSS JOIN` entre dos table-valued params (`@BranchOfficeTableTmp × @PromotionTmp`) dentro de `SmlSupp.PromotionBranchOffice`. No genera bloqueos ni escala en el tiempo — candidato a optimización, pero no vinculado a la campaña.
- `SFCG-WSV2-01` (WebServiceV2) fue el mayor consumidor de CPU de toda la ventana 15:00–20:00 (306.890ms, ~mitad del total) pero no aparece en el top 20 de `PNSSRL_TempdbProc` (sin huella en tempdb) — su query no fue identificada con las tablas de captura disponibles. Carga estable durante toda la ventana, no concentrada en el patrón de tráfico de la campaña, y corresponde a un servicio distinto al de MobileAppService. No vinculado a este ticket.
