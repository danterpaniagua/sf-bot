# Eventos — 20260728_nuevo-analisis-costos

## 2026-07-28 — Apertura: ticket separado del análisis de costos (ex ARQ-010)

**Autor:** Dante Paniagua

Se movió a este ticket propio el análisis de costos que había sido registrado como ARQ-010 en [20260720_ocultar-account-id-sqs-urls](../20260720_ocultar-account-id-sqs-urls/20260720_ocultar-account-id-sqs-urls.md), para no mezclar el seguimiento de costos con el ticket de diseño/PoC. Mismo alcance: extender ARQ-007 (que sólo cubría API Gateway + SQS) con Lambda authorizer, Secrets Manager y CloudWatch Logs, y recalcular contra `us-east-1` (región de producción real) en vez de `us-east-2`.

**Pendiente, solicitado al usuario antes del split:** conteo real de sucursales/agentes (`db.branches.countDocuments`) y 6 consultas de `aws pricing get-products`. Ninguno de los dos fue respondido todavía — este ticket queda a la espera.

**Archivo principal:** `20260728_nuevo-analisis-costos.md`

---

## 2026-07-28 — Conteo de agentes y pricing recibidos, análisis completado

**Autor:** Dante Paniagua

Se recibieron ambos datos pendientes: 2.162 sucursales con agente instalado (de 2.344 documentos totales en `branches`), y las 6 respuestas de `aws pricing get-products` en `us-east-1`.

**Hallazgo clave:** la corrección de región no cambia el costo base de ARQ-007 — la tarifa de API Gateway REST es idéntica en `us-east-1` y `us-east-2` ($3,50/millón). El componente nuevo dominante no es el Lambda authorizer (piso $5,69/mes, techo $44,94/mes) sino **CloudWatch Logs** — y ahí la elección de modo de logging importa: *execution logging* completo (como quedó configurado el PoC, para debug) cuesta ~$73-92/mes, mientras que *access logging* (recomendado para producción, una línea estructurada por request en vez de la traza completa) cuesta ~$28/mes.

**Resultado combinado, Opción A:** entre ~$551/mes (escenario recomendado: access logging + piso de invocaciones del authorizer) y ~$658/mes (logging completo + techo) — un incremento de +$34 a +$140/mes sobre la estimación original de ARQ-007 ($517,16/mes, que sólo cubría SQS+API Gateway).

Se marcaron COST-001 a COST-004 como resueltos. COST-005 (refinar duración/cold-starts del authorizer contra datos reales) queda abierto como refinamiento opcional, no bloqueante.

---

## 2026-07-28 — Corrección: CloudWatch Logs fuera de alcance, logging va por Event Hub → Graylog

**Autor:** Dante Paniagua

Se corrigió el análisis: el logging de esta implementación no va a correr por CloudWatch Logs — se enviará por el Event Hub existente hacia Graylog, mismo patrón ya usado en `develop`. Se eliminó por completo la línea de costo de CloudWatch Logs (antes ~$28-92/mes según modo de logging).

**Resultado actualizado:** el total combinado baja de ~$551-658/mes a **~$523-563/mes**. El delta sobre la estimación original de ARQ-007 ($517,16/mes, sólo SQS+API Gateway) se reduce de +6,6%/+27% a **+1,2%/+8,8%** — el Lambda authorizer y Secrets Manager, sin CloudWatch Logs de por medio, agregan muy poco al costo base.

---

## 2026-07-28 — Costo actual de producción re-confirmado, histórico 14 meses, aumento reportado

**Autor:** Dante Paniagua

Se re-confirmó el costo real actual vía Cost Explorer (histórico de 14 meses, límite de la cuenta — no se pudo consultar febrero 2025 sin habilitar historial extendido en Billing, fuera de alcance). Junio 2026 se revisó levemente al alza respecto a la consulta original de ARQ-007 ($75,00/151,21M vs. $73,49/147,76M) — normal, los datos de Cost Explorer se refinan después de la consulta inicial.

**Corrección a la premisa del usuario:** diciembre 2025 y febrero (2025/2026) no fueron los meses de mayor uso — **marzo de 2026 lo fue** ($81,04, 163,3M requests), con margen sobre el segundo lugar (enero 2026, $78,76).

**Aumento reportado:** recalculando la nueva implementación a volúmenes reales (junio 2026 típico y marzo 2026 pico, no el volumen desactualizado de ARQ-007), el aumento sobre el costo actual de producción es de **+613% a +667%**, estable sin importar qué mes se use de baseline (tanto el costo actual como el nuevo escalan casi linealmente con el volumen de requests). Cifra resumen: el proxy completo cuesta entre ~6,1x y ~6,7x el acceso directo a SQS actual.

---

## 2026-07-28 — Costo en contexto de toda la infraestructura AWS de la cuenta

**Autor:** Dante Paniagua

Se relevó el gasto total de la cuenta `382381053403` (todos los servicios, mismo rango de 14 meses) para poner el +613%/+667% en contexto — esa cifra comparaba sólo contra SQS aislado, que es apenas ~5% del gasto total de la cuenta (junio 2026: $1.418,29 total, $75,00 SQS). El costo dominante de la cuenta es cómputo (EC2+ECS+ELB ≈ $748/mes).

**Resultado recalculado:** reemplazando el costo de SQS actual por el de la nueva implementación en el total de cuenta, mes a mes, el aumento real al gasto total de AWS es de **~26% a 38%, típicamente ~30-35%** — no +613%/+667%. Cifra para reportar: el proxy pasaría a representar ~28-30% del gasto total de la cuenta, vs. el ~5% que SQS representa hoy.

Salvedad agregada: no se verificó si todos los servicios del desglose (Directory Service, WAF, Kinesis, etc.) pertenecen exclusivamente a SmartPedidos — se tomó el total de cuenta tal cual lo reporta Cost Explorer.

---

## 2026-07-28 — Gran total del período y corrección de una tabla previa

**Autor:** Dante Paniagua

Se entregó una tabla intermedia en el chat (no escrita al ticket) que reusaba por error los montos de costo *sólo del proxy* (~$480-580/mes) bajo la etiqueta "Nuevo total", en vez de los montos de *bill completo de cuenta* (~$1.500-2.200/mes) de la sección anterior. Se corrigió al pedir el usuario un gran total y notar que cada bill ronda ~$1.500 — confirmando que la referencia correcta era el bill completo, no el costo aislado del proxy.

**Gran total, 14 meses:** bill actual acumulado $18.837,81 → nuevo bill acumulado $24.652,87 (piso) a $25.153,43 (techo). Aumento total del período: +$5.815,06 (+30,9%) a +$6.315,62 (+33,5%) — consistente con el rango mensual ya reportado (~26-38%).

---

## 2026-07-29 — Opción más barata identificada: Opción A' con Lambda combinado (auth + relay)

**Autor:** Dante Paniagua

Se agregó al ticket una opción más barata que Opción A (la construida), derivada de ARQ-008 (ticket de origen, nunca resuelto entre Opción A y A'). Refinamiento nuevo: en vez de un authorizer TOKEN de REST API separado, meter la verificación JWT + binding de `branchId` dentro del mismo Lambda que ya haría falta para el relay a SQS en Opción A' (HTTP API no tiene integración nativa a SQS) — evita pagar una segunda dimensión de Lambda.

**Estimación a volumen real de junio 2026:** ~$213/mes, vs. ~$535/mes de Opción A real — ~$320/mes más barato (~60% de reducción). **No construida ni probada end-to-end**, a diferencia de Opción A.

Se documentaron los trade-offs reales de invocar Lambda en cada request (cold starts, límites de concurrencia, más superficie operativa — con referencia a los dos bugs de Lambda/IAM encontrados en esta misma sesión) — no es una mejora estrictamente superior a Opción A, es latencia/confiabilidad vs. costo. Se agregó COST-006 (PoC acotado midiendo latencia p50/p99 real) como siguiente paso no bloqueante antes de decidir ARQ-008.

---

## 2026-07-29 — Opción A' aplicada a los 14 meses reales, y presentación breve publicada

**Autor:** Dante Paniagua

Se extendió el análisis de Opción A' (combinado auth+relay) a los 14 meses de datos reales de Cost Explorer, misma metodología usada para Opción A. Resultado: Opción A' aumenta el bill total de la cuenta en **~9-12%** de forma consistente en los 14 meses, contra **~26-42%** de Opción A — más de 3x menos impacto, sin excepción mes a mes. Gran total del período: $18.837,81 (actual) → $20.583,45 (Opción A', +9,3%) vs. $24.652,87 (Opción A piso, +30,9%).

Se publicó además una presentación breve (Artifact) con el resumen ejecutivo: tiles de resumen, gráfico de tendencia de 14 meses con las tres series (Actual / Opción A / Opción A', paleta validada con `validate_palette.js`), tarjetas de comparación, un banner de recomendación fuerte sobre migrar el secreto de firma JWT a Secrets Manager (no opcional, dado el hallazgo de secreto compartido hardcodeado), y comandos curl de prueba para cada caso de respuesta (200/401/403) con tokens reemplazados por placeholders — los reales están firmados con el secreto real de producción, no se distribuyen fuera de Secrets Manager.

---

## 2026-07-29 — Opción A' construida y probada (ya no sólo diseño)

**Autor:** Dante Paniagua

Se construyó el PoC de Opción A' completo, no sólo la estimación: Lambda combinado (`smartpedidos/repos/ocultar-accountid-optB/index.js`, JWT+branchId + relay a SQS en la misma invocación, reutilizando las colas y el secreto de Opción A), rol IAM `poc-arq009-optb-combined-role` (permisos fusionados de Secrets Manager + SQS), HTTP API `1pslobqodi` con integración AWS_PROXY, rutas `POST`/`GET /{branchId}`, stage `optb` (separado del stage `poc` del REST API de Opción A, por pedido explícito del usuario — son recursos de API Gateway distintos, HTTP API vs REST API).

**Los 7 escenarios de prueba dieron el resultado correcto** (200/200/200/403/401/401/200), mismo comportamiento de autorización que Opción A. Se midió latencia real desde los logs del propio Lambda (`REPORT` lines, no el tiempo de curl): warm 40-60ms para el camino completo, 1,7-17,5ms para rechazos sólo-auth, cold start ~1,49s (367ms Init + 1.127ms Duration en la primera invocación). Confirma que el supuesto de 100ms del modelo de costo era conservador (costo real algo menor al estimado) y que el riesgo de cold-start es real y de ese orden de magnitud, no sólo hipotético.

Se marcó COST-006 como resuelto y se agregó COST-007 (muestra más grande, p50/p99 bajo concurrencia real) como refinamiento no bloqueante.

---

## 2026-07-29 — Mapas de transición: as-is, Opción A, Opción A'

**Autor:** Dante Paniagua

Se agregaron tres diagramas de secuencia al ticket: cómo es hoy (as-is), Opción A (REST — authorizer separado del llamado a SQS, con caché de decisión de 300s) y Opción A' (HTTP — auth y relay en el mismo Lambda, sin ese caché, cada request re-corre la verificación completa). Se agregaron como diagramas separados porque son estructuralmente distintos, no la misma secuencia con otro nombre — confirmado antes de agregarlos, no asumido.
