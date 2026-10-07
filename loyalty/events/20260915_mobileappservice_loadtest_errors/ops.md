# GITIN-2053 — Errores reportados por Grido durante una campaña real (MobileAppService)

## Resumen

Grido reportó errores y latencia elevada desde sus sistemas contra **SmartLoyalty Mobile** (MobileAppService, `mobileservice.clubgrido.com.ar:8043`) durante tráfico real de clientes generado por una campaña de marketing el 15/09/2026 (**no una prueba de carga** — corregido 2026-09-16), con pico reportado a las 12:00hs ARG (15:00 UTC). La investigación cubrió la ventana completa de la campaña (02:40–15:48 UTC, confirmada como el rango real de la campaña) y identificó **tres causas independientes entre sí (no encadenadas — cada una ocurre en una ventana horaria distinta y sin relación mecánica entre ellas)**: una tarea programada de mantenimiento colisionando con la ventana de la campaña a las `15:09` UTC (ya corregida), un bloqueo diario de base de datos entre `06:15` y `07:31` UTC ya registrado en otro ticket abierto (descartado explícitamente como causa del evento de las `15:09` UTC — el lock ya estaba liberado ~7.5 horas antes), y un patrón de presión de capacidad/distribución de tráfico entre los dos servidores del pool durante el pico `15:00`–`15:20` UTC que aún no tiene causa raíz confirmada. Al tratarse de clientes reales (no tráfico sintético de test), el impacto de este evento es sobre usuarios finales de Grido.

## Tabla resumen

| Campo | Valor |
|---|---|
| Ticket Jira | [GITIN-2053](https://smartit-ar.atlassian.net/browse/GITIN-2053) |
| Caso | Errores/latencia reportados por Grido durante una campaña real — MobileAppService |
| Servidor/Plataforma | `SFCG-MOBI-01`/`SFCG-MOBI-02` (MobileAppService, IIS), `SFCG-DB01` (`SmartFran.Solution.SmartLoyalty`) |
| Severidad | Alta (revisado 2026-09-16 — impacto sobre clientes reales durante una campaña, no tráfico sintético de test) |
| Detectado | 2026-09-15 |
| Resuelto | Parcial — ver Acciones propuestas |
| Responsable | Dante Paniagua (SRE) |

## Causa raíz

**Hallazgo 1 (cerrado):** la tarea programada `CleanCSVLogs` en `SFCG-MOBI-02` ejecuta diariamente un `iisreset` completo (detiene IIS, borra logs `.csv`/`.svclog`, reinicia IIS) como `SYSTEM`. Su disparador diario coincide con `~15:09` UTC, dentro de la ventana de la campaña de hoy, produciendo un corte real de IIS de ~20–30s y 53 respuestas `503` reales durante ese corte.

**Hallazgo 2 (referencia a ticket ya abierto, no remediado en este ticket):** entre `06:00` y `08:00` UTC, el job `PNSSRL_MantenimientoIndices` ejecutó un `ALTER INDEX ... REBUILD` (no `ONLINE`) sobre `Sml.CustomerPointsLog`, manteniendo un lock `Sch-M` durante ~45 minutos. Esto bloqueó las consultas de `Benefits/GetCustomerStatus`/`Customer/GetCustomerProfile` en `SFCG-MOBI-01`, generando cientos de `TIMEOUT` del lado de Grido. Este mecanismo ya está diagnosticado y abierto en [GITIN-1981](https://smartit-ar.atlassian.net/browse/GITIN-1981) (originado en [GITIN-1669](https://smartit-ar.atlassian.net/browse/GITIN-1669)) — esta es la tercera ocurrencia confirmada del mismo problema, sin corrección aplicada aún en el job.

**Hallazgo 3 (en investigación):** durante el pico de la campaña (`15:00`–`15:20` UTC), la distribución de tráfico entre los dos servidores del pool del Load Balancer (`SFCG-MOBI-LB`) estuvo fuertemente desbalanceada — `SFCG-MOBI-01` recibió solo 1.4% del tráfico total y `SFCG-MOBI-02` el 98.6% restante — sin que el health probe del LB (tipo TCP, sin verificación a nivel de aplicación) reportara ningún problema. En paralelo, una porción significativa de las fallas reportadas por Grido en esa ventana (2.653 de 4.616) corresponden a solicitudes que nunca llegaron a completarse del lado del servidor (sin respuesta HTTP registrada), consistente con presión de capacidad real bajo carga. Causa raíz aún no confirmada.

## Hallazgos

| # | Hallazgo | Riesgo |
|---|---|---|
| H1 | `iisreset` diario (`CleanCSVLogs`, `SFCG-MOBI-02`, disparador `~15:09` UTC) colisiona con la ventana de la campaña, produciendo 53 respuestas `503` reales | Alto — **remediado** |
| H2 | Bloqueo diario de `Sml.CustomerPointsLog` por `PNSSRL_MantenimientoIndices` (`06:15`–`07:31` UTC) — tercera ocurrencia del problema ya abierto en GITIN-1981 | Alto — pendiente en GITIN-1981, no en este ticket |
| H3 | Distribución de tráfico desbalanceada entre `SFCG-MOBI-01` (1.4%) y `SFCG-MOBI-02` (98.6%) durante el pico, no detectada por el health probe TCP del LB | Medio — en investigación |
| H4 | 2.653 fallas (`TIMEOUT`/`CIRCUIT_OPEN`/`CONN_RESET`/`BULKHEAD_REJECTED`) sin respuesta de servidor durante el pico `15:00`–`15:20` UTC, consistente con presión de capacidad | Medio — en investigación |

## Métricas del evento

| Métrica | Valor |
|---|---|
| Ventana de la campaña (UTC) | `02:40`–`15:48` |
| Llamadas totales registradas por Grido | 52.479 |
| Fallas en alcance de este ticket (excluye `HTTP_4XX` de `Account/Login`/`RecoveryPassword`, tratado como fricción genuina de autenticación de clientes reales bajo volumen elevado, no tráfico de test) | 3.750 (8.1%) |
| Pico de tráfico | `15:00`–`15:20` UTC (12.526 + 7.064 + 3.930 llamadas) |
| Errores `HTTP 5XX` reales en el pico (`15:00`–`15:20` UTC) | 6 |
| Fallas sin respuesta de servidor en el pico (`15:00`–`15:20` UTC) | 2.653 |
| Distribución de tráfico `-01`/`-02` en el pico | 1.4% / 98.6% |
| Duración del bloqueo SQL (`PNSSRL_MantenimientoIndices`) | ~45 min (`06:46`–`07:31` UTC) |

## Consultas ejecutadas

| # | Query | Propósito |
|---|---|---|
| Q1 | Actividad bloqueada en la ventana `05:45`–`08:15` UTC | Identificar sesiones bloqueadas y su causa |
| Q2 | Sesiones activas contra `SmartFran.Solution.SmartLoyalty` en la misma ventana | Confirmar qué se estaba ejecutando, no solo qué estaba bloqueado |
| Q3a/Q3b | Descubrimiento de columnas de `Etl.EtlOperationExecution`/`EtlOperationConfig` | Validar supuestos de esquema antes de consultar |
| Q3c | Detalle de ejecución de `PNSSRL_MantenimientoIndices` (`PNSSRL_DetallesEjecucionTablasModulos`) | Confirmar si el job siempre apunta a la misma tabla/índice |
| Q4 | Historial de backups de `SmartFran.Solution.SmartLoyalty` en la ventana | Descartar un backup como factor contribuyente |

Detalle completo en `scripts.sql`.

## Acciones propuestas

1. **(SRE)** — Eliminado el disparador diario `~15:09` UTC de la tarea `CleanCSVLogs` en `SFCG-MOBI-02` — solo queda el disparador "At startup". Aplicado.
2. **(SRE)** — Confirmar si `SFCG-MOBI-01` requiere el mismo tratamiento en su propio disparador (`05:00` UTC) — descartado por ahora: sin errores HTTP reales asociados en esa ventana.
3. **(SRE)** — Escalar la evidencia de este ticket (impacto real y confirmado sobre MobileAppService durante una campaña real, con clientes reales afectados) como refuerzo a GITIN-1981, sin duplicar el hallazgo como un problema nuevo.
4. **(SRE)** — Confirmar el modo de distribución del Load Balancer `SFCG-MOBI-LB` (hash de 5 tuplas u otro) y evaluar si el patrón de tráfico observado (conexiones persistentes/multiplexadas) explica el desbalance `-01`/`-02`.
5. **(SRE)** — Instalar un Data Collector Set de contadores de rendimiento (CPU, cola de requests, thread pool) en ambos servidores antes de la próxima campaña de alto tráfico — no existen datos históricos de este tipo para confirmar la causa raíz de H3/H4.
6. **(SRE)** — Solicitar a Grido la clasificación de errores de su aplicación/backend (o el texto de excepción crudo) para confirmar si agrupa fallas de transporte como códigos HTTP genéricos.

## Hallazgos secundarios

Durante el análisis de logs de MobileAppService en Graylog se detectó que el campo `Password` se registra **en texto plano** en los eventos `LoginSuccess` del log de servicio (`svclog_input`). Este hallazgo es independiente del alcance de este ticket — pendiente de decisión sobre si amerita un ticket propio de seguridad.

## Archivos de evidencia

| Archivo | Contenido |
|---|---|
| `scripts.sql` | Consultas SQL ejecutadas (Q1–Q4) |
| `data/pnssrl_blocking_0646_0731.txt` | Captura de bloqueo SQL en `Sml.CustomerPointsLog` |
| `data/pnssrl_mantenimientoindices_sweep_summary.txt` | Detalle de ejecución de `PNSSRL_MantenimientoIndices` |
| `data/sfcg-mobi-02_activitylog_24h.txt` | Activity Log de Azure para `SFCG-MOBI-02` (últimas 24h) |
| `data/sfcg-mobi-02_eventlog_1505-1515.txt` | Event Log de `SFCG-MOBI-02` confirmando el mecanismo `iisreset` |
| `data/sfcg-mobi-02_perfcounter_eventlog_scan.txt` | Verificación de disponibilidad de contadores de rendimiento históricos |
| `data/httperr_sfcg-mobi-01_1455-1525.txt`, `data/httperr_20260915_0455_0510_SFCG-MOBI-01.txt` | `httperr.log` de `SFCG-MOBI-01` en ambas ventanas relevantes |
| `data/httperr_sfcg-mobi-02_1400-1555.txt` | `httperr.log` de `SFCG-MOBI-02`, ventana completa de la campaña |
| `data/smartfrancall_aggregate_summary.txt`, `data/smartfrancall_hourly_breakdown.txt`, `data/smartfrancall_1500_1520_status_breakdown.txt` | Análisis agregado de `SmartFranCall.log` (log de Grido, no copiado al repositorio por contener PII) |
| `data/graylog_mobi_lockwindow_0615_0735.json`, `data/graylog_lockwindow_perminute_buckets.txt`, `data/graylog_lockwindow_analysis_summary.txt` | Cruce en Graylog confirmando el hueco de respuestas durante el bloqueo SQL |
| `data/graylog_errors_1500_1520_full.json`, `data/graylog_errors_1500_1520_by_cardinality.txt`, `data/graylog_errors_1500_1520_10min_analysis.txt`, `data/graylog_cardinality_totalvolume_1500_1520.txt` | Errores y distribución de tráfico por instancia (`ServiceCardinality`) en el pico `15:00`–`15:20` UTC |
| `data/graylog_latency_1500_1520.json`, `data/graylog_latency_1500_1520_analysis.txt` | Muestra de tráfico total (no solo errores) confirmando el desbalance `-01`/`-02` |
| `data/sfcg-mobi-lb_dipavailability_1445_1530.json` | Métrica `DipAvailability` del Load Balancer en la ventana del pico |
| `data/graylog_streams_list.json` | Referencia — stream `SML_MobileApp` y su regla de enrutamiento |
