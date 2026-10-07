# GITIN-2085 — [CLOUD] Discrepancia en Metrics de Insights

**Tags:** SmartCloud, Azure, Obserbavilidad, Performance, SRE, PROD

## Resumen

El 18-9 se reportó una discrepancia entre lo que mostraba Azure Monitor (una instancia de Sales-PRO al 100% de CPU) y App Insights Live Metrics (sin el mismo pico) para la ventana del 17-9 20:00-22:00 ART, con una alerta de escalamiento real (`Sales_CPU_Alert`) dependiendo de ese dato. La investigación confirmó que el pico de CPU es real y que la alerta funciona correctamente — el problema no es de notificación. Encontró dos mecanismos distintos, ninguno relacionado con la premisa original: (1) App Insights recibe cero telemetría de Sales-PRO actualmente, un gap ya conocido en otro servicio del mismo stack (Pos-PRO); y (2) la respuesta de capacidad (Autoscale) evalúa el promedio de CPU de todo el Plan (`DividePerInstance: false`), no por instancia — a diferencia de la alerta, que sí es por instancia — por lo que el promedio del Plan puede diluir una sola instancia saturada. Verificado contra la documentación oficial de Microsoft que `DividePerInstance: false` es el valor correcto/esperado para una métrica agregada por promedio (`CpuPercentage`/`Average`) — no es una falla de configuración a corregir. La causa raíz del pico de CPU original todavía no está confirmada.

## Tabla resumen

| Campo | Valor |
|---|---|
| Ticket Jira | [GITIN-2085](https://smartit-ar.atlassian.net/browse/GITIN-2085) |
| ID alerta | `Sales_CPU_Alert` / `Sales_Memory_Alert` (Azure Monitor Metric Alert) |
| Sistema | SmartFran Cloud — App Service Plan `SmartFran-Cloud-Sales-Plan-PRO` |
| Severidad | Baja — el alerting funciona correctamente; el mecanismo de Autoscale identificado es comportamiento esperado, no un defecto |
| Detectado | 2026-09-18 |
| Resuelto | Parcial — causa de la discrepancia original explicada (comportamiento esperado, no bug); causa raíz del pico de CPU en sí sigue sin confirmar |
| Responsable | Dante Paniagua |

## Causa raíz

Dos mecanismos distintos, ninguno relacionado con la premisa original ("la alerta no dispara"):

1. **App Insights recibe cero telemetría de Sales-PRO** (no solo CPU — `performanceCounters` y `requests` vacíos, histórico y en vivo). Por eso Live Metrics nunca mostró nada, independientemente de cualquier diferencia entre CPU de host vs. de proceso. Coincide con un gap ya confirmado y sin resolver en Pos-PRO (`cloud/events/20260913_pos-net-http-timeout/`), mismo stack de SmartFran Cloud.
2. **Autoscale evalúa el promedio de CPU de todo el Plan (`DividePerInstance: false`), no por instancia.** La alerta sí es por instancia y confirmado que dispara correctamente (~40 veces en 4 días, sin supresión). Con varias instancias activas, una sola saturada puede quedar diluida en el promedio, lo que explica la discrepancia percibida entre "Insights muestra 30-50%, en vivo muestra 100%". **Verificado contra documentación oficial de Microsoft** (`azure-monitor/autoscale/autoscale-understanding-settings`): `dividePerInstance` aplica a métricas agregadas por Sum/Count, no por Average — `false` es el valor correcto para `CpuPercentage`/`Average`. Este comportamiento es esperado, no una falla de configuración a corregir.

## Hallazgos

| # | Hallazgo | Riesgo |
|---|---|---|
| H1 | `Sales_CPU_Alert` está correctamente configurada (por instancia, umbral 80% sobre 5 min, grupo de acción `Correos-Cloud` válido y habilitado) | Informativo |
| H2 | Pico de CPU real confirmado el 17-9: instancia `wn0xsdwk00072R`, 94-98% promedio sostenido ~65 minutos, autoresuelto | Alto |
| H3 | App Insights sin telemetría de ningún tipo para Sales-PRO, histórico y en vivo — mismo patrón sin explicar ya visto en Pos-PRO | Alto |
| H4 | Recurrencia en vivo el 18-9: instancia `wn0sdwk000AXF` saturada ~98-99% por al menos 11 minutos | Alto |
| H5 | Hipótesis de retry storm de Service Bus/Cosmos **descartada** — dead-letter count plano durante el pico, y el throughput de mensajes bajó (no subió) durante la saturación | Bajo (descartado) |
| H6 | Hipótesis propuesta ("Cosmos caído encoló mensajes, el drenaje masivo causó el pico") **descartada** — el pico ocurrió 33 minutos antes de la ráfaga de errores 403 de Cosmos, no después | Bajo (descartado) |
| H7 | Sin Diagnostic Settings configurados en el App Service Plan — real, pero no es la causa de ninguna falla de disparo de alerta | Bajo |
| H8 | Resolución del pico del 18-9: confirmado por el usuario que fue un aumento manual del tamaño del plan (SKU) en respuesta a la alerta, no auto-heal ni resolución espontánea | Informativo |
| H9 | **Mecanismo real identificado**: Autoscale usa `DividePerInstance: false` (promedio de todo el Plan) mientras que la alerta evalúa por instancia — esto explica la discrepancia percibida entre "Insights muestra 30-50%, en vivo muestra 100%". Verificado contra documentación de Microsoft: es el valor correcto/esperado para una métrica `Average`, no un defecto a corregir | Informativo |
| H10 | Causa raíz del pico de CPU original (por qué se satura una instancia) sigue sin confirmar — no se pudieron capturar contadores de exception-rate/thread-pool durante el pico en vivo | Medio |

## Recursos afectados

| Recurso | Detalle |
|---|---|
| `SmartFran-Cloud-Sales-Plan-PRO` | App Service Plan afectado por los picos de CPU |
| `SmartFran-Cloud-Sales-PRO_new` | Componente de App Insights, sin telemetría |
| `SmartFran-Cloud-Sales-PRO` (regla de Autoscale) | `DividePerInstance: false` — comportamiento esperado y verificado contra documentación de Microsoft, no una falla de configuración |
| Destinatario del grupo de acción `Correos-Cloud` | Entrega no verificada |

## Comandos ejecutados

Sin `scripts.sh` consolidado para este ticket — cada resultado quedó persistido individualmente en `data/` a medida que se ejecutaba (definición de alerta, métricas de CPU por instancia, consultas de App Insights, historial de disparo de alertas, Activity Log, datos de throughput de Service Bus). Detalle completo en `investigation.md`.

## Acciones propuestas

1. **(SRE) Pendiente** — Traer el recurso completo `Microsoft.Insights/autoscalesettings` (no solo el snapshot embebido de un evento puntual) para confirmar todos los perfiles/reglas y si existe uno distinto para días de semana.
2. **(SRE) Pendiente** — Verificar la entrega real de los ~40 emails de alerta disparados al destinatario del grupo de acción `Correos-Cloud` (bandeja, spam, filtrado).
3. **(Dev/SRE) Pendiente** — Investigar el gap de telemetría cero en App Insights para Sales-PRO, en paralelo con el mismo gap ya confirmado en Pos-PRO — alcance cross-servicio, podría necesitar su propio ticket separado.
4. **(SRE) Pendiente** — Causa raíz del pico de CPU original sigue abierta. Si recurre, priorizar capturar contadores de exception-rate/thread-pool en vivo antes de que un recycle o escalado borre la evidencia otra vez.

## Hallazgos secundarios

Se investigó como hipótesis un cruce con `cloud/events/20260918_sales-cosmos-403-firewall/` (GITIN-2083) — descartado para este pico específico por el gap de 33 minutos entre ambos eventos, aunque el problema de firewall de Cosmos en sí sigue vigente y podría afectar estos mismos consumidores de forma intermitente.

Este hallazgo (Autoscale vs. alerta) redefine el alcance real de GITIN-2073 — ya reflejado en ese ticket y en el ticket de guardia [GITIN-2082](https://smartit-ar.atlassian.net/browse/GITIN-2082).

El acceso a Windows Event Log vía Kudu está bloqueado por el sandbox de App Service — vía cerrada para diagnosticar la causa raíz del pico por ese camino.
