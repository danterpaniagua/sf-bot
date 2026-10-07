Asunto: Órdenes de sucursales de Perú bloqueadas en estado Pendiente — SmartCloud Orders API

Estimados,

Les escribo para informar sobre un problema activo en la Orders API de SmartCloud (`SmartFran-Cloud-Orders-PRO`) que afectó a un subconjunto de órdenes de sucursales de Perú, y a compartir el diagnóstico realizado hasta el momento.

**Detalle**

Un subconjunto de las órdenes de sucursales de Perú no llegó a confirmarse en la Orders API: quedan indefinidamente en estado "Pendiente" del lado de SmartPedidos. La Orders API consume estas órdenes directamente desde AWS SQS (una cola FIFO por sucursal, publicada por `platforms-service`); cuando eso falla para una orden puntual, el mensaje queda reintentándose en la cola hasta que expira por política de retención (3 días) sin llegar nunca a confirmarse ni a la Dead Letter Queue.

Al momento de este reporte se identificaron 12 órdenes en esta condición, con antigüedad de entre 3 y 14 días, distribuidas entre varias sucursales y plataformas (PedidosYa, Rappi, PediGrido). El tiempo normal de procesamiento de una orden que sí se completa es de pocos minutos (mediana ~4 min sobre ~2900 órdenes de Perú en los últimos 7 días).

**Impacto**

Acotado en volumen — 12 órdenes bloqueadas sobre un volumen mucho mayor que se procesa con normalidad — pero real: cada una es un pedido de cliente que la sucursal nunca llega a ver.

**Hipótesis**

La causa raíz identificada es un defecto puntual en `TimeZoneCountries.cs` (Orders API): la función que asigna zona horaria a la orden reconoce explícitamente solo 4 países (Argentina, Chile, Uruguay, Paraguay); para cualquier otro país no listado — Perú incluido — cae a una rama de respaldo que intenta resolver el ID de zona horaria de Windows `"Argentina Standard Time"` en lugar de un ID IANA (`America/Argentina/Buenos_Aires`). En el contenedor Linux donde corre la Orders API esa resolución falla con una excepción no controlada (`TimeZoneNotFoundException`), que aborta el procesamiento del mensaje SQS antes de persistirlo.

El código de esta migración (.NET 8 a .NET 10) fue mergeado el 2026-09-07 (commit `c7fa45721`, ticket GSFC-998). El camino real hasta producción, reconstruido a partir del historial de despliegue y del log de actividad de Azure: el 2026-09-16 a la noche se desplegó una nueva build al slot de staging (`stg2`) de Orders; hoy, 2026-09-17 a las 06:00, se realizó el swap de ese slot a producción (`SwapWebSite`, con su verificación previa de diferencias entre slots y su calentamiento posterior — procedimiento estándar, no apurado). Ese swap es lo que llevó por primera vez la versión .NET 10 a producción en Orders, reciclando la última capacidad que aún corría la versión anterior. Por separado, el mismo día hubo también dos despliegues directos a producción (14:02 y 16:10 ART) — su relación exacta con el swap (si el swap terminó promoviendo la build de anoche por encima de estos dos despliegues del día, dado que el swap intercambia qué slot lleva la etiqueta de "producción") no está completamente reconciliada todavía. Lo que sí está confirmado en vivo, ahora mismo, es que Orders-PRO corre .NET 10 (`linuxFxVersion: DOTNETCORE|10.0`).

Esto también aclara el alcance real: la causa raíz confirmada explica el caso en vivo detectado hoy y cualquier caso nuevo desde que la versión .NET 10 quedó en producción, pero no explica las 12 órdenes bloqueadas históricas (todas anteriores a hoy, corriendo sobre la versión anterior) — su causa queda nuevamente abierta y sin identificar, y requiere una investigación separada.

Sobre el mecanismo de la falla en sí: no es que el runtime de .NET 10 cambie cómo se resuelve esta zona horaria — confirmamos que el mismo problema es reproducible en .NET 8 según un issue conocido del repositorio `dotnet/runtime`. La hipótesis es que la imagen base de contenedor que Azure App Service usa para .NET 10 ya no incluye el alias heredado de zona horaria que la imagen anterior sí tenía.

Ya está desplegada la corrección de código correspondiente (reemplazar el ID de Windows por el ID IANA, y agregar una entrada explícita para Perú), en SmartFran.Cloud; la misma ya fue desplegada.

Como hallazgo secundario relacionado: se encontró el mismo patrón de defecto, más extendido, en `Sales/TimeZoneCountries.cs` (usa IDs de Windows para las cuatro entradas de su diccionario, no solo en el respaldo) — hoy no genera impacto porque Sales corre sobre Windows, pero quedaría expuesto de la misma forma si Sales migra a Linux en el futuro.

**Cronología**

- **2026-09-04 al 09-14:** ocurren las 12 órdenes bloqueadas históricas, todas sobre la versión previa del código — causa aún sin identificar, sin relación confirmada con lo siguiente.
- **2026-09-07, 10:19 ART:** merge del código de migración .NET 8 → .NET 10 (commit `c7fa45721`) — merge del código únicamente, no despliegue.
- **2026-09-07 al 09-16:** el pipeline de despliegue se actualiza en cada ambiente de forma escalonada — DEV (07-sep), TEST (08-sep), STG (11-sep), PRO (16-sep 17:16 ART) — sin desplegar nada todavía en producción.
- **2026-09-16, 18:03 ART:** última build desplegada al slot de staging (`stg2`) de Orders.
- **2026-09-17, ~06:00 ART:** Swap stg2 -> prod.
- **2026-09-17, 14:02 ART:** Hotfix en producción en Orders.
- **2026-09-17, ~15:33 ART:** se captura en vivo la excepción real (`TimeZoneNotFoundException`) para una sucursal de Perú — cae entre el despliegue de las 14:02 y el swap de las 16:13, consistente con una falla parcial/intermitente en esa ventana, antes de volverse total.
- **2026-09-17, 16:10 ART:** segundo despliegue a slot stg en Orders (Fix Perú). Se realizan pruebas con el equipo.
- **2026-09-17, 16:12 a 16:15 ART:** Gastón Ávila ejecuta el swap del slot `stg2` a producción — confirmado en el log de actividad de Azure, con su verificación previa de diferencias entre slots y calentamiento posterior. Desde este momento la versión .NET 10 queda confirmada nuevamente en producción y toda orden nueva de Perú comienza a llegar.

Quedo a disposición para ampliar cualquier punto. El seguimiento completo de este caso está en el ticket [GITIN-2068](https://smartit-ar.atlassian.net/browse/GITIN-2068).

Saludos,
Dante Paniagua
