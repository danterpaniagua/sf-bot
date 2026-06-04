# [Fraude Puntos] Actividad irregular de transferencias — 21/05/2026

## Resumen

Actividad fraudulenta de transferencias de puntos detectada entre las 23:00 y las 02:00 (hora local) del 21 de mayo de 2026. Canal predominante: APP.

## Patrones identificados

| Patrón | Detalle |
|---|---|
| Explotación de duplicados + límite diario | Emisor ejecutó 4 transferencias por 28.000 pts. Dos pares procesados con 22 y 35 segundos de diferencia con parámetros idénticos. La plataforma no rechaza transferencias duplicadas en tiempo real. Límite diario (8.000 pts) superado en 3,5×. |
| Consolidación — cuenta hub | Cuenta receptora con 24.100 pts preexistentes recibe 12.000 pts adicionales en el evento. Saldo final: 36.100 pts. |
| Rapid accumulate-and-transfer | Cuenta receptora reenvía puntos a cuenta del mismo apellido en menos de 2 minutos tras recibirlos. Límite diario superado (8.715 pts enviados). |
| Transferencia circular | Dos cuentas se transfieren puntos recíprocamente con 16 minutos de diferencia. |
| Fan-in | 2 cuentas receptoras recibieron de múltiples emisores distintos en la ventana. |
| Registro sistémico | Registrador único (`334C1371-DB4D-C86D-9BBE-08D1B05CD52F`) con 28 cuentas emisoras registradas entre 2021-12-27 y 2026-05-21 (WEB y APP). Una cuenta creada el día del evento. |
| Identidad no resuelta | 3 cuentas sin registro de persona válido (campos con GUID en lugar de nombre/documento/email). |

## Métricas del evento

| Métrica | Valor |
|---|---|
| Ventana analizada (GMT) | 2026-05-21 02:00 – 08:00 +00:00 |
| Transferencias en ventana | 40 |
| Puntos totales transferidos | 124.350 |
| Canal predominante | APP (36 de 40 transferencias) |
| Emisores con incumplimiento de límite diario | 2 |
| Puntos involucrados en incumplimientos | 36.715 (28.000 + 8.715) |
| Cuentas receptoras con actividad post-evento | 3 |
| Cuentas registradas por registrador sistémico | 28 |

## Archivos de evidencia

Ruta: `events/20260521_fraude_evidencia/`

| Archivo | Contenido |
|---|---|
| `01_queries_investigacion.sql` | Consultas Q1–Q6 utilizadas en la investigación |
| `02_20260521_transferencias.csv` | Identidad y puntos por participante — exportar Q3 desde SSMS |
| `03_20260521_emisores.csv` | Emisores con validación de límite diario — exportar Q4 desde SSMS |
| `04_pointslog_transferencias_20260521.csv` | Exportación raw de `sml.CustomerPointsLog` para las transferencias del evento — SSMS Results to File |
| `05_20260521_transferencias_pm.csv` | Detalle de transferencias para PMs: nombres, DNIs, canal, flags de fraude |

Los datos de identidad de los participantes (nombres, documentos, emails) se encuentran en los archivos CSV. No se incluyen en este ticket.
