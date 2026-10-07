# Eventos — 20260914_gitin2034-timetaken-elapsedms-promotion

## 2026-09-14 — Apertura del ticket y verificación de la conf en vivo

He recibido el pedido de promover `TimeTaken`/`ElapsedMilliseconds` en `AppServiceHTTPLogs` y en `event_original.Properties.ElapsedMilliseconds`, bajo GITIN-2034. He verificado primero si esto ya estaba resuelto por GITIN-1940, dado que ese ticket promovió exactamente estos mismos campos y quedó verificado en vivo el 2026-08-26.

**Comando:** C1 — Descarga de la conf en vivo de Logstash vía SSH
**Resultado:**
El bloque de GITIN-1940 sigue desplegado sin cambios, con la misma lógica ya verificada anteriormente.

He confirmado que no se trata de una regresión en la configuración de Logstash — la lógica sigue intacta.

## 2026-09-14 — Confirmación de que la rama AppServiceHTTPLogs funciona en otras apps

**Comando:** C2 — Búsqueda Graylog `category:AppServiceHTTPLogs`, muestras de Admin-PRO/Orders-PRO
**Resultado:**
5.200 coincidencias en 1h, los 5 campos promovidos presentes y correctos en las muestras.

He confirmado que la rama `AppServiceHTTPLogs` funciona correctamente en otras apps, acotando el problema a algo específico de Sales-PRO.

## 2026-09-14 — Descarte de relación con las fallas de indexación

**Comando:** C3 — `GET /api/system/indexer/failures`
**Resultado:**
64.866 fallas totales, todas `mapper_parsing_exception` sobre un campo `time` no relacionado con `ElapsedMilliseconds`.

He descartado que este hallazgo explique el gap puntual que estoy investigando, y lo he dejado marcado como un hallazgo separado para seguimiento aparte.

## 2026-09-14 — Confirmación de la causa raíz real

**Comando:** C4 — Búsqueda Graylog por el `_id` específico de un mensaje sin los campos promovidos
**Resultado:**
Ninguno de los 5 campos (`Method`/`Path`/`StatusCode`/`ElapsedMilliseconds`/`ClientIP`) presente en el mensaje; `properties` llega como Hash vivo en lugar de String pre-stringificado, forma no contemplada por el guard original.

He confirmado la causa raíz exacta trazando el pipeline línea por línea, y he preparado un parche que acepta ambas formas del campo `properties`.

## 2026-09-14 — Intento de despliegue #1: falla y reversión

**Comando:** D3/D4 — Aplicación del parche y validación de sintaxis
**Resultado:**
`logstash -t` reportó un error de parsing en la línea del nuevo comentario; un apóstrofe dentro del bloque `code => '...'` cerró la cadena de forma prematura.

He revertido de inmediato desde el backup tomado antes de aplicar el parche, y he confirmado con `logstash -t` que la conf volvió al estado previo válido. Logstash nunca llegó a reiniciarse con la versión rota, por lo que no hubo impacto en el servicio.

## 2026-09-14 — Corrección del parche y verificación local

**Resultado:**
Reescritura del comentario sin apóstrofes, confirmada mediante un escaneo de balance de comillas y una validación de sintaxis Ruby local (`ruby -c`), ambas limpias.

He regenerado el parche y lo he vuelto a validar localmente antes de reintentar el despliegue.

## 2026-09-14 — Intento de despliegue #2: éxito

**Comando:** D3b-D6 — Aplicación del parche corregido, validación de sintaxis, reinicio y verificación de estado
**Resultado:**
`logstash -t` → Configuration OK. Reinicio limpio, receptores de Event Hub abiertos correctamente en ambas particiones, sin errores.

He confirmado el despliegue exitoso del parche corregido.

## 2026-09-14 — Verificación en tráfico real

**Comando:** V1 — Búsqueda Graylog post-despliegue sobre Sales-PRO
**Resultado:**
68 coincidencias en 5 minutos, los 5 campos promovidos presentes y correctos en las 10 muestras revisadas.

He confirmado en tráfico real que la corrección funciona como se esperaba, y he dejado registrado que la muestra también reforzó, de forma incidental, el hallazgo de `Shift/GetPaginatedForReportByFilterAsync` como endpoint lento del ticket `20260913_pos-net-http-timeout`.

## 2026-09-14 — Validación completa contra la conf en vivo y actualización del inventario de campos

**Comando:** Descarga fresca de la conf en vivo, comparación byte a byte contra la versión desplegada
**Resultado:**
Sin diferencias — la conf en vivo coincide exactamente con lo desplegado, sin drift.

He confirmado que el parche sigue aplicado de forma estable, sin cambios posteriores no documentados.

**Comando:** Chequeo de existencia (`_exists_`) contra los 23 campos trackeados en `docs/graylog-log-fields.md`, ventana de 24h
**Resultado:**
Todos los campos "siempre presentes" y los 5 campos de GITIN-1940/2034 confirmados en vivo a escala (cientos de miles a millones de hits). Único hallazgo real: `Category` ya no está en 0 — 638 hits — contradiciendo la afirmación vigente del documento ("no observado en vivo").

He actualizado `docs/graylog-log-fields.md` con el mecanismo completo del bug de GITIN-2034, la corrección de `Category`, y el gap remanente en `Service:"Sales"` — todo verificado contra tráfico real en lugar de asumido a partir del código o de la documentación previa.
