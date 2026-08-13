# Eventos — 20260722_puntos_duplicados_masivos_waf504

## 2026-07-22 — Apertura de investigación

He recibido el reporte de que Grido intentó aplicar una asignación masiva de puntos hoy, el WAF devolvió 504, y el operador reintentó varias veces, dejando clientes con puntos duplicados.

## 2026-07-22 — Identificación de causa raíz

He confirmado, revisando el código fuente de `MassivePointsAssignment`/`AssignmentPointsCatalog`, que un timeout de WAF hacia el cliente no cancela la ejecución del lado del servidor — el proceso sigue corriendo (entre 11 minutos y 1.5 horas por corrida). He confirmado también que el proceso no tiene control de idempotencia, por lo que cada reintento del operador ejecutó una asignación de puntos independiente sobre el mismo listado.

## 2026-07-22 — Ajuste de queries por permisos

Al ejecutar la primera query de descubrimiento recibí `Msg 229` (permiso `SELECT` denegado sobre `Sml.ManualAssignPoints`). He confirmado con `fn_my_permissions` que el login sólo tiene `VIEW DEFINITION` sobre esa tabla, no `SELECT`. Rediseñé todas las queries para trabajar exclusivamente desde `Sml.CustomerPointsLog` (con `SELECT` concedido), usando sus propias columnas `ManualAssignPointsId`, `Points`, `LogDate`, `EventTypeCode` y `Note`.

## 2026-07-22 — Descubrimiento de lotes por Note

He agrupado los lotes (`ManualAssignPointsId`) de hoy por `Note` (Query 2). Identifiqué cuatro listados distintos: "Lista socios ganadores" (enviado 3 veces), "Lista 1" y "Lista 2" (1-2 veces cada uno), y "Campaña recupero" (1 vez).

## 2026-07-22 — Confirmación de solapamiento cruzado entre listados

Inicialmente asumí que "Lista socios ganadores" era una fusión de "Lista 1" + "Lista 2" bajo otro nombre. Detecté que esa hipótesis era incompleta al confirmar que "Lista 1" también estaba duplicada, y corrí la Query 4 (solapamiento cruzado por `CustomerId`) para revisarlo. Confirmé que los cuatro listados apuntan, en la práctica, a la misma población objetivo: 1.987 clientes fueron impactados por 3 Notes distintos, 5.933 por 2 Notes distintos, y 20 por 1 solo Note con total no múltiplo limpio de 10.000 (caso límite).

## 2026-07-22 — Cálculo del exceso agregado

A partir de la Query 4 (`DistinctNotesHit`, `CustomerCount`, `SumPoints`), calculé el exceso total: 376.450.000 pts otorgados contra 79.400.000 pts esperados (7.940 clientes × 10.000 pts, una asignación correcta) — **297.050.000 pts de exceso a revertir**. Documenté el hallazgo agregado y el caso límite de 20 clientes en `_ops.md`, marcándolo explícitamente como pendiente de revisión fila por fila (Query 5, no ejecutada aún) en vez de incluirlo en el total de reversión automática.

## 2026-07-22 — Generación del listado completo de clientes implicados

Escribí la Query 7 (listado completo de clientes con exceso > 0, incluyendo `BatchIdsHit` para trazabilidad) y recibí el resultado completo pegado en la sesión. Queda pendiente exportar ese resultado a `implicated_customers.csv` en esta carpeta como listado autoritativo para la fase de reversión.

**Estado:** hallazgo agregado documentado y confirmado. Pendiente: (1) exportar Q7 a CSV, (2) ejecutar Q5 para el caso límite de 20 clientes, (3) definir y ejecutar Q6 para determinar qué proporción del exceso es recuperable (activo) vs. no recuperable (gastado/transferido), (4) decisión de operaciones sobre el mecanismo de reversión.

## 2026-07-22 — Desglose por Note (listado de campaña)

Escribí la Query 8 (conteo agregado por `Note`) y recibí el resultado en la sesión. Confirmé que la suma de puntos por Note (376.450.000) coincide exactamente con el total agregado por cliente de la Query 4, validando la consistencia de ambas vistas. El desglose muestra que "Lista socios ganadores" tuvo 3 lotes (2 reintentos de más) y concentra el 63% del total de puntos otorgados; "Lista 1" tuvo 2 lotes (1 reintento); "Lista 2" y "Campaña recupero" tuvieron un solo lote cada una — su exceso proviene enteramente del solapamiento de población con las otras listas, no de un reintento propio. Agregué la tabla a `_ops.md`.

## 2026-07-22 — Reversión total (no sólo el exceso) para tres de las cuatro listas

Propuse `PointsAdjustmentBatchError-{batchid}` como convención de `EventTypeCode` para las transacciones de reversión, en línea con el patrón dinámico ya documentado (`PointsAdjustment-{uid}`). Confirmé que esto sigue siendo diseño, no una escritura — actualicé `loyalty-fraud-points.md` con la nota correspondiente sobre el `GROUP BY` fragmentado.

Recibí la decisión de que la reversión será **total**, no sólo el exceso: Grido va a volver a correr la campaña completa desde cero, por lo que conviene retirar el 100% de lo otorgado por "Lista socios ganadores", "Lista 1" y "Lista 2" (356.450.000 pts) en vez de calcular y preservar un grant legítimo por cliente. "Campaña recupero" queda fuera de esta reversión — corrió una sola vez, sin reintento.

Escribí la Query 10 (sólo lectura) que genera, fila por fila, la especificación completa de reversión: `CustomerId`, `ManualAssignPointsId` de la fila original, puntos a revertir (negativo), `EventTypeCode` propuesto (`PointsAdjustmentBatchError-{batchid}`) y `Note` de reversión ya armada. Es un `SELECT`, no genera ni ejecuta DML — respeta la regla de sólo-lectura del proyecto; la escritura real queda a cargo de quien tenga permisos sobre producción. Actualicé `_ops.md` con la tabla de puntos a revertir por Note y la sección de acciones propuestas.

**Estado:** especificación de reversión lista (Query 10). Pendiente: (1) ejecutar Query 10 y generar las transacciones reales (fuera de esta sesión), (2) decidir el tratamiento de los 20 clientes del caso límite dado el cambio a reversión total, (3) exportar Query 7 a CSV como respaldo del estado previo a la reversión.

## 2026-07-22 — Validación del resultado de Query 10 y corrección de bug de alias

Recibí el resultado de Query 10 pegado como TSV (35.645 filas) y lo validé programáticamente contra las métricas ya documentadas: el total (356.450.000 pts), el desglose por Note y el conteo de clientes distintos (7.940) coinciden exactamente con lo reportado en `_ops.md`. Confirmé también que no hay pares `CustomerId`+`BatchIdToReverse` duplicados — la especificación es internamente consistente.

Al inspeccionar las columnas del resultado detecté que `DocumentType` traía el DNI numérico y `DocumentNumber` traía el literal `"Dni"` — invertidos. Revisé el uso de `UidCode`/`UidSerie` en otros eventos del proyecto (`20260604_fraude_transferencias`) y confirmé la convención correcta: `UidCode` = tipo de documento, `UidSerie` = número de documento. Las Queries 5, 7 y 10 en `_scripts.sql` tenían el alias invertido (`p.UidSerie AS DocumentType, p.UidCode AS DocumentNumber`); corregí las tres. Los valores de los datos ya recibidos no estaban mal calculados, sólo mal etiquetados — reconstruí el TSV con las columnas en el orden correcto y lo guardé como `20260722_puntos_duplicados_masivos_waf504_query10_reversion.tsv` (reemplaza los archivos de trabajo `out.sql`/`out.tsv`, ya eliminados).

Usando el TSV validado, revisé el punto pendiente sobre los 20 clientes del caso límite (Query 4, `DistinctNotesHit = 1`, total no múltiplo de 10.000): ninguno de los 35.645 registros de Query 10 corresponde a un cliente con un único Note entre las tres listas y suma no múltiplo de 10.000 (0 casos) — y confirmé que toda fila de las tres listas es de exactamente 10.000 pts. Esto indica que el Note único de esos 20 clientes es "Campaña recupero" (fuera de esta reversión), por lo que no requieren tratamiento aparte en Query 10. Queda abierto por qué su suma no es múltiplo de 10.000 si las filas conocidas son siempre de 10.000 — anotado como pendiente de Query 5 en `_ops.md`, no lo doy por resuelto sin ver el detalle fila por fila.

**Estado:** Query 10 validada y lista para uso por el equipo de escritura. Pendiente: (1) ejecutar Query 5 para explicar el total no múltiplo de 10.000 de los 20 clientes del caso límite, (2) exportar Query 7 a CSV como respaldo del estado previo a la reversión, (3) generar las transacciones reales de reversión (fuera de esta sesión).

## 2026-07-22 — Ajuste del texto de `Note` de reversión

Recibí instrucción de cambiar el `Note` de las transacciones de reversión de la fórmula dinámica original (`Reversión por reintento WAF 504 — corrección de: <Note original>`) a un texto fijo. Se ajustó dos veces en la misma sesión hasta el texto final: `Ajustamos tu saldo por un error de asignacion de puntos`. Actualicé Query 10 en `_scripts.sql`, la tabla de convención en `_ops.md`, y regeneré la columna `ReversalNote` en el `.tsv` ya exportado para las 35.645 filas.

## 2026-07-22 — Ampliación de alcance: "Campaña recupero" pasa a incluirse en la reversión

Recibí instrucción de incluir también "Campaña recupero" en la reversión, revirtiendo la decisión anterior (documentada más arriba) de excluirla por no haber tenido reintento propio. No tengo guardado en ningún archivo de esta sesión el literal exacto del `Note` de "Campaña recupero" (Q2/Q8 son agregaciones sin filtro de Note, y su resultado fue pegado en la sesión pero no persistido a un archivo), así que en vez de adivinar el string reescribí Query 10 sin filtro de `Note`: revierte todo lo otorgado hoy bajo `EventTypeCode = 'PrizePoints'` con `ManualAssignPointsId` no nulo, cubriendo las cuatro listas por igual. Actualicé `_ops.md`: la tabla de puntos a revertir pasa a 376.450.000 (suma de las cuatro listas), y dejé explícito que el `.tsv` ya exportado (`20260722_puntos_duplicados_masivos_waf504_query10_reversion.tsv`) quedó parcial — sólo cubre las tres listas originales (356.450.000 pts) y falta re-ejecutar Query 10 para incorporar las filas de "Campaña recupero" (~2.000 filas, 20.000.000 pts) antes de considerar el export completo.

**Estado:** especificación de reversión actualizada a alcance de cuatro listas (376.450.000 pts), aún sin validar contra un resultado real — pendiente: (1) ejecutar la Query 10 actualizada y pegar el resultado para regenerar el `.tsv` completo, (2) re-validar totales contra las cifras esperadas igual que se hizo para las tres listas, (3) ejecutar Query 5 para el caso límite (no bloqueante), (4) exportar Query 7 a CSV, (5) generar las transacciones reales de reversión (fuera de esta sesión).

## 2026-07-22 — Validación del resultado completo de Query 10 (cuatro listas) y cierre del caso límite

Recibí el `.tsv` regenerado (37.645 filas, las cuatro listas incluyendo "Campaña recupero") y lo validé contra las métricas ya documentadas: 376.450.000 pts totales, desglose exacto por Note (incluye Campaña recupero 20.000.000/2.000 clientes) y 7.940 `CustomerId` distintos. También validé el desglose por patrón de duplicación (Query 4) directamente desde el `.tsv`: 1.987 clientes con 3 Notes, 5.933 con 2 Notes, 20 con 1 Note — coincide exactamente con la tabla ya documentada en `_ops.md`, incluyendo los puntos por grupo (119.220.000 / 256.930.000 / 300.000). Sin duplicados de `CustomerId`+`BatchIdToReverse`; toda fila original es de 10.000 pts.

Aproveché el detalle fila por fila para resolver el caso límite (20 clientes, 1 Note) sin ejecutar Query 5: la caracterización original ("total no múltiplo limpio de 10.000") resultó ser un artefacto de promediar el grupo (300.000/20=15.000), no una propiedad real de cada cliente. Desagregado: 10 clientes con un único grant limpio de 10.000 bajo "Lista 2" (sin duplicado, sin exceso) y 10 clientes impactados dos veces dentro de "Lista 1" (mismo Note, dos `ManualAssignPointsId`, 20.000 pts, 10.000 de exceso c/u = 100.000 total, coincide con lo ya reportado). Ambos subgrupos figuran en la salida de Query 10 y quedan cubiertos por la reversión total. Actualicé `_ops.md`: sección "Caso límite" reescrita con esta explicación, Query 5 removida de las acciones propuestas, y la nota de ".tsv desactualizado" reemplazada por la validación completa.

También noté que `DocumentType` en el resultado completo incluye valores además de `Dni` (`DNI`, `CICPy`, `Other`) — coherente con el alcance multi-país de SmartLoyalty (Argentina, Paraguay), documentado como nota menor, no como hallazgo.

**Estado:** especificación de reversión completa (cuatro listas, 376.450.000 pts) validada y lista para el equipo de escritura. Caso límite cerrado. Pendiente: (1) exportar Query 7 a CSV como respaldo del estado previo a la reversión, (2) generar las transacciones reales de reversión (fuera de esta sesión).

## 2026-07-22 — Exportación de `implicated_customers.csv` y corrección del conteo de población con exceso

Se pidió exportar Query 7 a `implicated_customers.csv`. El resultado crudo de Query 7 nunca quedó guardado en un archivo de esta sesión (sólo pegado en una sesión de investigación previa), pero ya tenía en `query10_reversion.tsv` el detalle fila por fila de las cuatro listas, ya validado — suficiente para derivar la misma agregación que produce Query 7 (`CustomerId`, `DocumentType`, `DocumentNumber`, `DistinctNotesHit`, `DistinctBatchesHit`, `TotalPoints`, `ExcessPoints`, `BatchIdsHit`, filtrado a `TotalPoints > 10.000`) sin necesidad de pedir una nueva ejecución. Generé `implicated_customers.csv` de esta forma.

El resultado reveló una inconsistencia real en las métricas ya documentadas: la población con `TotalPoints > 10.000` es **7.930** clientes, no 7.940. El "7.940" de la tabla de Métricas resumen venía de la población total de la campaña (Query 4, sin filtro), no de la población de exceso real (Query 7) — son conceptos distintos que coincidían en número por casualidad hasta ahora. La diferencia son los 10 clientes del caso límite que recibieron un único grant limpio de 10.000 (sin exceso, ver hallazgo anterior). El CSV (7.930 filas) valida: `SUM(ExcessPoints) = 297.050.000`, coincide exacto con el exceso ya reportado — sólo cambia el conteo de clientes y el total de puntos de esa población específica (376.350.000, no 376.450.000).

Corregí la tabla de Métricas resumen en `_ops.md` separando ambos conceptos explícitamente (población total de campaña vs. población con exceso real), agregué una nota de corrección, y actualicé las referencias a "7.940 socios" en las secciones "Detalle de participantes" y "Contabilidad de puntos" a "7.930". La reversión total (376.450.000, cuatro listas, decisión ya tomada) no cambia — sigue incluyendo a los 7.940 porque revierte el 100%, no sólo el exceso.

**Estado:** `implicated_customers.csv` generado y validado (7.930 filas). Métricas del ticket corregidas y consistentes en todas las secciones. Pendiente: generar las transacciones reales de reversión (fuera de esta sesión).

## 2026-07-22 — Diseño y sanity check de Query 6 (estado gastado/activo/transferido/retenido)

Se pidió ejecutar Query 6, pendiente desde la apertura del ticket. No estaba diseñada aún. Antes de escribirla busqué en el clon local del código fuente de SmartLoyalty (`loyalty/repo/dev-src-sol-smartloyalty`) los literales reales de `EventTypeCode` para gasto (`DiscountPointsByExchange`, `DiscountPointsByPromotion`, `RemovePointsBySaleInvalidation`) y transferencia (`PointsByTransferSent`/`PointsByTransferReceived`, `EventTypeTable.cs`), y confirmé que `Sml.Customer.Id` comparte PK con `Sml.Person.Id` (herencia TPT, migración EF `201311132315187_InitialCreate.cs`) — mismo patrón de join ya usado en Q5/Q7/Q10, así que `JOIN Sml.Customer c ON c.Id = g.CustomerId` es seguro. El estado de cuenta activa es `DeativatedDate IS NULL` (confirmado en `CustomerService.cs`, `SpecCustomerActivated`). No existe columna de saldo persistido — se calcula por `SUM(Points)` histórico, igual que lo hace la propia aplicación.

Escribí Q6a (sanity check, dos sentencias) y Q6b (clasificación completa) en `_scripts.sql`, y pedí ejecutar sólo Q6a primero para validar los literales de EventTypeCode y el join contra datos reales antes de confiar en Q6b. Resultado de Q6a: `PointsByTransferSent` (-96.970/16 clientes) y `DiscountPointsByExchange` (-39.600/14 clientes) aparecen en la actividad real de la población desde el grant — confirma los literales. `DiscountPointsByPromotion`/`RemovePointsBySaleInvalidation` no tuvieron filas (no es error, sólo no ocurrieron). El join a `Sml.Customer` funciona (muestra de 20 `DeativatedDate`, todos `NULL`/activos). Q6b queda lista para ejecutar.

**Nota fuera de alcance de este ticket:** Q6a también mostró `CompensationalPoints` — 230.000 pts, 21 filas, 20 clientes distintos, dentro de la misma población afectada hoy. Según memoria de investigaciones previas de fraude, `CompensationalPoints` es un canal ya identificado como vector de explotación. No forma parte del incidente WAF-504 (EventTypeCode y causa raíz distintos) — no se investiga ni se documenta más en este ticket (regla de aislamiento de alcance del proyecto); se lo señalé al usuario aparte para que decida si amerita una investigación separada.

**Estado:** Q6a validada contra datos reales. Pendiente: (1) ejecutar Q6b y pegar el resultado para completar la clasificación gastado/transferido/activo/retenido, (2) generar las transacciones reales de reversión (fuera de esta sesión).

## 2026-07-22 — Q6b devolvió 7.940 filas; pivoteo a Q6c (agregado)

Recibí el resultado de Q6b pegado en la sesión: 7.940 filas, una por cliente de la población de reversión. Decidí no transcribirlo a un archivo — a ese volumen, reproducir manualmente miles de filas de un dataset que alimenta cifras financieras es una fuente real de error de transcripción, y no aporta nada que un agregado server-side no dé de forma más segura. Escribí Q6c en `_scripts.sql`: mismo cálculo de Q6b (gastado/transferido/activo/retenido) pero agregado por `AccountStatus`, así el resultado cabe en 1-2 filas y no depende de copiar miles de valores a mano.

**Estado:** Q6c pendiente de ejecución y resultado. Pendiente: (1) pegar resultado de Q6c, (2) generar las transacciones reales de reversión (fuera de esta sesión).

## 2026-07-22 — Resultado de Q6c: cierre de Query 6

Recibí el resultado agregado de Q6c: los 7.940 clientes de la población de reversión están `Activo` (0 `Retenido`, cuenta desactivada). De los 376.450.000 pts a revertir, 48.100 ya fueron gastados (`DiscountPointsByExchange`, 15 clientes, irreversible) y 104.970 transferidos (`PointsByTransferSent`, 17 clientes) — el resto, 376.296.930 pts (99,96%), sigue como balance activo y totalmente recuperable por la reversión administrativa.

Noté que estos totales son ~8.000 pts más altos que los que había visto en el sanity check de Q6a (ejecutado antes en la sesión) para los mismos EventTypeCode — no es una inconsistencia: el sistema es de producción en tiempo real, y hubo actividad real de socios (gasto/transferencia) en el intervalo entre ambas ejecuciones. Documenté esto como nota de temporalidad en `_ops.md`, junto con la tabla de estado final de puntos y el cierre del ítem 5 de acciones propuestas.

**Estado:** Query 6 completa. Todas las queries pendientes del ticket original están resueltas. Pendiente únicamente: (1) exportar Query 7 a CSV — ya resuelto vía `implicated_customers.csv` (ver entrada anterior), (2) generar las transacciones reales de reversión, fuera del alcance de esta sesión de sólo lectura.

## 2026-07-22 — Re-exportación de `implicated_customers.csv` y export de detalle del caso límite

Se pidió re-exportar `implicated_customers.csv` para confirmar que reflejaba el `.tsv` de Query 10 ya actualizado a las cuatro listas. Regeneré desde `20260722_puntos_duplicados_masivos_waf504_query10_reversion.tsv` (37.645 filas fuente, 7.940 clientes distintos) y el resultado fue idéntico al ya exportado: 7.930 filas, `SUM(ExcessPoints) = 297.050.000` — confirma que el archivo ya estaba al día, sin cambios.

Se pidió también exportar el detalle de los 20 clientes del caso límite "para el registro". Generé `caso_limite_query5.csv` desagregando por `CustomerId` sobre el mismo `.tsv` fuente (filtrando a clientes con un único `Note` distinto). Resultado: 10 filas con `TotalPoints = 20.000` (`DistinctBatchesHit = 2`, todas bajo "Lista 1 socios ganadores") y 10 filas con `TotalPoints = 10.000` (`DistinctBatchesHit = 1`, todas bajo "Lista 2 socios ganadores") — confirma exactamente el hallazgo ya documentado en `_ops.md` (10 duplicados reales dentro de Lista 1, 10 grants limpios de Lista 2). Referenciado el archivo en la sección "Caso límite" del ticket.

**Estado:** Ticket completo — validación, corrección de bug de alias, exceso, caso límite, Query 6 y ambos CSV de registro (`implicated_customers.csv`, `caso_limite_query5.csv`) resueltos. Pendiente único: generar las transacciones reales de reversión, fuera del alcance de esta sesión de sólo lectura.

## 2026-07-22 — Cambio de regla del proyecto y generación de DML de reversión

`loyalty/CLAUDE.md` fue modificado (fuera de esta sesión, por el usuario) para permitir generar DML/DDL cuando se solicita explícitamente — reemplaza la regla anterior de sólo lectura sin excepción. Ante el pedido explícito de generar el `INSERT` real de reversión, y antes de escribirlo, corrí dos queries de metadatos (sólo lectura) sobre `Sml.CustomerPointsLog`: columnas/nullability/triggers, y foreign keys.

El resultado reveló un hallazgo crítico: el trigger `CustomerPointsLogAfterInsert` (activo) recalcula el saldo cacheado del cliente en `SmlSt.CustomerPointsLog` mediante un `JOIN` entre `inserted` y el historial completo por `CustomerId`, sin condición de fila adicional — si un mismo `INSERT` trae más de una fila para el mismo cliente, el `SUM` se multiplica por esa cantidad de filas (fan-out), inflando el saldo cacheado. Confirmé sobre `query10_reversion.tsv` que los clientes de esta reversión tienen entre 1 y 6 filas cada uno — un `INSERT` masivo de las 37.645 filas en una sola sentencia habría corrompido el saldo cacheado de ~7.930 de los 7.940 clientes. Confirmé también (vía `sys.foreign_keys`) que `EventTypeCode` no tiene FK, así que el valor dinámico `PointsAdjustmentBatchError-{batchid}` no requiere pre-existir en ninguna tabla de lookup.

Diseñé la mitigación: dividir la reversión en 6 pasadas secuenciales (`ROW_NUMBER() OVER (PARTITION BY CustomerId ORDER BY ManualAssignPointsId)`), como máximo 1 fila por cliente por pasada, cada una envuelta en su propia transacción con verificación de `@@ROWCOUNT` (7.940 / 7.930 / 7.920 / 7.907 / 3.961 / 1.987 filas esperadas) antes del `COMMIT`. Guardé las 6 pasadas como Query 11 en `_scripts.sql`, con la nota de seguridad completa antes del bloque. Actualicé `_ops.md` con una nueva sección "Reversión — DML generada" documentando el hallazgo del trigger y la tabla de pasadas, y reemplacé el ítem 1 de acciones propuestas.

Esta sesión no tiene permisos de escritura sobre `Sml.CustomerPointsLog` (confirmado en Q1) — Query 11 es una especificación lista para ejecutar por quien sí los tenga, no algo que esta sesión pueda correr.

**Estado:** Query 11 (DML de reversión, 6 pasadas) generada y documentada, con mitigación de un bug de trigger real que de otro modo hubiera corrompido saldos de producción. Ticket listo para pasar a fase de ejecución por el equipo con permisos de escritura.

## 2026-07-22 — Ejecución de Query 11: Pasada 1 de 6

El login original usado durante la investigación no tiene permiso `INSERT` sobre `Sml.CustomerPointsLog` (confirmado por `Msg 229` al intentar la Pasada 1, consistente con lo ya documentado en Q1) — se hizo `ROLLBACK` de esa transacción abierta. La Pasada 1 se re-ejecutó con una cuenta con permisos de escritura: **7.940 filas insertadas, coincide exactamente con lo esperado**. Confirmé el match y indiqué `COMMIT`.

**Estado:** Pasada 1 de 6 completa y confirmada. Pendiente: Pasadas 2-6 (7.930 / 7.920 / 7.907 / 3.961 / 1.987 filas esperadas respectivamente), cada una a ejecutar y confirmar antes de avanzar a la siguiente.

## 2026-07-22 — Ejecución de Query 11: Pasada 2 de 6

7.930 filas insertadas — coincide exactamente con lo esperado. `COMMIT` confirmado.

**Estado:** Pasadas 1-2 de 6 completas. Pendiente: Pasadas 3-6 (7.920 / 7.907 / 3.961 / 1.987 filas esperadas).

## 2026-07-22 — Pasada 3 de 6 y verificación de duplicado ambiguo

Al pedir el resultado de la Pasada 3, recibí un resultado idéntico al de la Pasada 2 (mismo `RowsInserted = 7930`, mismo timestamp de finalización) — señal de un posible copy-paste erróneo o de una re-ejecución accidental de la Pasada 2. Pedí no hacer `COMMIT` y verificar `@@TRANCOUNT` antes de continuar. Recibí en su lugar un nuevo resultado (7.920 filas, timestamp distinto, coincide con lo esperado para la Pasada 3) — pero el usuario hizo `COMMIT` sin correr la verificación de `@@TRANCOUNT` que había pedido.

Dado que ya no se puede deshacer un `COMMIT`, verifiqué el estado real de la tabla en lugar de la transacción: (1) conteo total y suma de puntos de filas `PointsAdjustmentBatchError-%` de hoy — resultado 23.790 filas / -237.900.000 pts, coincide exactamente con 3 pasadas limpias (7.940+7.930+7.920); (2) búsqueda de `CustomerId`+`EventTypeCode` duplicados entre esas filas — 0 resultados. Ambas verificaciones confirman que el resultado ambiguo fue un error de copy-paste, no una ejecución duplicada real. No hay filas de reversión duplicadas en producción.

**Estado:** Pasadas 1-3 de 6 completas y verificadas contra el estado real de la tabla (no sólo contra el output de la sesión). Pendiente: Pasadas 4-6 (7.907 / 3.961 / 1.987 filas esperadas).

## 2026-07-22 — Pasada 4 de 6

7.907 filas insertadas — coincide exactamente con lo esperado. `COMMIT` confirmado.

**Estado:** Pasadas 1-4 de 6 completas. Pendiente: Pasadas 5-6 (3.961 / 1.987 filas esperadas).

## 2026-07-22 — Pasada 5 de 6

3.961 filas insertadas — coincide exactamente con lo esperado. `COMMIT` confirmado.

**Estado:** Pasadas 1-5 de 6 completas. Pendiente: Pasada 6 (1.987 filas esperadas) — última pasada.

## 2026-07-22 — Pasada 6 de 6 y verificación final: reversión completa

1.987 filas insertadas — coincide exactamente con lo esperado. `COMMIT` confirmado.

Corrí la verificación final por query (no sólo por output de sesión, dado el incidente de la Pasada 3): conteo total de filas `PointsAdjustmentBatchError-%` de hoy = **37.645 filas, -376.450.000 pts**, coincide exactamente con el total esperado de las 6 pasadas y con el monto validado en `_ops.md` para las cuatro listas de la campaña. Búsqueda de `CustomerId`+`EventTypeCode` duplicados = **0 filas**. Documenté ambos resultados en `20260722_puntos_duplicados_masivos_waf504_reversion_evidencia.md`, que pedí crear como registro de evidencia dedicado (creado luego de la Pasada 5) con el detalle verbatim de las 6 pasadas, el incidente de la Pasada 3, y ambas verificaciones (post-Pasada 3 y final).

**Estado: REVERSIÓN COMPLETA Y VERIFICADA.** Las 376.450.000 pts otorgados bajo las cuatro listas de la campaña ("Lista socios ganadores", "Lista 1", "Lista 2", "Campaña recupero") fueron revertidos en su totalidad, sin duplicados, verificado por query directa sobre la tabla. Ticket cerrado del lado de la reversión — no quedan acciones pendientes de esta sesión.

## 2026-07-22 — Asignación manual "Puntos por visita frecuente" (no relacionada al incidente)

Recibí un pedido separado, no relacionado al incidente WAF-504: asignar 10.000 pts a cada `CustomerId` de `assignment.csv` (`EventTypeCode = 'ManualPrizePoints'`, `Note = 'Puntos por visita frecuente'`). Antes de generar cualquier DML comparé los 7.940 `CustomerId` de `assignment.csv` contra la población ya revertida por el incidente (`query10_reversion.tsv`) — encontré superposición del 100%, sin adiciones ni omisiones, sin duplicados dentro del archivo. Al ser una coincidencia exacta con una población que acababa de perder 376.450.000 pts por reversión, no asumí que fuera intencional — pregunté explícitamente antes de continuar. Confirmé que sí lo era.

Diseñé la carga en 7 pasos (Query 12, `_scripts.sql`): tabla de staging en `SmlTemp` (aprobada explícitamente por el usuario), carga de `assignment.csv`, verificación de carga, validación de integridad referencial contra `Sml.Customer`, `INSERT` real, verificación final, limpieza. Como cada cliente aparece una sola vez en la fuente (sin duplicados), no aplica el bug de fan-out del trigger `CustomerPointsLogAfterInsert` (documentado en Q11) — un solo `INSERT` es seguro, sin necesidad de pasadas múltiples.

El Paso 2 (`BULK INSERT` desde `assignment.csv`) falló: `Msg 4860`, el path (`C:\Users\dantep\Documents\assignment.csv`) es local a la máquina cliente, no visible para el motor de SQL Server en `SFCG-DB01`. Como ya tenía el contenido del archivo leído localmente en esta sesión, generé la carga como 8 lotes de `INSERT...VALUES` (tope de 1.000 filas por sentencia en T-SQL) — `20260722_puntos_duplicados_masivos_waf504_q12_paso2_values.sql` — sin dependencia de acceso a filesystem del servidor. Los 8 lotes se ejecutaron sin errores: 1.000×7 + 940 = 7.940 filas, coincide exactamente.

Verifiqué la carga (7.940 filas en staging) y la integridad referencial (0 `CustomerId` sin correspondencia en `Sml.Customer`) antes de tocar la tabla real. El `INSERT` en `Sml.CustomerPointsLog` insertó 7.940 filas — coincide. Verificación final por query: `COUNT(*)` / `SUM(Points)` de filas `ManualPrizePoints` de hoy = 7.940 filas, 79.400.000 pts, coincide exactamente. Instruí el `DROP TABLE` de limpieza tras confirmar.

Documenté el detalle verbatim en `20260722_puntos_duplicados_masivos_waf504_asignacion_evidencia.md`, y agregué una sección dedicada en `_ops.md` (marcada explícitamente como no relacionada al incidente) — inicialmente sólo había quedado en el `.sql` y en el archivo de evidencia, sin reflejarse en el ticket principal ni en este log paso a paso; corregido tras notarlo.

**Estado:** asignación manual completa y verificada — 7.940 clientes, 79.400.000 pts, `EventTypeCode = 'ManualPrizePoints'`. Documentación retroactivamente alineada con el resto del ticket.

## 2026-07-22 — Email de cierre para PMs

Generé `20260722_puntos_duplicados_masivos_waf504_email_pm.md` con la skill `loyalty-sre-output` — cierre del incidente en lenguaje no técnico, sin código, sin detalle interno de Operations (permisos, triggers, pasadas de reversión), y sin mencionar la asignación manual de "puntos por visita frecuente" (Query 12), asumiendo en ese momento que era una acción no relacionada al incidente.

## 2026-07-22 — Corrección: la reasignación manual SÍ es la resolución del incidente

Recibí la corrección de que la asignación manual de Query 12 no es una acción aparte — es la corrida "desde cero" de la campaña ya anunciada en la Decisión de reversión, hecha a mano vía SQL validado en lugar de `MassivePointsAssignment` justamente para no repetir la falta de idempotencia que causó el incidente original. Corregí la caracterización en los cuatro lugares donde la había documentado como "no relacionada": `_ops.md` (título y cuerpo de la sección, ítem 3 de acciones propuestas), `_asignacion_evidencia.md` (título, intro, estado final), `_scripts.sql` (comentario de cabecera y nota antes de Q12).

Actualicé también el email a PMs (`_email_pm.md`), que tenía la información desactualizada — decía que los socios "quedaban a la espera" de que Grido corriera la campaña de nuevo, cuando en realidad ya está corrida y verificada. Reescribí la sección "Resolución" para reflejar ambos pasos completos (reversión + reasignación correcta) y quité la frase de "a la espera".

**Estado:** documentación alineada — el incidente está cerrado de punta a punta (causa raíz, reversión de 376.450.000 pts duplicados, reasignación correcta de 79.400.000 pts a los 7.940 ganadores) en `_ops.md`, `_ops-events.md`, ambos archivos de evidencia, `_scripts.sql` y el email a PMs.
