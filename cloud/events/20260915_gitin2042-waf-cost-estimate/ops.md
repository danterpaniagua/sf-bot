# GITIN-2042 — Estimación de costo WAF (Opción B, GITIN-1938)

**Tags:** `SmartCloud`, `Azure`, `CloudPOS`, `SRE`

## Resumen

GITIN-1938 dejó identificada la Opción B (WAF sin APIM, extendido a retail) como una de las alternativas de diseño para dar a SmartFran Cloud protección WAF que hoy no existe, pero sin estimar su costo. Esta ticket cierra ese punto: estima el costo mensual de la Opción B para Azure Front Door Premium y Application Gateway WAF_v2, en base a volumen de tráfico real medido (no solo estimado por lectura de código), cubriendo PROD y no-prod, y proyectado a tres escenarios de crecimiento de franquicias (1.500, 2.000, 2.600) sobre la base actual (200).

## Tabla resumen

| Campo | Valor |
|---|---|
| Ticket Jira | GITIN-2042 |
| Ticket relacionado | GITIN-1938 |
| Sistema | SmartFran Cloud — Azure Front Door Premium / Application Gateway WAF_v2 |
| Severidad | N/A — estimación de costos, no incidente |
| Detectado | N/A |
| Convergida | 2026-09-15 |
| Responsable | Dante Paniagua, SRE |

## Causa raíz

No aplica en el sentido de incidente — esta ticket es una estimación proactiva, no una respuesta a una falla. La base técnica del costo es el volumen de requests HTTP que un WAF consolidado tendría que procesar: 8 App Services de producción más 4 Function Apps, medido en una ventana real de 91,67 horas y proyectado linealmente por franquicia. Los dos productos evaluados tienen modelos de costo estructuralmente distintos — Front Door cobra por request y GB, totalmente calculable a partir del volumen medido; Application Gateway cobra por Capacity Unit, un modelo que Microsoft no expone como fórmula cerrada y que recomienda medir empíricamente sobre un gateway en funcionamiento, no calcular por adelantado.

## Hallazgos

| # | Hallazgo | Riesgo |
|---|---|---|
| H1 | El heartbeat de SmartPedidos (`Orders/Queue/Heartbeat`) representa el 29,7% de todo el tráfico medido (8 App Services + 4 Function Apps) — más que el endpoint set completo de Sales. Es tráfico de keepalive sin valor de negocio por request, presente incluso con el POS abierto e inactivo. | Alto |
| H2 | El costo variable de Application Gateway WAF_v2 (Capacity Units) no es calculable con precisión a partir de conteo de requests — depende de negociación TLS y overhead de reglas WAF, ambos no expuestos por Microsoft como fórmula. No existe un gateway real para medir el consumo empíricamente. | Medio |
| H3 | La consulta de favoritos aparece en los datos reales con un ratio de 0,02 respecto a las ventas, bastante menor a lo que sugiere el código fuente (3 veces por venta) según el análisis del dev de cloud responsable. Hipótesis más probable (no confirmada): un `FavoritesRankingTimerTrigger` programado precalcula el ranking y el POS solo lo lee, sin las 3 llamadas de red que el código sugiere. | Medio |
| H4 | `WsFePe/GeneratePending` y `WsFePe/GetMaxAmountCustomerRequired` corren al 31-35% del volumen de `Sale/Create`, alto para un endpoint cuyo nombre sugiere facturación electrónica específica de Perú, dado que el tráfico medido es mayormente de tenants argentinos (94,8% Grido + 2,7% Weiss). No confirmado si el nombre es engañoso o hay otra explicación. | Bajo |
| H5 | `cloud/docs/infrastructure.md` documentaba 3 Function Apps bajo una convención de nombres completamente distinta y desactualizada, sin fuente ni fecha conocida. Corregido a las 4 reales (`SFC-CodeGenerator-PRO`, `SFC-PosWasmRelay-PRO`, `SFC-ScheduledJobs-PRO`, `SFC-TicketProcess-PRO`). | Bajo |
| H6 | `SFC-ScheduledJobs-PRO` combina un endpoint HTTP real orientado a POS (`RegisterBusinessLog`) con 4 jobs internos por timer que nunca atraviesan un WAF. La métrica de plataforma disponible (`FunctionExecutionCount`) no permite separar ambos. Re-intentado el 2026-09-15 vía el nuevo campo `FunctionName` de Graylog (GITIN-2050) — sin éxito para esta ventana específica: la promoción de campos se desplegó ese mismo día, después de que corriera casi toda la ventana de medición de esta ticket, y no es retroactiva (confirmado: 600.837 mensajes reales en la ventana, 0 con `FunctionName` poblado). El volumen de esta Function App se sigue tratando como cota superior, no como cifra confirmada, en la estimación final. | Bajo |

## Recursos afectados

| Recurso | Detalle |
|---|---|
| App Services PROD (8) | `SmartFran-Cloud-{Admin,Business,Catalog,Orders,Person,Platform,Pos,Sales}-PRO`, RG `SmartFran.Cloud.PRO` |
| Function Apps PROD (4) | `SFC-CodeGenerator-PRO`, `SFC-PosWasmRelay-PRO`, `SFC-ScheduledJobs-PRO`, `SFC-TicketProcess-PRO` — mismo App Service Plan (`P0v3`, 1 instancia) |
| No-prod | Suscripción separada (Smart IT - Grido) — DEV/DEV2/STG/TEST/POC, mismos 8 dominios; no incluido en el volumen medido, sí en el costo fijo proyectado (×2 ambientes) |
| Host externo Loyalty | Fuera del alcance de esta medición — no hay stream/métrica disponible para su volumen |
| WAF / Front Door / Application Gateway | Ninguno existe hoy — confirmado en GITIN-1938 |

## Comandos ejecutados

| # | Comando / Script | Propósito |
|---|---|---|
| C1 | Pricing Front Door | Precio real Azure Front Door Premium (Base Fee, Requests, Data Transfer In/Out) vía Azure Retail Prices API |
| C2 | Pricing App Gateway | Precio real Application Gateway WAF_v2 (Fixed Cost, Capacity Units), región `eastus2` |
| C3-C9 | Tráfico real — 7 App Services | Export Graylog (`PROD-{App}-AppServiceHTTPLogs`) + agregación local por endpoint, Admin/Business/Catalog/Orders/Person/Platform/Pos, misma ventana |
| C10 | Discovery Function Apps | Componentes App Insights en el RG + métricas de plataforma disponibles para un Function App |
| C11 | FunctionExecutionCount | Volumen real de ejecución de las 4 Function Apps vía Azure Monitor, misma ventana |

Ver `scripts.sh` para el detalle completo de cada comando; salida real de cada uno en `data/`.

## Acciones propuestas

1. Resolver el heartbeat de SmartPedidos antes de avanzar con la adopción del WAF (H1) — reducir frecuencia, agrupar, o reutilizar la conexión WebSocket de SignalR ya abierta por POS en lugar de un request HTTP independiente cada 50 segundos. Reduce directamente el costo de cualquiera de los dos productos evaluados, en la misma proporción que el crecimiento de franquicias.
2. Elegir producto WAF con el trade-off completo a la vista, no solo el costo — Front Door es más caro en los 4 escenarios evaluados pero tiene soporte nativo de múltiples orígenes (coincide con el diseño de "front door único" que propuso el dev de cloud) y WAF incluido sin cargo adicional; Application Gateway es más barato, su costo variable no es calculable de antemano (H2), y a favor tiene ser tecnología conocida en la organización, ya en producción para SmartLoyalty (`WAF_APPs`) — no un producto nuevo a aprender desde cero. El patrón de múltiples orígenes en una instancia también está probado ahí (listeners multi-sitio, 3 backend pools), pero a una escala bastante menor (3 listeners/2 servicios) que los 8 App Services + Functions que necesitaría esta ticket.
3. Si se opta por Application Gateway, sacar las métricas reales de Capacity Units de `WAF_APPs` (gateway real, mismo tenant, ya corriendo en producción) para reemplazar el rango no oficial de H2 con un número empírico — más rápido y más barato que levantar un piloto nuevo, aunque no sea la misma carga de tráfico.
4. Compartir con el dev de cloud responsable los dos puntos donde los datos reales suman detalle sobre su estimación por lectura de código (H3, H4), para que los confirme o los explique.
5. Si se necesita una cifra más precisa antes de aprobar presupuesto, cerrar las brechas de datos que quedan fuera de esta estimación: descarga de assets estáticos del cliente (bundle WASM), host externo de Loyalty, y la porción HTTP real de `SFC-ScheduledJobs-PRO` (H6).

## Hallazgos secundarios

- Las métricas de plataforma de las Function Apps incluyen `BytesReceived`/`BytesSent` (confirmado en la discovery, C10) — no usadas en esta estimación, pero cerrarían la brecha de tamaño de payload necesaria para calcular Throughput Units de Application Gateway con precisión, si se retoma esta estimación más adelante.
- El onboarding de las 4 Function Apps a Graylog (GITIN-2050, 2026-09-15) agregó el campo `FunctionName`, que sí permite separar el tráfico HTTP real de `RegisterBusinessLog` de los 4 jobs por timer en `ScheduledJobs` — pero solo hacia adelante desde esa fecha, no retroactivo (ver H6). Si esta estimación se retoma más adelante con una ventana de medición posterior a 2026-09-15, H6 se puede cerrar con una cifra confirmada en lugar de una cota superior.
