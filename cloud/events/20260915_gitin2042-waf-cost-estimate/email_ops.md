Asunto: GITIN-2042 — Estimación de costo WAF (Opción B) y hallazgos sobre el tráfico real

Hola Javier, ¿cómo estás?

Con los números de tráfico que pasó Gastón armé la estimación de costo del WAF para la Opción B de GITIN-1938. Te dejo el resumen y dos cosas que me gustaría que confirmen del lado del equipo de dev.

Sumé al análisis de Gastón (por lectura de código) tráfico real medido en Graylog y Azure Monitor (los 8 App Services PROD más las 4 Function Apps, misma ventana de ~92 horas) — se complementan bien: el heartbeat mide 68 req/franquicia/hora, cerca de su estimación de 72/h por POS, y la relación Create/Close de Sale es prácticamente 1:1 como esperaba. Los datos reales suman dos cosas más para mirar juntos:

La consulta de favoritos aparece en los datos reales con una frecuencia bastante menor a la que se ve en el código (ratio de apenas 0,02 respecto a las ventas). Encontré un `FavoritesRankingTimerTrigger` programado en ScheduledJobs que podría explicar la diferencia — el ranking se precalcularía y el POS solo lo leería, sin las 3 llamadas de red que sugiere el código — pero no lo tengo confirmado. ¿Le suena esa hipótesis a alguien del equipo?

Por otro lado, `WsFePe/GeneratePending` y `WsFePe/GetMaxAmountCustomerRequired` corren al 31-35% del volumen de `Sale/Create` — alto para un endpoint que por nombre sería específico de Perú, con el tráfico medido siendo casi todo de tenants argentinos. ¿El nombre no refleja lo que hace realmente, o hay algo más ahí?

Sobre el costo, un punto importante antes de la tabla: el diseño necesita **2 WAFs, no 1** — uno para PROD y otro para DEV/STG/TEST (están en subscripciones distintas). Eso se refleja así en los números de abajo:

- Costo fijo (el fee base mensual que cobra cada producto, tengas tráfico o no) — se paga por gateway, así que son 2 facturas reales, una por PROD y otra por no-prod:
  - Front Door: $330/mes por gateway → $330 (PROD) + $330 (no-prod) = **$660/mes**
  - Application Gateway: $262,80/mes por gateway → $262,80 (PROD) + $262,80 (no-prod) = **$525,60/mes**
- Costo variable (requests / Capacity Units) — **no** lo dupliqué: lo calculé solo con el tráfico real de PROD, porque no-prod no tiene volumen de franquicias real que justifique sumarle el mismo tráfico de nuevo.

Las tablas de costo más abajo ya muestran el **total** (fijo + variable sumados) para cada producto en cada escenario — no hay que sumarle nada aparte. Lo único que cambia entre filas es el costo variable, porque el fijo (los $660 o $525,60 de arriba) es el mismo siempre haya 200 o 2.600 franquicias.

Para presupuesto, el variable es la parte que importa mirar con cuidado — es lo que crece con la red de franquicias, no el fijo:

- **Front Door**: el variable es 100% calculable — a más franquicias, más requests, más costo, sin margen de error. Solo en PROD, a 2.600 franquicias el variable ($630) ya casi duplica el fijo de PROD ($330).
- **Application Gateway**: acá el variable **no es una cifra confirmada** — no hay fórmula pública de Microsoft que lo calcule por adelantado (depende de negociación TLS y overhead de reglas WAF), así que el rango sale de una heurística no oficial, no de un cálculo cerrado como el de Front Door. Pero el impacto en el bolsillo es chico: a 1.500 franquicias el variable va de $18 a $54 — contra un fijo de $525,60 que domina el total de cualquier forma. La incertidumbre es real en el método, no en el presupuesto.

Con la tasa medida (221 req/franquicia/hora, PROD) armé la proyección para el volumen actual y para 1.500, 2.000 y 2.600 franquicias:

| Franquicias | Requests/hora (promedio) | Requests/día | Requests/mes |
|---|---|---|---|
| 200 (actual) | 44.250 | 1.062.000 | 32.302.500 |
| 1.500 | 331.875 | 7.965.000 | 242.268.750 |
| 2.000 | 442.500 | 10.620.000 | 323.025.000 |
| 2.600 | 575.250 | 13.806.000 | 419.932.500 |

El promedio esconde la hora pico, que es la que realmente importa para dimensionar el WAF. Con 200 franquicias medí un pico real de 130.000 req/hora (13/09 19:20 UTC, ~2,9x el promedio) — para 1.500/2.000/2.600 proyecté ese mismo factor, no es una medición real a esa escala:

| Franquicias | Pico (req/hora) |
|---|---|
| 200 (medido) | 130.000 |
| 1.500 (proyectado) | 975.000 |
| 2.000 (proyectado) | 1.300.000 |
| 2.600 (proyectado) | 1.690.000 |

El costo de abajo lo calculé sobre el promedio, no sobre el pico — para Front Door no cambia nada (cobra por request real, sea pico o valle). Para Application Gateway sí importa: las Capacity Units se dimensionan para soportar el pico, no el promedio, así que el rango de CU de más abajo probablemente queda corto en la hora más cargada.

Y el costo que sale de ese volumen (sobre el promedio) — separado por ambiente, porque son 2 WAFs con perfiles de costo distintos:

**PROD** (fijo + variable, este último crece con las franquicias)

| Franquicias | Front Door Premium/mes | Application Gateway WAF_v2/mes |
|---|---|---|
| 200 (actual) | $378 | $265-$270 |
| 1.500 | $693 | $281-$317 |
| 2.000 | $815 | $287-$335 |
| 2.600 | $960 | $294-$356 |

**No-prod** (solo fijo — no tiene volumen real de franquicias que justifique un variable, así que no cambia entre escenarios)

| | Front Door Premium/mes | Application Gateway WAF_v2/mes |
|---|---|---|
| DEV/STG/TEST | $330 | $262,80 |

**Total (PROD + no-prod)** — la suma de las dos tablas de arriba:

| Franquicias | Front Door Premium/mes | Application Gateway WAF_v2/mes |
|---|---|---|
| 200 (actual) | $708 | $528-$533 |
| 1.500 | $1.023 | $544-$579 |
| 2.000 | $1.145 | $550-$597 |
| 2.600 | $1.290 | $557-$619 |

Es un trade-off real, no una decisión obvia. Te dejo pros y contras de cada uno:

Azure Front Door Premium
- A favor: soporte nativo para consolidar los orígenes separados por servicio que señaló Gastón (Sales/Business/Catalog/Person + Functions + Loyalty) detrás de un único front door, sin configuración extra. WAF incluido sin cargo adicional. Beneficio de cache en el edge para la descarga de assets estáticos (bundle WASM), algo que Application Gateway no hace. Costo totalmente calculable de antemano, sin incertidumbre.
- En contra: más caro en los cuatro escenarios evaluados, principalmente por el fee base fijo. Modelo de ruteo global/DNS, menos integrado con la red virtual que ya usamos.

Application Gateway WAF_v2
- A favor: más barato en los cuatro escenarios evaluados. Integración nativa con la VNet existente, sin una capa global separada que razonar. Tecnología conocida en la organización, ya en producción en Loyalty (`WAF_APPs`) — no es un producto nuevo a aprender desde cero.
- En contra: el patrón ya funciona en Loyalty (`WAF_APPs`, Application Gateway WAF_v2 en producción con listeners multi-sitio para varios backend pools: ClubSite AR, ClubSite PY y WebSite), pero a 3 listeners/2 servicios — 8 App Services + Functions sería ~4x ese tamaño en una sola instancia, sin precedente interno a esa escala. Sin cache/CDN para assets estáticos. El costo variable (Capacity Units) no lo puedo calcular con precisión de antemano — depende de negociación TLS y overhead de reglas WAF que Microsoft no expone como fórmula. Ahí el `WAF_APPs` de Loyalty sí ayuda: es un gateway real corriendo hoy, y puedo sacarle las métricas reales de Capacity Units para tener un número empírico en vez de la estimación no oficial que uso ahora — lo hago si les sirve. Solo regional, sin puntos de presencia globales.

Lo dejo planteado así en la ticket, con el detalle completo.

Una alerta aparte: el heartbeat solo (`Orders/Queue/Heartbeat`) es el 29,7% de todo el tráfico medido — más que Sales completo. No tiene valor de negocio por request, es puro keepalive de POS abierto e inactivo, y pega directo en el costo de cualquiera de los dos productos en la misma proporción que crezca la red de franquicias. Vale la pena resolverlo antes de que el WAF esté en producción, no después — coincide con lo que ya había marcado Gastón en su mail.

Cualquier cosa que quieras profundizar, la ticket tiene el desglose completo, incluyendo el gráfico de consumo por servicio/función: https://smartit-ar.atlassian.net/browse/GITIN-2042

Saludos
Dante
