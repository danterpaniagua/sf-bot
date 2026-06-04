# Email — Reporte de Hallazgo

**Para:** PMs — SmartLoyalty
**De:** Dante Paniagua, SRE
**Fecha:** 2026-05-17
**Asunto:** [PERF] WebServiceV2 — carga creciente sobre base de datos detectada hoy

---

Equipo,

Durante el monitoreo de hoy se identificó un incremento sostenido de carga sobre el servidor de base de datos de SmartLoyalty, originado en el servicio WebServiceV2 a partir de las 09:30 UTC-3.

---

## Qué se observó

El servicio WebServiceV2 realiza consultas para obtener el producto favorito y el promedio de consumo de cada cliente. A lo largo de la tarde, la cantidad de consultas simultáneas fue creciendo, generando presión acumulada sobre la base de datos.

| Franja horaria (UTC-3) | Consultas simultáneas |
|---|---|
| 10:00 – 11:00 | 1 – 3 |
| 11:00 – 12:00 | 3 – 7 |
| 12:00 – 13:30 | 5 – 8 |

No se registraron errores ni caídas de servicio. El impacto fue degradación de performance en el servidor de base de datos.

## Estado

El equipo IT tiene identificada la causa y está trabajando en la corrección. No se requiere acción de parte de PMs en este momento.

---

Dante Paniagua
SRE — SmartLoyalty
