# Eventos — 20260816_club_grido_campaign_query_health

## 2026-08-18 08:40 — Inicio de investigación

Abrí la investigación a partir del reporte de una campaña masiva de marketing de Club Grido el domingo 2026-08-16, con pico reportado de 80 req/s POST y 100 req/s GET. Convertí la ventana solicitada (12:00–17:00 UTC-3) a GMT (15:00–20:00 UTC) y confirmé que el servicio afectado por la campaña es MobileAppService (`SFCG-MOBI-01/02`). Obtuve la URL del ticket Jira GITIN-1866.

## 2026-08-18 08:45 — Disponibilidad de datos confirmada

Ejecuté Q1 sobre `PNSSRL_AuditSysprocesses`: confirmé 60 snapshots entre 15:01:00 y 19:56:01 UTC, cadencia de ~5 minutos, cobertura completa de la ventana 15:00–20:00 UTC.

## 2026-08-18 08:46 — Delta de CPU por SPID

Ejecuté Q2 (top 50 por delta de CPU). Confirmé `blocked = 0` en todas las filas del top 50. Los mayores consumidores individuales fueron sesiones de `SFCG-WSIT-01` y `SFCG-WEBS-02/03`, no de MobileAppService.

## 2026-08-18 08:47 — Desglose por host y verificación de bloqueos

Ejecuté Q3 (desglose de CPU por host) y Q4 (verificación de bloqueos, 0 filas). Confirmé que `SFCG-WSV2-01` (WebServiceV2) fue el mayor consumidor de CPU de la ventana (306.890ms, ~mitad del total), mientras que MobileAppService (`SFCG-MOBI-01/02`) tuvo el mayor volumen de conexiones/sesiones pero CPU marginal (14.185ms, 2.4% del total).

## 2026-08-18 08:48 — Cruce con datos de Graylog (primera muestra)

Recibí conteo de hits por endpoint desde Graylog (solo respuestas OK) para la ventana original. Confirmé tiempos de respuesta saludables (menores a 100ms en promedio) en los endpoints de mayor volumen, consistente con el bajo costo de CPU medido para MobileAppService.

## 2026-08-18 08:49 — Identificación de Query077 vía TempdbProc

Ejecuté Q5 sobre `PNSSRL_TempdbProc`. Identifiqué que `SFCG-CLUB-01` ejecutó repetidamente Query077 (`AvailablePromotion`), explicando la totalidad de su consumo de CPU en la ventana. El consumidor dominante (`SFCG-WSV2-01`) no apareció en el top 20 de `TempdbProc` — sin huella en tempdb, su query queda sin identificar con las tablas de captura disponibles.

## 2026-08-18 08:51 — Corrección de ventana de pico real

Recibí una segunda tabla de Graylog que mostró mayor volumen de tráfico en la ventana 16:00–21:00 UTC, distinta a la ventana 15:00–20:00 UTC originalmente calculada. Detecté un hueco de cobertura en la hora 20:00–21:00 UTC.

## 2026-08-18 08:58 — Cierre de cobertura de la hora faltante

Ejecuté Q6 sobre la ventana 20:00–21:00 UTC (disponibilidad, bloqueos, desglose por host). Confirmé 12 snapshots sin huecos, cero bloqueos, y CPU de MobileAppService nuevamente marginal (327ms en `MOBI-02`, 0ms en `MOBI-01`). Cobertura completa de la ventana real de pico (16:00–21:00 UTC) confirmada.

## 2026-08-18 09:05 — Análisis de logs IIS crudos

Recibí y procesé la exportación cruda de logs IIS de Graylog (302.748 filas, `SFCG-MOBI-01/02`, ventana 15:25–20:55 UTC). Detecté una tasa sostenida de respuestas 400 (21.7% del tráfico total, hasta 66.5% en `SaveNewMember`), presente desde el inicio de la ventana y no vinculada a un pico puntual — hallazgo no visible desde el lado de base de datos. Detecté también un evento aislado de degradación de latencia y el único error 500 de todo el dataset, ambos concentrados en el bucket 20:55–20:58 UTC.

## 2026-08-18 09:10 — Redefinición de alcance del ticket

El alcance de este ticket se acotó a los hallazgos ya confirmados (lado de base de datos saludable, tasa de 400 sostenida, evento aislado de latencia/500). La causa raíz de la tasa de 400 y el análisis de capacidad/límites ante una campaña de mayor escala quedan como acciones propuestas para una investigación futura, sin resolver en este ticket.

## 2026-08-18 09:12 — Cierre de artefactos

Generé `ops.md`, `scripts.sql` y esta bitácora a partir del estado final de `investigation.md`.
