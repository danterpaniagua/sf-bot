# Eventos — 20260917_smartpedidos-peru-orders-pending

## 2026-09-17 15:07 — Apertura de la investigación GITIN-2068

He abierto la investigación para GITIN-2068 a partir del reporte de que SmartCloud no está recibiendo órdenes de SmartPedidos y que las órdenes de Perú específicamente quedan en estado "Pendiente". He documentado el contexto de arquitectura conocido (platforms-service publica en AWS SQS, SmartCloud enruta hacia los POS) y he dejado como pregunta abierta el mecanismo exacto de puente entre ambos sistemas, que no estaba documentado en ningún lugar del repositorio.

## 2026-09-17 15:10 — Identificación del mecanismo de puente SmartPedidos → SmartCloud

He revisado el código fuente de `SmartFran.Cloud` (repositorio local, actualizado a `origin/dev`) y he confirmado que `MessageProcessor.PollOnceAsync` (Orders API) consume directamente, vía AWS SDK, la cola SQS FIFO por sucursal que publica `platforms-service`. He identificado dos posibles brechas relacionadas con tenant/país en el mismo código (`OrderSQSVersionSettings` y `TimeZoneCountries`), como hipótesis a confirmar, no como causa confirmada en ese momento.

## 2026-09-17 15:14 — Verificación en Graylog: errores del servicio Orders y alcance real de Perú

**Comando:** C5-C8 — consultas Graylog (errores Orders 24h, salud del sistema, muestra 1h, texto libre "Peru")
**Resultado:** ver `data/graylog_orders_errors_24h.json`, `data/graylog_system_health.json`, `data/graylog_orders_any_1h.json`, `data/graylog_peru_freetext_24h.json`

La consulta de errores del servicio Orders en las últimas 24h no arrojó resultados, pero antes de tomarlo como "sin errores" he verificado que Graylog está recibiendo datos del servicio Orders con normalidad, para descartar un falso vacío. La búsqueda de texto libre "Peru" sí ha devuelto 22 resultados reales, 20 del servicio Orders, correspondientes a un franquiciado real de Grido en Perú bajo el tenant ya onboardeado de Grido — esto ha debilitado la hipótesis de un tenant sin registrar como causa.

## 2026-09-17 15:16 — Intento de verificación de Azure App Configuration (bloqueado por RBAC)

**Comando:** C1-C4 — `az appconfig kv show` (organizations, OrderSQSVersion), `az account show`, `az appconfig show`
**Resultado:** C1 y C2 han fallado con error de deserialización (403 sin cuerpo); C3 y C4 han confirmado identidad/suscripción correctos y que el recurso es alcanzable a nivel de control plane.

He aislado la falla de C1/C2 al plano de datos de App Configuration específicamente — la identidad (`dantep@smartfran.com`) y la suscripción son correctas, pero falta el rol RBAC "App Configuration Data Reader" sobre `smartfran-cloud-settings-pro`. Queda pendiente solicitar ese acceso para confirmar la configuración real de tenants/versión SQS.

## 2026-09-17 15:36 — Trazabilidad de una orden específica bloqueada

**Comando:** C9 — Graylog, traza de la orden 2270509683 (sucursal 5610) en su ventana completa de 13 días
**Resultado:** ver `data/graylog_order_2270509683_trace.json` — 0 resultados

He confirmado que esta orden puntual, identificada del lado de SmartPedidos como bloqueada hace 11.6 días, no aparece en ningún log de la API de Orders en toda su vida útil — ni éxito ni error. Esto ha abierto la pregunta de si el mensaje efectivamente llegó a ser consumido por el lado de SmartCloud.

## 2026-09-17 15:50 — Causa raíz confirmada a partir de un log en vivo

A partir de un export real y en vivo de logs de Azure AppServiceConsoleLogs, he confirmado la causa raíz: una excepción `System.TimeZoneNotFoundException` no manejada en `MessageProcessor.SetTimeZones`, actual y en curso al momento de la revisión, para una sucursal de Perú (5454). La excepción ocurre porque `TimeZoneCountries.GetTimeZone` cae a un ID de zona horaria de Windows (`"Argentina Standard Time"`) para cualquier país no listado explícitamente — Perú incluido — y ese ID no resuelve en el contenedor Linux de producción. Esto deja el mensaje SQS correspondiente sin eliminar, reintentándose indefinidamente hasta expirar en silencio.

En el mismo log he detectado un hallazgo de seguridad separado: las credenciales de AWS ya conocidas como comprometidas en el repositorio de `concentrador-service` también se reemiten en cada JWT de login de sucursal. No he incluido el valor de la credencial en ningún artefacto de este ticket.

## 2026-09-17 16:05 — Redacción y validación del fix propuesto

He redactado el diff correctivo para `TimeZoneCountries.cs` (reemplazo del ID de Windows por el ID IANA correspondiente, más una entrada explícita para Perú) y lo he validado con una aplicación de prueba (`patch --dry-run`) contra el clon local de solo lectura, sin modificarlo. El diff queda disponible en `gitin2068-timezone-fix.patch` para que el equipo propietario del repositorio `SmartFran.Cloud` lo aplique.

## 2026-09-17 16:12 — Confirmación contra la rama `main` (PRO)

**Comando:** C11 — `git diff origin/main origin/dev --stat` sobre los archivos involucrados
**Resultado:** sin diferencias — ambos archivos son idénticos entre `origin/dev` (37470e4f) y `origin/main` (faca32f1)

He confirmado que el fix propuesto aplica igual contra lo que realmente está desplegado en producción (`main`), no solo contra `dev`.

## 2026-09-17 16:25 — Correlación con la migración de framework .NET 8 → .NET 10

**Comando:** C11 — `git show c7fa45721 --stat`, revisión de `.csproj` y workflows de GitHub Actions
**Resultado:** commit `c7fa45721` ("Migracion Framework", GSFC-998, 2026-09-07) confirmado

He identificado que la migración fleet-wide de .NET 8 a .NET 10 del 2026-09-07 es la causa más probable de que el problema haya empezado a manifestarse ahora — coincide temporalmente con 8 de las 12 órdenes bloqueadas confirmadas del lado de SmartPedidos. He descartado un cambio de versión del SDK de AWS SQS como factor, dado que no fue tocado en el mismo commit. He encontrado además, como hallazgo separado, que todos los pipelines de PRO de GitHub Actions revisados para SmartFran Cloud siguen fijando versiones de .NET previas a la migración, mientras el código en `main` ya apunta a `net10.0` — no bloqueante hoy, pero inconsistente.

## 2026-09-17 16:40 — Precisión de la causa "por qué ahora", verificada externamente

He verificado que la falla de resolución de zona horaria en sí (`America/Buenos_Aires` no encontrado en Linux vía el ID de Windows) es un problema conocido y preexistente de .NET, ya reproducible en .NET 8, no una regresión introducida por el runtime de .NET 10. He corregido la hipótesis en la investigación: lo más probable es que la imagen base del contenedor administrado por Azure haya cambiado junto con la migración de framework, y que la nueva imagen no incluya el symlink de compatibilidad heredado que la anterior sí tenía.

## 2026-09-17 16:50 — Redacción del ticket GITIN-2068

He redactado el cuerpo del ticket GITIN-2068 (`ops.md`) con el resumen, causa raíz, hallazgos, recursos afectados, comandos ejecutados y acciones propuestas, incluyendo los dos hallazgos secundarios de seguridad y de higiene de CI/CD. El ticket queda con el fix aún sin aplicar, pendiente de que el equipo propietario del repositorio lo revise y despliegue.
