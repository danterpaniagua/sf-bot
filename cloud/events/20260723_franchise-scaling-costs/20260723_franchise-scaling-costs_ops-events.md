# Eventos — Validación de costos y proyección por escala de franquicias

## 2026-07-23 10:00 — Pedido inicial de proyección a 1.000/2.000/2.600 franquicias

He recibido el pedido de cotizar la infraestructura Graylog escalada a 1.000, 2.000 y 2.600 franquicias, con base en el volumen ya medido para 170 franquicias actuales (259M eventos/7 días, `cloud-graylog/20260625_cloud-graylog-costs`). He construido una primera proyección lineal usando la estimación ya aprobada como base, incluyendo una advertencia sobre el límite de 20 Throughput Units por namespace de Event Hubs Standard, que se cruza entre 1.000 y 2.000 franquicias.

## 2026-07-23 11:00 — Reemplazo de cada supuesto por datos reales

He medido el tamaño real por evento en dos pasos: primero vía `_BilledSize` en Log Analytics (~194 bytes/evento, tamaño crudo pre-pipeline), y después directo en OpenSearch (`_cat/indices` en `sfcloud-monitoreo`) para obtener el tamaño real indexado, que incluye el overhead de Logstash y de OpenSearch. Con Business + Sales (234.951.609 docs / 94 GB) calculé un ratio real de **~430 bytes/evento** — menos de la mitad del supuesto original (~970 bytes/evento).

## 2026-07-23 11:30 — Corrección del precio de Event Hubs Standard TU

He verificado el precio real de Event Hubs vía Azure Retail Prices API y encontré que **Standard Throughput Unit cuesta $0,03/hora (~$21,90/mes)**, casi el doble del ~$11/mes usado en toda la estimación aprobada y documentado en `cloud-graylog/CLAUDE.md`. Identifiqué que ese ~$11/mes coincide casi exacto con la tarifa de **Basic** tier ($0,015/hora), lo que indica que se aplicó por error el precio de un tier distinto al de la arquitectura Standard efectivamente decidida. Recalculé el costo de Event Hub para los 4 escenarios con la tarifa corregida.

## 2026-07-23 12:00 — Confirmación del precio de cómputo (sin corrección necesaria)

He verificado el precio real de `E16s_v5`/`E16s_v6` — confirmé que **E16s_v5 Regular (Linux, no Spot/Low Priority) = $736,00/mes**, coincidiendo exacto con la estimación ya aprobada. Este componente no requería corrección. Encontré además que `cloud-graylog/CLAUDE.md` nombra "E16s_v6" en la tabla de sizing pero "E16s_v5" en las tablas de costo — inconsistencia documental pendiente de resolver.

## 2026-07-23 13:00 — Verificación de costo por consulta en Log Analytics

Evalué si Azure Log Analytics tiene costo oculto por consulta (distinción real entre plan "Analytics Logs", que incluye consultas gratis, y "Basic Logs", que cobra por GB escaneado en cada consulta). Intenté `az costmanagement query`, pero la extensión instalada (v1.0.0) no tiene ese comando en este entorno — solo `export` y `show-operation-result`, incluso después de reinstalarla. Usé el Portal de Azure (Cost Analysis, agrupado por Meter) como alternativa, mismo método ya validado para el bill real de junio.

El desglose real de la facturación completa de la suscripción mostró **un solo meter para Log Analytics: "Analytics Logs Data Ingestion", $525,58** — sin ninguna línea de "Data Analyzed" ni "Data Retention". Confirmé que **Log Analytics no tiene costo de consulta ni de almacenamiento separado** en el plan actual (`pergb2018`).

Ese mismo desglose reveló de forma incidental los costos reales de la infraestructura Graylog ya desplegada: VM `D8s v6` (todavía tamaño de pilot, no de flota completa), discos `P6`+`P10` (muy por debajo del P30 asumido para flota completa), y Event Hub TU real (~$15,60 parcial del mes, consistente con la tarifa corregida). Esto refuerza que la estimación de flota completa puede estar sobredimensionada también en cómputo, aunque no lo confirmé formalmente.

## 2026-07-23 13:30 — Retención real de Log Analytics

Verifiqué la retención real configurada vía `az monitor log-analytics workspace show` — confirmé **30 días**, SKU `pergb2018`. Until esta consulta no tenía el dato real, solo el supuesto documentado por Azure.

## 2026-07-23 14:00 — Cobertura real de Graylog vs. Insights

Verifiqué contra `docs/infrastructure.md` el inventario completo de App Services compartidos (8 en total: Pos, Admin, Business, Sales, Orders, Platform, Person, Catalog, más 3 Function Apps) y lo crucé con los índices reales en OpenSearch (C2, `sfcloud-monitoreo`). Confirmé que **Graylog hoy solo ingiere Business y Sales — 2 de 8 App Services** — el resto de la flota no tiene ningún log en Graylog, solo en Log Analytics. Esto significa que el escenario "Solo Graylog" de la cotización (dar de baja Insights) no es equivalente en cobertura tal como está hoy: dejaría sin visibilidad de logs a la mayoría de los servicios, salvo que se cotice y ejecute antes el onboarding del resto.

## 2026-07-23 14:30 — Utilización real semanal de la VM Graylog (Zabbix)

Sumé el dato de Zabbix de `sfcloud-monitoreo` para la semana en curso: CPU utilization avg 3% / max 31%, Memoria avg 63% / max 64%. Confirma, con una ventana más amplia que la foto puntual de `free -h` (C3), que la VM pilot `D8s v6` no muestra señales de estrés sostenido sirviendo Business + Sales.

## 2026-07-23 14:45 — Costo real de retención extendida en Log Analytics

Completé H7 con el dato de precio ya capturado en C7 pero no reflejado antes en el hallazgo: retener datos más allá de los 30 días incluidos en Log Analytics cuesta USD 0,10/GB/mes (`Analytics Logs Data Retention`). Lo agregué también al email a PMs, ya que es un costo real que Graylog no tiene (su retención depende solo del disco asignado, no de un meter aparte).

## 2026-07-23 15:00 — Estimación de costo de retención a 1 año

Calculé el impacto de extender la retención de Log Analytics de 30 a 365 días, sobre el volumen real de ingesta ya confirmado en C9 (228,5 GB/mes a 170 franquicias) y la tarifa real de retención extra de C7 (USD 0,10/GB/mes): ~USD 251/mes a 170 franquicias, ~USD 1.479/mes a 1.000, ~USD 2.958/mes a 2.000 y ~USD 3.846/mes a 2.600, en régimen (a partir del mes ~11). Agregué el resultado como H10 en el ticket y como sección nueva en el email a PMs, con la aclaración de que no está confirmado el período de retención asumido en el dimensionamiento de disco ya cotizado para Graylog.

## 2026-07-23 15:15 — Riesgo de disponibilidad: Graylog como "fusible" de capacidad fija

Documenté un riesgo arquitectónico señalado en la conversación: a diferencia de Insights (PaaS elástico, sin techo de capacidad para el cliente), la VM de Graylog tiene disco y memoria fijos — un aumento de verbosidad no controlado o el onboarding de más apps sin reprovisionar recursos podría llenar el disco o saturar el heap de OpenSearch y detener la ingesta de logs. Marqué esto como riesgo identificado por arquitectura (comportamiento conocido de OpenSearch), no como fallo reproducido — la evidencia parcial que lo respalda es el baseline de memoria de 63-64% ya visto en H8, sirviendo solo 2 de 8 App Services. Lo agregué como H11 en el ticket y como párrafo de riesgo en el email a PMs.

## 2026-07-23 15:30 — H11 ampliado con el ángulo de costo (válvula de seguridad)

Amplié H11 para cubrir el otro lado del mismo mecanismo: el costo de Insights escala en tiempo real y sin techo con el volumen (un error de verbosidad dispara la factura de inmediato), mientras que el costo de Graylog es fijo y no sube con más volumen dentro de su capacidad. Dejé explícito que esa "protección" de costo en Graylog no es gratuita — se logra porque Graylog deja de poder ingerir al tocar su límite de disco/heap, el mismo mecanismo que ya documenté como riesgo de disponibilidad. Actualicé el ticket y el email para reflejar el trade-off completo (riesgo de costo en Insights vs. riesgo de disponibilidad en Graylog), no solo el lado favorable a Graylog.

## 2026-07-23 15:45 — Tabla de pros/contras desde presupuesto

Agregué al email a PMs una tabla de pros/contras Graylog vs. Insights enfocada en presupuesto (no en el total de dólares, ya cubierto en la tabla de costos), construida sobre los hallazgos H1-H11 ya documentados: costo fijo vs. elástico, riesgo de disponibilidad vs. riesgo de presupuesto descontrolado, gaps de cobertura y capacity planning aún pendientes.

## 2026-07-23 16:00 — Referencias a Hallazgos en el email + H12 nuevo

Agregué `(H#)` a cada afirmación del email que corresponde a un Hallazgo del ticket, para que quede trazable. Encontré una afirmación (alertas/dashboards/Search Jobs, ya verificada en la conversación pero nunca promovida a Hallazgo) sin número — la agregué como H12 al ticket, referenciando el script C12 (ya registrado, curl a Azure Retail Prices para Azure Monitor) que no tenía fila en la tabla de Comandos ejecutados. La corregí también.

## 2026-07-23 16:15 — Reversión de referencias (H#) en el email

Quité todas las referencias `(H#)` que había agregado al email a PMs — no crea siempre el ticket de Jira correspondiente, así que una referencia a un hallazgo interno puede terminar sin destino. El contenido de cada aclaración se mantuvo intacto, solo se quitó el número entre paréntesis. Las referencias siguen existiendo en el ticket interno (`_ops.md`), que es donde corresponden.

## 2026-07-23 16:30 — Corrección de una inconsistencia real: PAYG vs. reserva de 1 año

Al revisar si el email a PMs era consistente con el análisis completo, leí el email anterior real (`cloud-graylog/.../20260625_cloud-graylog-costs_email_pm_insights-vs-graylog.md`, solo lectura) y encontré que su conclusión de "ahorro modesto" dependía específicamente de una reserva de 1 año (Graylog $609/mes reservado vs. Insights $679/mes) — el mismo email ya advertía que sin reserva, Graylog seguía siendo más caro. Confirmé que toda la cotización de este ticket usa precios pay-as-you-go (C4, C5, C6), sin excepción. Eso significa que la nota que había escrito ("la conclusión aplica a 170 franquicias, se revierte a partir de 1.000") estaba mal planteada — bajo PAYG, Graylog ya era más caro que Insights a 170 franquicias, consistente con la propia advertencia del email original, no una reversión a escala. Corregí el ticket (agregué H13, corregí la fila de Recursos afectados y agregué la acción propuesta 11) y el párrafo correspondiente en el email a PMs.

## 2026-07-23 16:45 — Costo de reprocesar JSON en ingesta (transformación)

Verifiqué contra la tarifa real de Azure Monitor (C13) que reprocesar el JSON crudo en pares clave:valor sí tiene costo si se hace como transformación de ingesta (Data Collection Rule): `Logs Processed GB`, USD 0,10/GB, aparte del costo de ingesta. Estimé el impacto sobre el volumen real ya usado en H10: ~USD 23/mes a 170 franquicias hasta ~USD 349/mes a 2.600. Aclaré que si el parseo se hace en la consulta KQL del dashboard en vez de en la ingesta, no tiene costo. Agregué esto como H14 en el ticket y como sección nueva en el email a PMs (sin referencias de hallazgo, según la corrección pedida antes).

## 2026-07-23 17:00 — Tabla consolidada de costos fantasma de Insights

Agregué al email a PMs una tabla que combina los dos costos "fantasma" de Insights ya documentados por separado (retención a 1 año y split de JSON en ingesta), justo después de la tabla de costos proyectados, para que quede claro que la fila "Solo Insights" no los incluye. Total combinado: ~USD 274/mes a 170 franquicias hasta ~USD 4.195/mes a 2.600.

## 2026-07-23 17:15 — Descuento real de reserva de 1 año, por componente

Verifiqué contra la tarifa real de Azure (C14) el descuento de reserva de 1 año para cada componente de Graylog: VM (`E16s_v5`) ~41% más barata reservada; Storage Premium SSD solo tiene reserva a partir de P30, no para el P20 que realmente se necesita (H2); Event Hubs Standard no tiene ninguna opción de reserva/compromiso. El descuento combinado real es ~34%, no el ~20% que se venía asumiendo. Agregué esto como H15 en el ticket y reescribí la "Nota sobre el email anterior" en el email a PMs — con reserva, Graylog sería más barato que Insights en los 4 escenarios, pero dejé explícito que esto se apila sobre H4/H5/H9 todavía sin resolver, y no debe presentarse como cifra final.

## 2026-07-23 17:20 — Tabla Insights vs. Graylog reservado en la nota del email anterior

Agregué una tabla comparativa a la "Nota sobre el email anterior" del email a PMs, con Insights vs. Graylog con reserva de 1 año (~34% de descuento combinado, H15) en los cuatro escenarios — Graylog reservado resulta más barato en los cuatro, con la diferencia creciendo de ~$94/mes a 170 franquicias hasta ~$1.539/mes a 2.600.

## 2026-07-23 17:35 — Verificación real: Orders sin logging configurado

Verifiqué en vivo (`az monitor diagnostic-settings list` sobre el App Service de Orders, C15) — resultado vacío, sin ningún Diagnostic Setting. Confirmé que la excepción ya señalada en el email de PMs del 2026-06-25 ("Orders todavía no tiene logging configurado") sigue vigente hoy. Corregí H9 (que decía incorrectamente que Orders estaba "solo en Log Analytics") y agregué H16 para dejar esto documentado como su propio hallazgo, con acción propuesta 14. Corregí también la aclaración correspondiente en el email a PMs, y aclaré el uso de "1 año" en la nota sobre reserva de infraestructura para no confundirlo con la retención de datos — ambos puntos señalados en la revisión de consistencia del email.

## 2026-07-23 17:45 — Tabla combinada: costos fantasma + reserva

Agregué al email a PMs una tabla que combina las cuatro variantes ya cotizadas por separado (Insights base, Insights + costos fantasma, Graylog pago por uso, Graylog con reserva de 1 año) en un solo cuadro por escenario. Encontré, al armarla, algo que no habíamos señalado antes: si los costos fantasma de Insights (retención 1 año + split de JSON) terminan aplicando, Graylog ya queda más barato incluso sin reserva, en los cuatro escenarios — no hace falta esperar a la reserva de 1 año para que la cuenta lo favorezca en ese caso. Agregué esa aclaración junto con la tabla, dejando las mismas advertencias de H5/H9 vigentes.

## 2026-07-23 — Corrección de ubicación del registro (este archivo)

Había registrado este trabajo por error directamente dentro del repositorio `cloud-graylog` (`~/Documentos/git/cloud-graylog/operations/events/`), tratándolo como si fuera el lugar correcto para nuevos artefactos — cuando en realidad ese directorio es de solo lectura para mí, igual que `loyalty/repo/`, `cloud/repo/` y `smartpedidos/repos/` en este monorepo. Corregí eliminando los 3 archivos que había creado ahí (verifiqué con `git status` que no tocaba ningún cambio preexistente del usuario en ese repo) y recreé este registro en la ubicación correcta: `bots/cloud/events/`.

## 2026-07-27 — Nueva sección: agregar segunda VM WebServiceV2 (SmartLoyalty)

Agregué al ticket (H17, fila de Recursos afectados, C16, acción propuesta 15) la propuesta de sumar `SFCG-WSV2-02` junto a `SFCG-WSV2-01` (WebServiceV2, SmartLoyalty, suscripción Smart IT - Grido) — hoy corre como instancia única, mismo patrón de punto único de falla ya documentado para `SFCG-WSIT-01` en `loyalty/docs/infrastructure.md`. No coticé el componente: el SKU/tamaño real de la VM no está documentado en ningún lado del repositorio, así que agregué el comando `az vm show` (C16) para que se confirme antes de traer el precio real vía Azure Retail Prices API. Dejé explícito que no debe asumirse el mismo precio que la VM de `cloud-graylog` (E16s_v5/v6) — distinta suscripción, posiblemente distinta región.

## 2026-07-27 — Corrección: SFCG-WSV2-02 ya existe, y nunca fue encendida

He ejecutado C16 (`az vm show`) y he encontrado que **`SFCG-WSV2-02` ya está desplegada** — no era una propuesta, era infraestructura real no documentada en `loyalty/docs/infrastructure.md`. Tamaño real: `Standard_D8as_v5` (`-01`) vs. `Standard_D2ds_v4` (`-02`), asimétricos en tamaño y familia. Aclaré después que `-02` **nunca fue encendida** — no es una secundaria on-demand, es un recurso provisto y nunca puesto en servicio. Corregí H17, la fila de Recursos afectados, la acción propuesta 15, y `loyalty/docs/infrastructure.md` para reflejar que WebServiceV2 corre hoy con un solo servidor activo (mismo patrón de punto único de falla que `SFCG-WSIT-01`). Agregué C18 (`az vm get-instance-view` + Activity Log) para confirmar el historial de encendido y el estado de power actual antes de precisar costo (disco/IP sin cómputo activo) o decidir si se pone en servicio o se da de baja.

## 2026-07-27 — Precio real de SFCG-WSV2-01 (C17)

He ejecutado C17 (Azure Retail Prices API, `Standard_D8as_v5`, `eastus`). Usé la tarifa Windows Regular ($0,712/hs) — no la Linux Regular ($0,344/hs) — por patrón de toda la flota SmartLoyalty (rutas `D:\`/`C:\`, cuenta `SMARTIT\itservices`, DB en Windows Server 2022), pero dejé explícito que el sistema operativo real no está confirmado por una query directa (`storageProfile.osDisk.osType`), a diferencia del resto de datos de este ticket que sí vienen de un comando real. Calculado a 730 hs/mes (misma convención ya usada para `E16s_v5` en este ticket): **~$519,76/mes**. Agregado a H17 y C17, marcado como pendiente de confirmación de SO.

## 2026-07-27 — Power state de SFCG-WSV2-02 confirmado; límite de Activity Log

He ejecutado C18. `az vm get-instance-view` confirmó power state real: **Deallocated**. El intento de Activity Log con `--offset 365d` falló: `(BadRequest) The start time cannot be more than 90 days in the past` — límite duro de Azure, no ajustable por flag. Reintenté con `--offset 90d` (máximo permitido) y encontré una acción `deallocate` exitosa hoy ~16:56 UTC, sin ningún `start` en esos 90 días — es decir, ya estaba corriendo antes de esa ventana. Esto contradijo mi hipótesis inicial de "nunca encendida", así que pregunté directamente si acababa de deallocarla yo mismo como parte de esta investigación.

Confirmé que sí: la deallocé yo mismo, ~1 hora antes de este registro. Intenté además obtener la fecha de creación real del recurso (C19, `az resource show --api-version 2026-03-01`) para acotar desde cuándo estaba corriendo, pero `systemData.createdAt` no está poblado para este recurso — límite conocido de Azure para recursos que datan de antes del rollout de ese campo. Aclaré directamente que había estado encendida ~3 días antes del deallocate de hoy. Corregí H17, la fila de Recursos afectados, la acción propuesta 15 y `loyalty/docs/infrastructure.md` para reflejar la cronología real: no "nunca encendida", sino ~3 días encendida sin uso ni redundancia real, ahora apagada. Agregué C20 y C21 (SO de `-02` y precio real de `D2ds_v4`) para cuantificar el costo exacto de esas ~72 horas.

## 2026-07-27 — Costo real final: ~$14,76

Recibí el precio real de `D2ds_v4` (C21, Azure Retail Prices API) y, por separado, el SO real de `SFCG-WSV2-02` (C20, `az vm show`): **Windows**, confirmado por query directa. Con la tarifa Windows Regular ($0,205/hs) calculé el costo real de las ~72 horas encendida: **~$14,76** — un monto bajo en términos absolutos, dado el tamaño chico de la VM (2 vCPU). Actualicé H17, C20, C21 y el resumen de severidad en el ticket para dejar claro que el hallazgo relevante acá es operativo (una segunda instancia encendida ~3 días sin uso ni redundancia real), no financiero.

## 2026-07-27 — Corrección: C17 no reflejaba la confirmación de SO ya obtenida

Al revisar si el costo de `SFCG-WSV2-01` estaba realmente en el ticket, encontré que C17 seguía diciendo "SO Windows inferido, pendiente confirmar" — a pesar de que ya había confirmado Windows por query directa antes de cerrar ese hallazgo. Quedó sin actualizar por un descuido mío. Corregí C17 para reflejar el estado real: SO Windows confirmado, costo $519,76/mes final, no pendiente de nada.

## 2026-07-28 — Reconciliación de la cotización de Datadog contra este ticket

Recibí una cotización de Datadog ya calculada (precios públicos de datadoghq.com) proyectada a 1.000/2.000/2.600 franquicias, junto con volumen real medido de Sales+Business (12.099.202 eventos/día, 2026-07-27) extrapolado a flota completa vía un factor de cobertura de 70-80%. Encontré que ese volumen extrapolado (~15,1-17,3M eventos/día) no coincide con dos mediciones directas propias, ya existentes en `cloud-graylog/CLAUDE.md` y en este ticket (C1): ~37-41M eventos/día, medidas de forma independiente el 2026-06-25 y el 2026-07-23. Verifiqué que el factor de cobertura de 70-80% sí está bien respaldado por un dato real (Business 70,3% + Sales 4,07% del total de flota, medido 2026-07-02) — pero eso no resuelve cuál de las dos bases absolutas es la correcta. Documenté esto como H19 y H20, sin elegir una cifra por sobre la otra.

## 2026-07-28 — Descarte de la teoría de drift como explicación de la brecha

Al analizar en vivo los índices reales de OpenSearch (evento separado `20260728_logging-verbosity-ef-core-cors`), encontré que `AppServiceConsoleLogs` de Business está activo y es su categoría de mayor volumen — contradice la nota de drift de `cloud-graylog/CLAUDE.md` que se venía usando como explicación de la brecha de H19. Documenté esto como H21 en este ticket, dejando la brecha de H19 sin explicación causal nuevamente.

## 2026-07-28 — Corrección de H4 con datos reales de hora pico

Con datos reales de hora pico (800K eventos/hora, 2026-07-27) pude calcular el ratio pico/promedio real (~1,6x) y lo comparé contra H4 (techo de 20 TU/namespace de Event Hubs excedido a 2.000-2.600 franquicias). Revisé `scripts.sh` completo y no encontré ningún cálculo guardado que respalde H4 — viene de la primera proyección lineal del 2026-07-23, antes de las correcciones con datos reales, y usa un multiplicador pico/promedio no documentado. Con el ratio real, el techo de 20 TU no se cruza ni en el escenario más alto. Documenté esto como H18, degradando H4 de "confirmado" a "pendiente de re-verificar".

## 2026-07-28 — Corrección del proxy de bytes/evento de Datadog

Encontré que la cotización de Datadog usa un proxy de ~270 bytes/evento sin verificar, cuando este ticket ya midió el dato real dos veces (194 bytes/evento crudo vía `_BilledSize`, C1; 430 bytes/evento indexado en OpenSearch, C2). Documenté esto como H22 — recomendando sustituir el proxy por el dato real crudo (194 bytes/evento, comparable al modelo de facturación de Datadog).

## 2026-07-28 — Escritura de la comparación multi-plataforma en el ticket

Agregué la sección "Comparación de costos multi-plataforma a escala" con las cifras de Datadog (1/6/12 meses de retención) junto a Insights y Graylog self-hosted ya cotizados, dejando explícito que las cifras de Datadog fueron provistas ya calculadas, no verificadas de forma independiente en este ticket. Agregué también una nota sobre el método alternativo de estimación de Graylog a escala (basado en cantidad de nodos según el techo real de heap), que difiere hasta ~3x del escalado lineal ya usado, sin reemplazar el capacity planning real todavía pendiente (H5). Agregué las acciones propuestas 16-19 y referencié el ticket nuevo `20260728_logging-verbosity-ef-core-cors` en Recursos afectados.
