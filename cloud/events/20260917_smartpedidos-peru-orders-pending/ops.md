# GITIN-2068 — Órdenes de sucursales de Perú bloqueadas en estado Pendiente

**Tags:** `SmartCloud`, `AWS`, `PROD`, `SRE`

## Resumen

SmartCloud no confirmaba la recepción de un subconjunto de órdenes provenientes de SmartPedidos para sucursales de Perú, que quedaban indefinidamente en estado "Pendiente" (o sin estado persistido) del lado de SmartPedidos, sin llegar nunca a procesarse en la API de Orders de SmartCloud. El problema era intermitente y de bajo volumen (no afectaba la totalidad de las órdenes de Perú), pero reproducible. Se detectó el 2026-09-17 a partir de un reporte de que "las órdenes de Perú quedan pendientes". **La causa raíz fue corregida y desplegada a producción el mismo día** (~16:11 ART); persiste sin explicación el backlog de 12 órdenes bloqueadas anteriores al despliegue del defecto en producción (H3b), que requiere una investigación separada.

## Tabla resumen

| Campo | Valor |
|---|---|
| Ticket Jira | [GITIN-2068](https://smartit-ar.atlassian.net/browse/GITIN-2068) |
| ID alerta | N/A — reportado por usuario, no por alerta automática |
| Sistema | SmartFran Cloud — Orders API (`SmartFran-Cloud-Orders-PRO`) |
| Severidad | Alta |
| Detectado | 2026-09-17 |
| Resuelto | 2026-09-17, ~16:11 ART (causa raíz confirmada en vivo) |
| Responsable | Dante Paniagua (SRE) |

## Causa raíz

`MessageProcessor.PollOnceAsync` (Orders API) consume directamente, vía AWS SDK, la cola SQS FIFO propia de cada sucursal donde SmartPedidos publica las órdenes nuevas. Para órdenes del tenant Grido, el procesamiento pasa por `ApplyTimeZones`/`SetTimeZones` (`TimeZoneCountries.cs`), que solo reconoce explícitamente 4 países (Argentina, Chile, Uruguay, Paraguay); para cualquier otro país — incluido Perú — cae a una rama de respaldo que intenta resolver el ID de zona horaria de Windows `"Argentina Standard Time"` en lugar de un ID IANA. En el contenedor Linux donde corre la Orders API, esa resolución falla con `System.TimeZoneNotFoundException`, no manejada, que se propaga hasta el bloque `catch` genérico de `PollOnceAsync`. Ese bloque no elimina el mensaje de la cola SQS, por lo que la orden se reintenta indefinidamente hasta que expira silenciosamente al cumplirse el período de retención de la cola (3 días) — sin llegar nunca a la Dead Letter Queue (el umbral de reintentos configurado, 1000, no llega a alcanzarse en ese plazo) y sin que SmartPedidos reciba jamás una confirmación. Esto último es lo que se observa como la orden "quedándose en Pendiente".

## Hallazgos

| # | Hallazgo | Riesgo |
|---|---|---|
| H1 | `TimeZoneCountries.GetTimeZone` usa un ID de zona horaria de Windows (`"Argentina Standard Time"`) en su rama de respaldo, en lugar de un ID IANA — falla en el contenedor Linux de producción para cualquier país no listado explícitamente, incluido Perú. | Alto |
| H2 | La excepción no manejada resultante dentro de `ProcessGridoOrderAsync` deja el mensaje SQS sin eliminar; se reintenta indefinidamente hasta expirar por `MessageRetentionPeriod` (3 días) sin pasar nunca por la Dead Letter Queue ni notificar a SmartPedidos. | Alto |
| H3 | **Confirmado con log de actividad completo de Azure:** Gastón Ávila ejecutó un swap de slot (`stg2` → producción) a las **06:08-06:11 ART del 17-sep** — el momento real en que `.NET 10` quedó en producción por primera vez, promoviendo la build que esperaba en `stg2` desde la noche anterior. Esto hace coherente toda la cronología: producción ya corría .NET 10 desde las 06:11 ART, por lo que el crash en vivo detectado a las ~15:33 ART (9.5 horas después) es consistente, no un caso aislado. Un despliegue directo adicional (14:02 ART, hotfix no relacionado) y un segundo swap (16:12-16:15 ART, coincidente con el despliegue de la corrección de Perú) ocurrieron más tarde el mismo día, ya sobre base .NET 10. Por separado: la falla de resolución en sí (`FindSystemTimeZoneById` no resuelve `America/Buenos_Aires` en Linux) es un problema conocido y preexistente en .NET, ya reproducible en .NET 8 (ver [dotnet/runtime#103864](https://github.com/dotnet/runtime/issues/103864)) — no es una regresión del runtime .NET 10 en sí. **Ninguna de las 12 órdenes bloqueadas históricas (4 al 14-sep) queda explicada por este mecanismo**, ya que el código no estaba en producción antes del 17-sep. | Alto |
| H3b | **Nuevo, sin confirmar:** dado que la migración a .NET 10 recién se desplegó hoy, las 12 órdenes bloqueadas históricas (4 al 14-sep, corriendo sobre la versión .NET 8 previa) tienen una causa distinta y todavía sin identificar. Pendiente de investigación. | Medio |
| H4 | Verificado contra datos reales de SmartPedidos (MongoDB): 12 órdenes de las 35 sucursales de Perú permanecen indefinidamente en estado `PENDING` o sin campo `state`, con antigüedad de entre 2.8 y 13.7 días — bajo volumen relativo (349 órdenes/24h en esas sucursales), pero activo y reproducible. Como referencia, sobre 2891 órdenes de Perú que sí completaron su ciclo en los últimos 7 días, la mediana de tiempo hasta el último cambio de estado es de ~3.8 minutos (p95 ~20 min, p99 ~91 min; el caso normal más lento observado fue de ~47 horas). Las 12 órdenes bloqueadas superan ese p99 entre 4.000x y 20.000x. | Medio |
| H5 | Existe un segundo mecanismo de entrega (`/api/v1/Queue/Heartbeat`, pull HTTP) distinto del mecanismo SQS afectado. Aún no se determinó su relación exacta con el problema — si es el canal principal de entrega real a terminales POS, o uno secundario. No bloquea la corrección propuesta, pero es necesario aclararlo antes de cerrar el ticket. | Bajo |

## Recursos afectados

| Recurso | Detalle |
|---|---|
| `SmartFran-Cloud-Orders-PRO` (App Service) | Ejecuta el consumidor SQS afectado (`MessageProcessor.PollOnceAsync`) |
| 35 sucursales Grido — Perú | Lima y Callao, todas bajo el tenant Grido (`d3186bc6d7b2`) |
| Colas SQS por sucursal (`<branchId>PRD_PlatformMessages.fifo`) | Cuenta AWS `382381053403`, `us-east-1` |
| `TimeZoneCountries.cs` | `Source/Services/Orders/SmartFran.Cloud.Orders.Application/Models/Enum/` — repositorio SmartFran.Cloud |

### Órdenes confirmadas bloqueadas (12, al momento de esta investigación)

| ID orden | Sucursal | Plataforma | Estado | Antigüedad | Fecha |
|---|---|---|---|---|---|
| 5454662 | 5491 — Libertad | PediGrido | PENDING | 13.7 días | 2026-09-04 |
| 2260808327 | 5522 — Salamanca | Rappi | (sin estado) | 12.8 días | 2026-09-05 |
| 2270509683 | 5610 — Cercado Bertello | PedidosYa | PENDING | 11.6 días | 2026-09-06 |
| 2261092537 | 5522 — Salamanca | Rappi | (sin estado) | 10.7 días | 2026-09-07 |
| 2275382811 | 5647 — San Luis | PedidosYa | PENDING | 7.9 días | 2026-09-09 |
| 2276088336 | 5522 — Salamanca | PedidosYa | PENDING | 7.6 días | 2026-09-10 |
| 2261439040 | 5491 — Libertad | Rappi | (sin estado) | 6.9 días | 2026-09-10 |
| 2279219022 | 5440 — Jesús María, Huiracocha | PedidosYa | PENDING | 5.6 días | 2026-09-12 |
| 2279162694 | 5440 — Jesús María, Huiracocha | PedidosYa | PENDING | 5.6 días | 2026-09-12 |
| 5507077 | 5396 — Pueblo Libre I | PediGrido | PENDING | 4.8 días | 2026-09-12 |
| 2280301259 | 5481 — Club Naval | PedidosYa | PENDING | 4.8 días | 2026-09-12 |
| 2261933306 | 5435 — Callao, Bellavista San José | Rappi | (sin estado) | 2.8 días | 2026-09-14 |

Antigüedad calculada al momento de la extracción (2026-09-17, sesión de investigación) — no es en vivo. Las órdenes sin estado (Rappi) corresponden a un gap separado y de menor severidad (H de detalle en la investigación técnica), no necesariamente al mismo mecanismo de bloqueo que las que sí muestran `PENDING`.

## Comandos ejecutados

Ver `scripts.sh` para el detalle completo. Resumen:

| # | Comando / Script | Propósito |
|---|---|---|
| C1-C2 | Azure App Config `kv show` (organizations, OrderSQSVersion) | Confirmar configuración de tenants/versión SQS — falló por falta de rol RBAC |
| C3-C4 | Azure identidad/recurso App Config | Aislar la falla de C1-C2 al plano de datos específicamente |
| C5-C7 | Graylog — errores Orders, salud, muestra 1h | Descartar falta de datos en Graylog antes de confiar en resultados "0" |
| C8 | Graylog — búsqueda de texto "Peru", 24h | Confirmar tráfico real de Perú bajo tenant Grido |
| C9 | Graylog — traza de orden puntual bloqueada (13 días) | Confirmar que la orden nunca aparece en los logs de Orders API |
| C10 | Export de logs en vivo de Azure (provisto por el usuario) | Confirmó la excepción real `TimeZoneNotFoundException` en producción |
| C11 | Verificación de repositorio (`git diff`/`git show`) | Confirmó que el fix aplica contra `main` (no solo `dev`) y fechó la migración .NET 8→10 |

## Acciones propuestas

1. ~~Aplicar la corrección de código en `TimeZoneCountries.cs`~~ — **Completado.** El equipo propietario del repositorio aplicó la corrección (commits `d5d87db50`/`86bab37f9`, "add peru zona horario") y la desplegó a producción (release "v02.45.02 fix timezone", commit `958dfa2`, 2026-09-17 ~16:09-16:11 ART). Confirmado por el usuario: las órdenes de Perú se procesan con normalidad desde ese despliegue.
2. Solicitar el rol RBAC "App Configuration Data Reader" sobre `smartfran-cloud-settings-pro` para poder confirmar si Perú requiere algún ajuste adicional de tenant/versión SQS (bloqueado actualmente).
3. Definir si las 12 órdenes ya perdidas (H4) requieren recuperación manual o reingreso por parte de las sucursales afectadas, dado que el mensaje SQS correspondiente ya expiró sin posibilidad de reproceso automático.
4. Investigar el origen de las 12 órdenes bloqueadas históricas (H3b) — corrieron enteramente sobre la versión .NET 8 previa (el despliegue de .NET 10 fue recién hoy, 2026-09-17), por lo que ninguna queda explicada por la causa raíz identificada en H1/H2. Requiere una investigación separada.
5. Aclarar la relación entre el mecanismo SQS (afectado) y el mecanismo de heartbeat/pull HTTP (H5) para confirmar cuál es el camino de entrega real de órdenes a las terminales POS en producción.

## Hallazgos secundarios

- **Credenciales de AWS en texto plano:** se encontró un par de credenciales de AWS (access key + secret) committeado en texto plano en el repositorio de `concentrador-service`, y las mismas credenciales reemitidas dentro de cada JWT de login de sucursal — distribuidas activamente a dispositivos POS en operación normal. Requiere ticket de seguridad separado; no se registró el valor de la credencial en ningún artefacto de este ticket.
- **Defecto duplicado, latente, en Sales:** `Source/Services/Sales/SmartFran.Cloud.Sales.Application/Models/Enums/TimeZoneCountries.cs` contiene una versión más amplia del mismo defecto — usa IDs de Windows (`"Argentina Standard Time"`, `"Chile Standard Time"`, `"Uruguay Standard Time"`, `"Paraguay Standard Time"`) para **las cuatro** entradas de su diccionario, no solo en el respaldo como en Orders. Hoy no genera ningún problema porque Sales corre sobre Windows (confirmado por la convención de nombres de sus workflows de GitHub Actions, sufijo `_win`), donde esos IDs resuelven de forma nativa sin traducción a IANA. Queda como riesgo latente: si Sales migra a Linux en el futuro — el mismo tipo de migración que gatilló este ticket en Orders — este código fallaría de inmediato para Argentina, Chile, Uruguay y Paraguay directamente, no solo para un país no listado como Perú. Se revisó el resto del repositorio (`StockService.cs`, `FranchisorOrderService.cs`, `RegisterPaymentDialog.razor.cs`, el helper compartido `TimeZoneOperation.cs`) y todos usan un patrón distinto y seguro, basado en un campo `Zonename` ya en formato IANA — no se encontró ningún otro caso del mismo defecto.
- **Pipelines de PRO — corrección:** el hallazgo original (pipelines de PRO desactualizados, fleet-wide) se verificó contra la rama equivocada (`dev` local en lugar de `main`). Contra `origin/main` real: el commit `8c19f850a` ("Cambio NET10 en YML PRO", 2026-09-16 17:16) ya corrigió los 11 workflows de PRO a `DOTNET_CORE_VERSION: 10.0.x` el día anterior al despliegue real. Esto explica el desfasaje de 9 días entre el merge del código (7-sep) y el despliegue efectivo (17-sep): el pipeline de PRO no podía building/desplegar de forma confiable el código net10.0 hasta esa corrección. No se requiere ticket adicional para este punto — ya está resuelto.
- **Rollback evaluado y descartado como remediación:** se evaluó revertir la migración .NET 8→10 en Orders como alternativa a corregir `TimeZoneCountries.cs`. Descartado: (1) el commit de migración retargeteó en el mismo cambio las librerías compartidas `Provider.*` (`Logger.Core`, `Logging.AspNetCore`, `Messaging.AzureBus`, etc.) de las que dependen todos los servicios — revertir Orders sola probablemente ni compila contra esas librerías ya en `net10.0`, y revertir las librerías compartidas afecta en cascada a Business, Catalog, Person, Platform, Pos, Sales y las Function Apps, ya redesplegados sobre `net10.0`; (2) 57 commits reales de funcionalidad (no solo infraestructura) se mergearon a `main` desde el 7-sep, con riesgo de revertirlos o romperlos sin relación con este defecto. La corrección puntual de código ya redactada sigue siendo la vía recomendada.
