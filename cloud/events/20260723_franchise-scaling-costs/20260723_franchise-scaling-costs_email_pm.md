Asunto: Costos de Graylog proyectados a 1.000 / 2.000 / 2.600 franquicias

Buen día,

Comparto la cotización de la infraestructura de Graylog escalada a 1.000, 2.000 y 2.600 franquicias, a partir del volumen real medido hoy con 170 franquicias.

**Importante antes de los números: estos costos reflejan el volumen de logs actual, sin optimizar.** Todavía no se coordinó con el equipo de desarrollo la reducción de verbosidad de `AppServiceConsoleLogs`, que hoy representa ~70% del volumen total de logs. Eso significa que las cifras de abajo son un techo, no un piso — si se reduce esa verbosidad antes de escalar (acción ya identificada, pendiente de coordinar con dev), el costo real en cada escenario sería menor a lo cotizado acá.

**Otra aclaración: el costo de Insights cotizado es solo por datos crudos, sin alertas, sin dashboards, sin análisis.** Hoy no hay reglas de alertas configuradas sobre Log Analytics (confirmado contra la facturación real — un solo meter, de ingesta). Si en el futuro se agregan alertas sobre Insights, eso suma un costo real aparte (~USD 0,10 a 3,00 por regla/mes según frecuencia, más notificaciones) que no está incluido en esta cotización. Los dashboards (Workbooks) no tienen costo propio en Azure, así que no cambian esta cuenta.

**Aclaración importante sobre el escenario "Solo Graylog": hoy Graylog solo tiene los logs de Business y Sales, 2 de los 8 App Services compartidos.** Pos, Admin, Platform, Person, Catalog y los 3 Function Apps no están en Graylog — solo en Log Analytics. Dar de baja Insights hoy dejaría sin ningún log a la mayoría de la flota, no es una migración 1 a 1. Antes de considerar ese escenario hace falta cotizar y ejecutar el onboarding del resto de los servicios a Graylog, con su propio costo de infraestructura y esfuerzo.

Aparte, verificamos que Orders sigue sin tener logging configurado en ningún lado (ni Insights ni Graylog) — la misma excepción que ya habíamos señalado en el email del 25/6, todavía sin resolver casi un mes después. Es un punto ciego de observabilidad independiente de esta cotización, que vale la pena resolver por separado.

**Sobre retención: Insights (Log Analytics) incluye 30 días sin costo extra; más allá de eso, retener datos cuesta USD 0,10/GB/mes aparte.** Graylog no tiene ese techo — la retención depende solo del disco que se le asigne. Si el requisito de negocio es guardar logs por más de 30 días, esa diferencia suma un costo adicional del lado de Insights que no está en la tabla de arriba.

**Estimación de impacto si se requiere guardar 1 año de datos (365 días) en Insights**, sobre el volumen real de ingesta medido hoy:

| Escenario | Costo extra de retención (mensual, en régimen) |
|---|---|
| 170 (base) | ~USD 251 |
| 1.000 | ~USD 1.479 |
| 2.000 | ~USD 2.958 |
| 2.600 | ~USD 3.846 |

Este costo no aparece de golpe: tarda ~11 meses en llegar a ese nivel, mientras se acumula el primer año de datos. Importante: no tenemos confirmado qué período de retención asume el dimensionamiento de disco ya cotizado para Graylog, así que todavía no podemos afirmar que Graylog sea más barato que Insights para un requisito de 1 año — falta verificar ese dato antes de usar esta comparación para decidir.

**Un punto de riesgo, no solo de costo: Graylog funciona como una "válvula de seguridad" de capacidad fija — Insights no — y es un trade-off, no una ventaja gratis de Graylog**. Del lado de disponibilidad: la VM de Graylog tiene disco y memoria fijos. Si la verbosidad de logs sube sin control (el mismo riesgo mencionado arriba) o se suman más apps sin agrandar la VM a tiempo, el disco se puede llenar o la memoria saturar — y ahí Graylog deja de recibir logs, justo en el momento en que más se necesitan (durante un incidente o un bug en producción). Insights no tiene ese techo: si sube el volumen, sube el costo, pero el servicio no se cae.

Del lado del costo es al revés: el de Insights sube en tiempo real y sin límite con el volumen — un error de verbosidad dispara la factura de inmediato — mientras que el de Graylog, al ser infraestructura ya paga (VM + disco), no sube con más volumen dentro de su capacidad. Pero esa "protección" de costo en Graylog se logra exactamente porque deja de poder recibir logs al tocar el límite — no es un freno controlado, es una falla de ingesta, y suele coincidir con el momento en que más logs hacen falta. Hoy no vimos ese límite alcanzado, pero la VM pilot ya está en un uso de memoria de 63-64% sirviendo solo 2 de los 8 servicios — el margen no es tan amplio como parece a simple vista. En resumen: ninguna de las dos opciones está libre de riesgo, cada una lo tiene de un lado distinto (costo vs. disponibilidad).

**Sobre reprocesar el JSON crudo para separarlo en pares clave:valor antes de usarlo en dashboards: sí tiene costo, si se hace en la ingesta.** Azure cobra USD 0,10/GB por ese procesamiento (`Logs Processed`), aparte del costo de ingesta ya cotizado. Sobre el volumen real medido hoy, eso suma:

| Escenario | Costo extra de procesamiento (mensual) |
|---|---|
| 170 (base) | ~USD 23 |
| 1.000 | ~USD 134 |
| 2.000 | ~USD 269 |
| 2.600 | ~USD 349 |

Esto solo aplica si el parseo se hace como paso de ingesta (antes de guardar el dato). Si en cambio se hace dentro de la consulta de cada dashboard (parseando el JSON al momento de mostrarlo), no tiene costo — es una consulta común, ya cubierta por lo que aclaramos arriba sobre consultas.

## Costos proyectados (mensual)

| Escenario | Base (170 franquicias) | 1.000 | 2.000 | 2.600 |
|---|---|---|---|---|
| Graylog + Insights en paralelo (estado actual) | $1.565 | $9.289 | $18.531 | $23.788 |
| Solo Graylog (dando de baja Insights) | $886 | $5.295 | $10.542 | $13.403 |
| Solo Insights (sin invertir en Graylog) | $679 | $3.994 | $7.988 | $10.385 |

Al armar esta cotización encontramos y corregimos dos cálculos desactualizados de la estimación anterior (uno de Event Hubs, otro de almacenamiento) — los números de arriba ya están corregidos y verificados contra los precios reales de Azure.

**Costos fantasma de Insights — no incluidos en la fila "Solo Insights" de arriba.** Si el requisito de negocio termina necesitando retención de 1 año y/o separar el JSON en clave:valor en la ingesta, hay que sumar estos dos costos aparte, ninguno visible en la cotización base:

| Escenario | Retención a 1 año | Split de JSON en ingesta | Total costo fantasma |
|---|---|---|---|
| 170 (base) | ~USD 251 | ~USD 23 | ~USD 274 |
| 1.000 | ~USD 1.479 | ~USD 134 | ~USD 1.613 |
| 2.000 | ~USD 2.958 | ~USD 269 | ~USD 3.227 |
| 2.600 | ~USD 3.846 | ~USD 349 | ~USD 4.195 |

Ninguno de los dos aplica automáticamente — depende de cómo se implemente cada cosa (retención por default es 30 días sin costo extra; el split de JSON no cuesta nada si se hace en la consulta del dashboard en vez de en la ingesta). Pero si ambos terminan siendo necesarios tal cual, el costo real de "Solo Insights" pasa a ser la fila de la tabla de arriba más esta tabla.

**Un componente todavía no está confirmado: el costo del servidor que corre Graylog (cómputo) a estas escalas.** El valor incluido en la tabla es un piso estimado, no una cifra final — antes de aprobar presupuesto en base a esto, hace falta completar un paso técnico de dimensionamiento que confirme el tamaño real de infraestructura necesario a 1.000+ franquicias.

**Nota sobre el email anterior de Graylog vs. Insights:** aquella conclusión de "ahorro modesto completando la migración" dependía específicamente de contratar la infraestructura de Graylog con una **reserva de infraestructura por 1 año** (un compromiso de compra, no relacionado con cuánto tiempo se guardan los logs — eso es un tema aparte, cubierto arriba) — el mismo email ya aclaraba que sin esa reserva, Graylog seguía siendo más caro que Insights. Todos los números de la tabla de arriba son de pago por uso (sin reserva, para poder comparar los tres escenarios de forma pareja), y bajo esa modalidad Graylog ya resulta más caro que mantener Insights incluso a 170 franquicias.

Revisamos qué pasaría con una reserva de 1 año, y el descuento real no es parejo entre componentes: el servidor (cómputo) sí tiene reserva y sale ~41% más barato, pero el disco solo tiene reserva a partir de un tamaño mayor al que realmente necesitamos, y Event Hubs (la parte que conecta todo) no tiene ninguna opción de reserva — ese costo no baja nunca, sin importar qué tan madura esté la implementación. Combinando los tres, el ahorro real de reservar por 1 año ronda el 34%, no el 20% que se venía asumiendo.

| Escenario | Insights | Graylog con reserva de 1 año | Diferencia |
|---|---|---|---|
| 170 (base) | $679 | ~$585 | Graylog ~$94 más barato |
| 1.000 | $3.994 | ~$3.495 | Graylog ~$499 más barato |
| 2.000 | $7.988 | ~$6.958 | Graylog ~$1.030 más barato |
| 2.600 | $10.385 | ~$8.846 | Graylog ~$1.539 más barato |

Con esa reserva, Graylog terminaría siendo más barato que Insights en los cuatro escenarios, no solo a 170 franquicias.

Importante: esto todavía no es una cifra para presupuestar. Se apila sobre tres cosas que seguimos sin confirmar — el tamaño real de servidor necesario a 1.000+ franquicias, el cambio de arquitectura que exige Event Hubs a esa escala, y el hecho de que hoy Graylog solo cubre 2 de los 8 servicios (el resto haría falta migrarlo primero). Antes de tomar una decisión de presupuesto con reserva de 1 año, hay que cerrar esos tres puntos.

**Vista combinada: uniendo los costos fantasma de Insights con Graylog pago por uso y reservado, en un solo cuadro:**

| Escenario | Insights (base) | Insights + costos fantasma | Graylog (pago por uso) | Graylog (reserva 1 año) |
|---|---|---|---|---|
| 170 (base) | $679 | ~$953 | $886 | ~$585 |
| 1.000 | $3.994 | ~$5.607 | $5.295 | ~$3.495 |
| 2.000 | $7.988 | ~$11.215 | $10.542 | ~$6.958 |
| 2.600 | $10.385 | ~$14.580 | $13.403 | ~$8.846 |

Algo que no habíamos remarcado: si retención a 1 año y split de JSON terminan siendo requisitos reales, Graylog **sin reserva** ya queda por debajo de Insights con esos costos fantasma, en los cuatro escenarios — no hace falta esperar a la reserva de 1 año para que la cuenta favorezca a Graylog en ese caso. Con reserva, la diferencia es todavía mayor. Dicho esto, sigue aplicando la misma advertencia: esto no cambia que la elección de "Solo Graylog" hoy deja sin logs a la mayoría de la flota (H9) y que el cómputo a escala no está confirmado (H5).

## Pros y contras desde una mirada de presupuesto

| | Graylog | Insights |
|---|---|---|
| **A favor** | Costo fijo (VM + disco ya pagos) — no sube con más volumen dentro de su capacidad. Sin costo de consulta, dashboards ni reglas de alerta (todo corre sobre el mismo cómputo). Sin cargo de retención — el disco ya está pago, se use o no. | Elástico, sin techo de capacidad — nunca deja de recibir logs por volumen, protege contra el peor escenario (quedarse sin logs durante un incidente). Sin costo de consulta hoy (confirmado, un solo meter). Ya cubre los 8 App Services + Function Apps, sin costo de onboarding pendiente. |
| **En contra** | Presupuesto fijo también significa que, al tocar el límite de disco/heap, el riesgo no es pagar más — es dejar de recibir logs. Cotización aún no incluye el onboarding de 6 de 8 apps que faltan ni un capacity planning real a escala — hay costos "escalón" todavía no presupuestados. Event Hubs Standard tiene techo duro de 20 TU/namespace entre 1.000 y 2.000 franquicias — fuerza un cambio de arquitectura, no solo más gasto. | El costo escala en tiempo real y sin techo con el volumen — un error de verbosidad se traduce directo en una factura más alta, sin ningún freno. Retener más de 30 días cuesta aparte y crece con la escala (hasta ~USD 3.846/mes extra a 2.600 franquicias solo por retención a 1 año). |

En síntesis: Graylog da presupuesto predecible pero con riesgo de disponibilidad si se descontrola el volumen; Insights da disponibilidad garantizada pero con riesgo de presupuesto si se descontrola el volumen. Ninguna opción es gratis de riesgo — la pregunta de fondo es cuál de los dos riesgos es más aceptable para el negocio.

## Próximos pasos

- Coordinar con desarrollo la reducción de verbosidad de `AppServiceConsoleLogs` antes de escalar — reduce el costo en los tres escenarios, a cualquier franquicia.
- Definir arquitectura para 2.000 y 2.600 franquicias (el volumen a esa escala requiere un cambio de configuración en Event Hubs, no solo más presupuesto).
- Confirmar el costo de cómputo real antes de tomar cualquier decisión de presupuesto sobre estos escenarios.

Quedo disponible ante cualquier consulta.

Saludos,
Dante Paniagua
SRE — Operations Team
