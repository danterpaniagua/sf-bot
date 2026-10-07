# Eventos — 20260915_functionapp-onboarding

## 2026-09-15 (inicio de sesión) — Onboarding de 4 Function Apps vía Terraform

He agregado/actualizado recursos en Terraform para `SFC-FunctionAPP-Linux-Plan-PRO`: `SFC-CodeGenerator-PRO`, `SFC-ScheduledJobs-PRO`, `SFC-PosWasmRelay-PRO`, `SFC-TicketProcess-PRO` (renombrado desde `SFC-TicketProcessAsync-PRO` — el nombre viejo ya no resuelve en Azure) más diagnostic settings para los 4 slots `stg2` de cada app. He actualizado el recurso viejo `ticketprocessasync_pro_sfc` in-place, no lo he dejado colgando, porque una referencia a un nombre inexistente hubiera roto el `terraform plan` completo, no solo este onboarding.

`terraform apply` acotado a los 5 recursos nuevos: 5 added, 0 changed, 0 destroyed — sin sorpresas respecto al plan.

## 2026-09-15 — Verificación de entrega, primer intento fallido por casing

**Comando:** C4
**Resultado:**
`total_results: 0` para las 4 apps nuevas al buscar por `name:SFC-CodeGenerator-PRO` (mayúsculas/minúsculas tal cual el nombre de recurso Azure).

Antes de concluir que había un problema real, he verificado `FunctionExecutionCount` vía `az monitor metrics` (C2) — las 3 apps con más tráfico mostraron ejecuciones reales (343, 752 y 2 respectivamente), descartando "app inactiva". He encontrado la causa real: el campo `name` en Graylog queda indexado en **MAYÚSCULAS** (viene de `resourceId`, que Azure devuelve todo en mayúsculas). La query original usaba el casing exacto de Azure (mixto), lo que devolvía 0 resultados de forma silenciosa — un falso negativo de la query, no una falla de entrega. Repitiendo la búsqueda con `name:SFC-CODEGENERATOR-PRO` (mayúsculas) he confirmado tráfico real en las 4: CodeGenerator 210.666 msgs/24h, ScheduledJobs 114.596, PosWasmRelay 766.766, TicketProcess 236.

## 2026-09-15 — Verificación de schema de campos

He confirmado que las 4 apps devuelven el mismo set de 38 campos en Graylog, salvo `tags` (presente solo cuando `event_original` fue truncado por tamaño — no es una diferencia de schema real, confirmado revisando 10 mensajes consecutivos de TicketProcess sin ese campo, todos por debajo del umbral de truncado).

## 2026-09-15 — Separación de streams por app

**Comando:** C9, C10, C11
**Resultado:**
He creado un Index Set + Stream dedicado por app (mismo patrón ya usado para GITIN-1834: regla `field: name, type: 1` exact match, `remove_matches_from_default_stream: true`). He encontrado 2 quirks nuevos de la API de Graylog, no documentados antes: `POST /system/indices/index_sets` rechaza tanto `default` como `can_be_default` (ambos de solo lectura en el GET); y el wrapper `{"entity": {...}}` de `POST /streams` mapea `entity` directamente a `CreateStreamRequest`, sin anidar `"type"/"data"` — mi primer intento con esa estructura anidada falló con "Null title".

He verificado entrega end-to-end: CodeGenerator (325 msgs/60s en el stream nuevo, 0 en Default), ScheduledJobs (71/60s, 0 en Default), PosWasmRelay (1112/60s, 0 en Default — tardó ~1-2 min en propagar tras el resume, lo que inicialmente pareció fuga entre streams pero se resolvió solo). TicketProcess quedó con la regla verificada correcta pero sin tráfico en vivo para confirmar el corte — su job (`ProcessTicketsHourly`) no volvió a disparar durante la sesión. En cada paso he verificado que el tráfico de otras apps en Default no se viera afectado.

## 2026-09-15 — Promoción de campos de FunctionAppLogs en Logstash

`FunctionAppLogs` nunca tuvo promoción de campos: su `properties` llega como un string con repr de diccionario Python (comillas simples), no JSON, así que ningún guard `JSON.parse` existente lo reconocía. He relevado 2 shapes distintos de `properties.category` (`Host.Function.Console` con `message` anidado, y `Function.<nombre>`/`.User` con `message` plano) contra mensajes reales de las 4 apps.

**Comando:** C7
**Resultado:**
He escrito un parser Python-literal en Ruby puro (sin gems externas, ya que no hay forma de instalar dependencias nuevas en el JRuby de la VM desde esta sesión) y lo he probado contra 9 mensajes reales capturados **antes** de tocar el pipeline en vivo — he encontrado y corregido un bug real (`FunctionEventName` promovía el string `"0"`, un placeholder sin sentido en líneas `.User`) y he confirmado una mejora real (`AppLevel` ahora muestra `"Warning"` correctamente en vez del `"Informational"` incorrecto que mostraba antes para ese mismo mensaje).

He detectado una discrepancia de sincronización: la copia del repo no tenía el fix `GITIN-2034` (manejo de `properties` en dos shapes, wrapped vs. flat) ya presente en la config desplegada en la VM. He sincronizado el repo con la versión real desplegada antes de insertar el nuevo bloque, para no revertir ese fix al desplegar.

## 2026-09-15 — Despliegue a producción

**Comando:** C12, C13
**Resultado:**
He descargado la config real desde la VM (`/etc/logstash/conf.d/azure-eventhub-to-graylog.conf`, vía `sudo cat` por SSH) en vez de asumir que la copia del repo era la autoritativa — la copia del repo tiene las connection strings redactadas (`"NO"`), desplegarla tal cual hubiera roto la conexión a Event Hub. He insertado el nuevo bloque sobre la copia real (con secretos + fix GITIN-2034 intactos).

He verificado la transferencia por hash (`sha256sum`) antes de instalar — este archivo tiene historial de 3 corrupciones de transferencia por 3 mecanismos distintos en una sesión previa. `logstash -t` pasó limpio.

## 2026-09-15 — Restart y confirmación de estabilidad

**Comando:** C14
**Resultado:**
Tras `systemctl restart`, `NRestarts=0` a los 10s y logs confirmando reconexión real a Event Hub (partition receiver abierto). He reconfirmado `NRestarts=0` varios minutos después del restart, no solo a los 10s iniciales — sin crash loop. Doy el despliegue del pipeline actualizado por estable.

## 2026-09-15 — Confirmación en vivo de la promoción de campos

Primer mensaje real de producción con el pipeline actualizado, capturado desde el stream dedicado de `SFC-PosWasmRelay-PRO`: `message` con contenido real (`"Executed Functions.IngestLogs (Succeeded, Id=..., Duration=2ms)"` en vez del placeholder genérico), más `AppLevel`, `FunctionName`, `FunctionInvocationId` y `FunctionEventName` promovidos correctamente. Coincide exactamente con lo esperado según las pruebas standalone previas al despliegue — primera confirmación en producción real, no solo en el harness de prueba.

## 2026-09-15 — Verificación posterior: config en vivo + promoción de campos en las 4 apps

**Comando:** C15, C16
**Resultado:**
He descargado nuevamente la config real desde la VM (mismo comando que la sesión de despliegue) y la he comparado contra la copia del repo — el diff crudo mostró el archivo completo como distinto por un artefacto de línea (CRLF introducido por el `-t` de SSH, mismo mecanismo de corrupción de transferencia ya documentado, esta vez sin afectar ningún despliegue real ya que solo lo he usado para lectura). Normalizado a LF, el diff real quedó en 2 líneas — únicamente `event_hub_connections`/`storage_connection`, redactadas en el repo como `"NO"` por diseño. El bloque de parseo de `FunctionAppLogs` documentado coincide exactamente entre repo y VM.

**Incidente de manejo de secretos, corregido en el momento:** la descarga cruda de la config en vivo quedó escrita en 2 archivos dentro de `data/` con el `SharedAccessKey` de Event Hub y el `AccountKey` de Storage en texto plano (ninguno de los dos estaba trackeado por git todavía). He redactado ambos valores in-place inmediatamente al detectarlo, junto con los 2 archivos de diff derivados que también los contenían — he confirmado los 4 archivos limpios (`grep` sin hits) antes de continuar. Ningún archivo llegó a estar staged. Ambos secretos también quedaron visibles brevemente en la salida de una herramienta durante esta sesión de verificación — a evaluar si amerita rotación, no decidido acá.

**Comando:** C17, C18
**Resultado:**
He validado los 4 streams dedicados con datos reales (`category:"FunctionAppLogs" AND name:"<APP>"`, 6h, 3 mensajes c/u): `FunctionName`/`FunctionInvocationId`/`AppLevel`/`message` promovidos correctamente en las 4. **TicketProcess confirmado en vivo** (`ProcessTicketsHourly`, `Service: SmartFran.Cloud.Functions.Sales.TicketProcessAsync`) — cierra el pendiente que había quedado abierto por falta de una corrida durante la sesión de despliegue. `SFC-CodeGenerator-PRO` confirma además que la versión desplegada es `LiteEditionV2` (`Service` field), no `LiteEdition` — ambigüedad que quedaba abierta solo por lectura de código. `SFC-PosWasmRelay-PRO` confirma que cada mensaje de log relayado incluye el detalle real de la llamada HTTP original del cliente POS (ej. `"HTTP 'POST' '/api/v1/Queue/Heartbeat' responded 200 in 403.2 ms"`), no solo metadata del relay en sí. `SFC-ScheduledJobs-PRO` confirma que `FunctionName` distingue de forma limpia `RegisterBusinessLog` de sus otros jobs (`Functions.RegisterBusinessLog` + `FunctionEventName:"FunctionCompleted"` identifica una ejecución completa) — habilita separar su tráfico HTTP real de sus jobs internos por timer, algo que no era posible antes de este onboarding.

## 2026-09-15 — Intento de aplicar FunctionName a una ventana histórica anterior

Un ticket relacionado (`cloud/events/20260915_gitin2042-waf-cost-estimate/`, GITIN-2042) ha intentado reutilizar `FunctionName` para separar el tráfico HTTP real de `SFC-ScheduledJobs-PRO` sobre una ventana de medición anterior al despliegue de este mismo día (2026-09-11 a 2026-09-15). No ha funcionado: he confirmado 600.837 mensajes reales de `FunctionAppLogs` para ScheduledJobs en esa ventana, pero 0 con `FunctionName` poblado — la promoción de campos no es retroactiva. La capacidad nueva solo sirve hacia adelante desde el despliegue de hoy.

## 2026-09-15 — Migración del evento a este repositorio

He migrado este evento completo (investigation.md, ops.md, ops-events.md, scripts.sh, data/) desde un repositorio separado a `cloud/events/20260915_functionapp-onboarding/` de este monorepo, convirtiendo la voz de los archivos al estándar de este proyecto (primera persona, pretérito perfecto compuesto) y agregando `investigation.md`, que no existía en el origen. He vuelto a verificar, en el destino, que ningún archivo copiado contuviera las credenciales reales redactadas en la sesión anterior — limpio.

## Pendientes

- `terraform apply` no acotado (`-target`) pendiente, para limpiar el diagnostic setting huérfano `ticketprocessasync_pro_sfc` (apunta al nombre viejo, ya retirado).
- Compartir (`Everyone`/`Viewer`) los 4 streams nuevos — no hecho esta sesión, sí hecho para el stream de DEV en GITIN-1794.
- Evaluar si el `SharedAccessKey`/`AccountKey` expuestos brevemente durante la verificación posterior ameritan rotación.
