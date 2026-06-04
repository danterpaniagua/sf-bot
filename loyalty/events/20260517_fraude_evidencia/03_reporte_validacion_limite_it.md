# Reporte Técnico — Ausencia de validación de límite diario de transferencia de puntos
**Fecha del evento:** 2026-05-17
**Hora del evento:** 09:26 UTC-3 (12:26 GMT)
**Investigador:** Dante Paniagua, SRE
**Alcance:** IT — hallazgos técnicos y controles de sistema

---

## Resumen del evento

El día 2026-05-17 a las 09:26 (UTC-3) se registró una transferencia de **24.785 puntos** desde la cuenta de Juan Esteban Boccasile (DNI 7786506) hacia la cuenta de Romina Boccasile (DNI 27711999). La operación fue procesada y confirmada por la plataforma sin error ni rechazo.

El límite diario de transferencia establecido en el Reglamento de Club Grido es de **8.000 puntos**. La transferencia ejecutada representa **3,1 veces ese límite** (+16.785 pts sobre el máximo permitido).

---

## Hallazgo técnico: ausencia de validación server-side

### Evidencia

| Campo | Valor |
|---|---|
| `sml.CustomerPointsLog.Id` (emisor) | 378416697 |
| `sml.CustomerPointsLog.Id` (receptor) | 378416698 |
| `LogDate` | `2026-05-17 12:26:18.2531382 +00:00` |
| Puntos transferidos | 24.785 |
| Límite diario reglamentario | 8.000 |
| Exceso | +16.785 |
| Balance post-evento emisor (`smlst.CustomerPointsLog`) | 0 |
| Balance post-evento receptor (`smlst.CustomerPointsLog`) | 31.455 |

La operación fue escrita en `sml.CustomerPointsLog` como un par atómico (IDs consecutivos 378416697 / 378416698), lo que indica que la capa de aplicación ejecutó la transferencia sin consultar ni acumular el total diario enviado por el emisor previo al commit.

### Causa raíz

No existe validación en tiempo real del acumulado diario de puntos transferidos por cuenta. La plataforma registra cada transferencia de forma individual sin verificar si el emisor ya alcanzó o superó el límite diario de 8.000 puntos antes de procesar la operación.

Esto aplica tanto a la capa de aplicación (WebService / WebServiceV2) como al motor de base de datos: no se detectaron constraints, triggers ni stored procedures en `SmartFran.Solution.SmartLoyalty` que rechacen o bloqueen transferencias que superen el límite reglamentario.

### Patrón recurrente

Este es el **tercer evento confirmado** con violación de límites de transferencia en la plataforma:

| Fecha | Modalidad | Límite superado |
|---|---|---|
| 2026-05-14 | Fan-in multi-emisor coordinado | Diario y semanal |
| 2026-05-15 | Fan-in multi-emisor coordinado | Diario y semanal |
| 2026-05-17 | Transferencia única de cuenta completa | Diario (+16.785 pts) |

La ausencia de control es estructural: no se trata de un bypass circunstancial sino de una validación que nunca fue implementada.

---

## Recomendación técnica

Implementar validación server-side del acumulado diario de puntos transferidos antes de confirmar cada operación. La verificación debe ocurrir dentro de la misma transacción que escribe en `sml.CustomerPointsLog`, consultando el total ya enviado por el `CustomerId` emisor en el día calendario (UTC-3) en curso.

La validación en cliente (frontend / app mobile) no es suficiente como único control: debe existir un rechazo a nivel de servicio o base de datos que no pueda ser eludido.

---

## Archivos de evidencia

| Archivo | Contenido |
|---|---|
| `01_queries_investigacion.sql` | Queries Q1–Q6 ejecutadas durante la investigación |
| `02_transferencias_evento2.csv` | Detalle de participantes con roles, puntos y balance post-evento |
| `03_reporte_validacion_limite_it.md` | Este documento |
