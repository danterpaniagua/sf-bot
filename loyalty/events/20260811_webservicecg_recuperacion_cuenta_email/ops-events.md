# Eventos — 20260811_webservicecg_recuperacion_cuenta_email

## 2026-08-11 — Apertura de investigación (GITIN-1816)

Recibí el reporte de GITIN-1816: las solicitudes de recupero de cuenta ("Account Recovering") a través de WebServiceCG no están enviando el email al socio. Confirmé que WebServiceCG pertenece al proyecto SmartLoyalty, alojado en `SFCG-WSCG-01`.

## 2026-08-11 — Trazado del flujo de código

Rastreé el flujo completo en el clon local de fuentes (`loyalty/repo/dev-src-sol-smartloyalty/`): `AccountController.AccountRecovery` invoca `CustomerApplicationService.ExecuteRecovery`, que llama a `SendMailConfirmation` pero ignora su resultado booleano y siempre devuelve éxito al llamador. `SendMailConfirmation` captura cualquier excepción del envío (ya sea por lectura de plantillas HTML o por el envío SMTP en sí a través de `IMailSender`) y la persiste en `Sml.CustomerAccountRecovery.SendEmailError`, sin relanzarla. Esto significa que la API siempre responde 200 "¡Listo!..." independientemente de si el email se envió.

Guardé las consultas de diagnóstico en `scripts.sql` (Q1: solicitudes recientes por canal BOT; Q2: filtradas a las que tienen `SendEmailError` no nulo) para confirmar la causa real contra la base `SmartFran.Solution.SmartLoyalty`.

## 2026-08-11 — Caso puntual reportado

Recibí el caso concreto reportado en GITIN-1816: `Sofilualbornoz@icloud.com`, solicitud alrededor de `2026-08-10T02:08:20.58776+00:00`. Agregué Q3 a `scripts.sql`, acotada a ese email y a una ventana de ±2h sobre ese timestamp contra `Sml.CustomerAccountRecovery`.

## 2026-08-11 — Log de hMailServer del caso puntual

Recibí el log de hMailServer para el mensaje 5669021 (`info@clubgrido.com.ar` → `Sofilualbornoz@icloud.com`), que muestra el mensaje aceptado y reenviado a `smtp.sendgrid.net` a las `02:08:18.385` del 2026-08-10, con el hilo de entrega local completado a las `02:08:18.432`. Esto confirma que el relay local (hMailServer) entregó el mensaje a SendGrid, pero no confirma la entrega final a iCloud. Esto reorienta la investigación hacia un posible rechazo/descarte en SendGrid o en el filtrado de iCloud, en lugar del bug de código encontrado en `ExecuteRecovery` — pendiente de confirmar contra la fila real en `Sml.CustomerAccountRecovery` (Q3) y contra el log de actividad de SendGrid.

## 2026-08-11 — Confirmación por base de datos: sin excepción a nivel de aplicación

Ejecuté Q3 contra `SmartFran.Solution.SmartLoyalty` y obtuve la fila real (Id 746836) para el caso de `Sofilualbornoz@icloud.com`: `SendEmailError` es NULL y `SendEmailAttemptedAt` (02:08:18.390) coincide con el timestamp de aceptación en el log de hMailServer (02:08:18.385). Con esto descarté el bug de `ExecuteRecovery`/`SendMailConfirmation` como causa de este caso puntual — el envío a nivel de aplicación no lanzó excepción. La causa queda acotada a algo posterior al relay local: rechazo/descarte en SendGrid o filtrado en iCloud, ninguno confirmado todavía.

## 2026-08-11 — Redacción de ticket en estado bloqueado

Redacté `ops.md` reflejando el estado actual: bloqueado, causa raíz no confirmada, pendiente de recopilar más ocurrencias para determinar si el problema está acotado al dominio `icloud.com` o es más amplio (SendGrid/relay). El hallazgo del bug de `ExecuteRecovery` se documentó como hallazgo secundario, no como causa raíz de este caso puntual.

## 2026-08-11 — Identificación del relay de correo y mejora de observabilidad

Identifiqué las dos VM de relay hMailServer (`192.168.50.161` y `192.168.50.162`, tag `SF-SMTPRL` Cardinality 01/02) que alimentan Graylog vía NXLog. En paralelo (trabajo de mejora de observabilidad, no específico de este caso) agregué extracción de `$MessageId` y `$Thread` en la configuración de NXLog y eliminé un `drop()` que descartaba toda línea de "delivery thread completed", para poder correlacionar futuras ocurrencias por ID de mensaje una vez desplegado. Marqué el filtrado de dominio de iCloud como teoría líder (no confirmada) dado que el único caso confirmado hasta ahora es `@icloud.com` — pendiente de más ocurrencias en otros dominios para contrastar.

## 2026-08-11 — Reversión de la mejora de observabilidad en NXLog

El intento de agregar `$MessageId`/`$Thread` en la configuración de NXLog de ambas VM de relay (`.161`/`.162`) provocó que ambas dejaran de enviar datos a Graylog por completo (sin errores visibles en `nxlog.log`, corte silencioso de decenas de minutos). No llegué a aislar la causa exacta antes de revertir. Restauré la configuración original en ambas VM y confirmé que el envío se reanudó. Como consecuencia, la capacidad de correlación por `MessageId` que iba a usarse para contrastar el caso de `icloud.com` contra otros dominios **no existe todavía** — este ticket sigue bloqueado en ese punto.

## 2026-08-12 — Causa raíz real identificada y capacidad de correlación restablecida

Identifiqué la causa real de los cortes de envío a Graylog de toda la noche: el contenedor de OpenSearch que sostiene esta instancia de Graylog se reinició (confirmado por sus logs, `StartedAt` 2026-08-12 01:24:54), y durante la recuperación posterior todos los índices del cluster (de un solo nodo) quedan momentáneamente no disponibles — esto explica por qué los mensajes no llegaban sin ningún error visible del lado de NXLog, independientemente de la configuración desplegada. No fue causado por ninguno de los cambios de NXLog de esta noche. Encontré además, como hallazgo separado, que los índices `graylog_299` y `sp_platform__50` alcanzaron el límite de 1000 campos de mapeo de OpenSearch — pendiente de resolución, fuera del alcance de este ticket. Con la causa real identificada, volví a desplegar la extracción de `$MessageId` en ambas VM y confirmé que está funcionando en producción (mensajes con `MessageId` real en Graylog desde `.161` y `.162`). La capacidad de correlación por `MessageId` para contrastar `icloud.com` contra otros dominios ya está disponible.

## 2026-08-12 — Actualización de ticket

Actualicé `ops.md`: marqué como resuelto (H3) el bloqueador de diagnóstico en Graylog/NXLog — no la causa raíz del email no recibido, que sigue sin confirmar. Estado del ticket pasa de "Bloqueado" a "En progreso". Quedan pendientes: revisar el log de actividad de SendGrid (nunca se hizo) y recopilar más ocurrencias ahora que la correlación por `MessageId` está disponible.

## 2026-08-11 — El corte de envío a Graylog recurrió también con la configuración original

El envío desde ambas VM (`.161`/`.162`) volvió a detenerse por completo incluso ya revertida la configuración a la versión original — descarta que las ediciones de esa noche ($MessageId/$Thread/DNI) fueran la causa real, ya que el corte se repite sin ellas. La teoría líder actual es degradación de `im_file` por la acumulación de ~80 archivos `.log` históricos que matchea el wildcard (confirmado en `.162`), no algo específico del bloque `Exec`. En curso: mover los archivos históricos fuera del alcance del wildcard en ambas VM para probar esta teoría. Confirmé además el hostname de `.161` vía `$env:COMPUTERNAME`: `SFCG-SMTP-01`.
