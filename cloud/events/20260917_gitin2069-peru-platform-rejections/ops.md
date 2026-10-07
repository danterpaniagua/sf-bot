# GITIN-2069 — Guardia 17-9-2026: rechazos por plataforma en órdenes de Perú

**Tags:** `SmartPedidos`, `AWS`

**Nota de alcance:** este ticket se descubrió durante la verificación de GITIN-2068 (no relacionado en causa). La ubicación de este evento (`cloud/events/`) es provisoria — el mecanismo real (`PlatformRejectStrategy`, colección `news`) vive del lado de SmartPedidos; no se confirmó con el usuario si este ticket debería moverse a `smartpedidos/` o si "Guardia" implica un alcance más amplio que solo este hallazgo puntual.

## Resumen

Durante la verificación de la corrección de GITIN-2068 se observó un cluster de órdenes de la sucursal 5396 (Pueblo Libre I, Perú) llegando a estado "Recibida" con motivo "Orden rechazada por plataforma Grido". El usuario planteó la pregunta de si hay demasiadas ocurrencias de este motivo en Perú.

**Determinación del usuario, 2026-09-17:** evento aislado, probablemente derivado de GITIN-2068 (no una causa independiente). No se investigó el detalle de los 4 rechazos puntuales para confirmar el vínculo causal de forma independiente — se registra como la conclusión del usuario, no como algo verificado a partir del motivo/detalle real de cada rechazo.

## Tabla resumen

| Campo | Valor |
|---|---|
| Ticket Jira | [GITIN-2069](https://smartit-ar.atlassian.net/browse/GITIN-2069) ("Guardia 17-9-2026") |
| ID alerta | N/A — descubierto durante verificación de GITIN-2068 |
| Sistema | SmartPedidos (`platforms-service`, colección `news`) / reporte visible desde SmartCloud |
| Severidad | Baja-Media (sin confirmar aún) |
| Detectado | 2026-09-17 |
| Resuelto | 2026-09-17 — cerrado como evento aislado, probable derivado de GITIN-2068 (determinación del usuario, no verificada independientemente) |
| Responsable | Dante Paniagua (SRE) |

## Causa raíz

Según la determinación del usuario, este evento es aislado y probablemente derivado de GITIN-2068 — no una causa independiente. La sucursal 5396 fue una de las 12 órdenes bloqueadas históricas de ese ticket, lo que hace plausible una relación entre ambos hechos, aunque no se investigó el detalle/motivo real de los 4 rechazos puntuales para confirmarlo de forma independiente.

## Hallazgos

| # | Hallazgo | Riesgo |
|---|---|---|
| H1 | Tasa de rechazo por plataforma en Perú, últimos 7 días: 17 de 3071 órdenes (`news`) = **0.55%**, distribuido en 12 de las 35 sucursales, mayormente 1 caso cada una. No luce anómalo a nivel agregado. | Bajo |
| H2 | La sucursal 5396 (Pueblo Libre I) es una outlier clara: 4 rechazos / 87 órdenes = **4.60%** — 4 a 8 veces la tasa de cualquier otra sucursal de Perú (siguiente más alta: 1.18%). Es la misma sucursal que tuvo una de las 12 órdenes bloqueadas históricas de GITIN-2068 (`5507077`), sin que se haya establecido relación causal entre ambos hechos. | Medio |
| H3 | **Sin confirmar:** si 4.60% sobre n=87 es estadísticamente significativo o varianza plausible a ese volumen — no se comparó contra la propia línea base histórica de la sucursal 5396 (semanas previas), solo contra otras sucursales de Perú en el mismo período. | Medio |
| H4 | **Sin investigar:** el detalle/motivo específico de cada uno de los 4 rechazos de la sucursal 5396 — no se determinó si son del mismo tipo (ej. mismo producto sin stock) o de causas distintas. | Medio |

## Recursos afectados

| Recurso | Detalle |
|---|---|
| Sucursal 5396 — Pueblo Libre I (Perú) | Tasa de rechazo elevada, sin causa confirmada |
| `platforms-service` (`PlatformRejectStrategy`) | Mecanismo que registra el rechazo en `extraData.rejected` de la colección `news` |

## Comandos ejecutados

Ver `mongo_rejection_rate_check2.js` (corregido tras dos intentos fallidos — primero apuntaba a la colección equivocada, luego a un campo de fecha inexistente en `news`). Resultado persistido en `data/mongo_rejection_rate_check2.txt`.

## Acciones propuestas

1. ~~Investigar causa raíz~~ — **Cerrado.** El usuario determinó que se trata de un evento aislado, probable derivado de GITIN-2068. No se requieren más acciones sobre este ticket.
2. Si en el futuro se observa el mismo patrón (tasa de rechazo elevada en la sucursal 5396) sin relación con un incidente activo como GITIN-2068, reabrir la investigación desde el punto donde quedó (comparar contra línea base histórica de la sucursal, revisar detalle real de los rechazos).

## Hallazgos secundarios

Ninguno identificado todavía en esta investigación específica.
