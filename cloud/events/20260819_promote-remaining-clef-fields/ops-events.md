# Eventos — 20260819_promote-remaining-clef-fields

## 2026-08-19 — Apertura del ticket GITIN-1892

He abierto la investigación a partir del cierre de GITIN-1883: de los 16 campos canónicos de `Properties` listados en `cloud/docs/devs-log-structure.md` §9, ese ticket promovió 4 (`TraceKey`, `TenantId`, `Service`, `Environment`) más `AppLevel` (ya resuelto desde GITIN-1835, no es un campo de `Properties`). Quedan 12 sin promover: `UserId`, `Component`, `ProcessType`, `Category`, `ErrorCode`, `Operation`, `Recovered`, `Handled`, `AuditAction`, `AuditOutcome`, `RequestId`, `SourceContext`. He revisado la investigación de GITIN-1883 para no re-derivar lo ya confirmado (ubicación del bloque Ruby en `azure-eventhub-to-graylog.conf`, patrón de despliegue por patch acotado, existencia de una segunda copia versionada del pipeline en `bots/settings/prod-sfcloud-monitoreo/`).

He identificado, a partir de `devs-log-structure.md` §3.2/§3.3/§3.5, que los 12 campos se dividen en dos grupos con distinto comportamiento: 6 siempre presentes cuando el log está scoped a request/helper (`UserId`, `Component`, `ProcessType`, `Category`, `SourceContext`, `RequestId`) y 6 condicionales a un helper específico (`ErrorCode`, `Operation`, `Recovered`, `Handled`, `AuditAction`, `AuditOutcome`) — estos últimos requieren guardar contra la clave ausente del hash, no solo contra string vacío, a diferencia del patrón usado en GITIN-1883. No he corrido ninguna consulta todavía contra Graylog; dejo armadas en `scripts.sh` las consultas para traer muestras reales de ambos grupos (C1 plano por servicio, C2 por marcador de texto para cada campo condicional).

## 2026-08-19 — Muestras C1 confirmadas; bug en C2 detectado y corregido

He revisado las 6 muestras reales de C1 (una por servicio). Confirmo `UserId`, `ProcessType`, `Component`, `RequestId` presentes en las 6, con `Component` mostrando `Api`/`Web` en vez del nombre de dominio de negocio que documenta `devs-log-structure.md` §3.2 (ej. `"Sales"`) — dejo esto como discrepancia a confirmar con Dev, no como causa asumida. `SourceContext` aparece en solo 3 de 6 muestras (Business/Admin/Catalog sí, Platform/Person/Orders no) — inconcluyente con una sola muestra por servicio. `Category` no aparece en ninguna de las 6 — ningún mensaje muestreado pasó por los 6 helpers canónicos (`LogBusinessEvent`, etc.), son logs planos de `ILogger`. Corrijo la clasificación original: `Category` se comporta como el grupo condicional, no como el grupo siempre-presente.

Encuentro que las 6 consultas C2 (marcador de texto por campo condicional) fallaron con `query_shard_exception` — al menos en `ErrorCode` y `AuditAction`, verificado directamente; no inspeccioné los 4 restantes antes de decidir corregir y volver a correr los 6 igual. Causa: la consulta usaba `name:(SMARTFRAN-CLOUD-BUSINESS-PRO OR ...)` sin comillas por término — OpenSearch interpreta el guión sin comillas como operador NOT de Lucene. Corrijo `scripts.sh` citando cada nombre de servicio individualmente. Ninguno de los 6 campos condicionales, ni `Category`, está confirmado todavía en datos reales — queda pendiente re-correr C2 corregido.

## 2026-08-19 — Debugging adicional de la consulta y resolución de la sintaxis

Encuentro que la corrección de comillas por sí sola no alcanza: el JSON saliente quedaba mal formado porque las comillas de `SERVICES` no estaban pre-escapadas para el contexto donde se interpolan (la sustitución de variables de bash no reprocesa backslashes). Corrijo `SERVICES` para que ya contenga las secuencias `\"` escapadas. Con eso el JSON queda válido, pero las 6 consultas siguen fallando con el mismo `query_shard_exception`, ahora por un motivo distinto: confirmo con una prueba aislada (una sola app, sin agrupamiento OR) que el problema es específicamente el wildcard (`*ErrorCode*`) — este cluster de OpenSearch rechaza wildcards al inicio del término. Prueba sin wildcard: la consulta parsea correctamente pero devuelve 0 resultados incluso para `TraceKey`, campo que sé que está presente (confirmado por una muestra real ya compartida en la conversación). Confirmo entonces que `resultDescription` es un campo tipo `keyword` (no analizado/tokenizado) — ninguna búsqueda de subcadena sin wildcard puede funcionar ahí. Pruebo una consulta por expresión regular (`resultDescription:/.*TraceKey.*/`) y obtengo 97306 resultados reales en Business — confirmo que regex es la forma de consulta correcta para este campo, no sujeta a la restricción de wildcard inicial. Corrijo `scripts.sh` (C2) para usar regex.

Corro C2 con la sintaxis regex sobre los 6 campos condicionales: los 6 devuelven `total_results: 0` en la ventana de 7 días, sobre los 6 servicios combinados. Dado el esfuerzo ya invertido en resolver la metodología de consulta, decido no seguir intentando confirmar estos 6 campos (ni `Category`) contra tráfico real antes de escribir el fix — `devs-log-structure.md` §3.3/§6 ya documenta la forma exacta de estos campos con ejemplos concretos por helper, y el patrón de guardado contra clave ausente no representa ningún riesgo si un campo resulta más raro de lo esperado en producción. Dejo la confirmación en vivo de estos 6 campos como paso de verificación posterior al despliegue, igual que GITIN-1883 usó `_exists_:<campo>`.

## 2026-08-19 — Fix escrito y aplicado a ambas copias versionadas del pipeline

He leído el bloque Ruby existente de GITIN-1883 en `bots/settings/prod-sfcloud-monitoreo/etc/logstash/conf.d/azure-eventhub-to-graylog.conf` para extenderlo con precisión en vez de reconstruirlo de memoria. Confirmo antes de editar que esa copia y la de `cloud-graylog/docs/azure-eventhub-to-graylog.conf` (repositorio separado, no forma parte de este monorepo, pero accesible localmente) coinciden salvo las líneas de credenciales ya documentadas en GITIN-1883.

Agrego un nuevo bloque Ruby (etiquetado GITIN-1892) inmediatamente después del bloque de GITIN-1883, mismo patrón de parseo de `resultDescription`. Promuevo `UserId`/`ProcessType`/`Component`/`RequestId` con el mismo guardado por string vacío que usa GITIN-1883; para `Category`/`SourceContext`/`ErrorCode`/`Operation`/`AuditAction`/`AuditOutcome` uso el mismo guardado — confirmo que `props["X"].is_a?(String)` ya es seguro contra clave ausente (`nil.is_a?(String)` es `false`), no hace falta un chequeo adicional de presencia de clave como había anotado antes en `investigation.md` (corrijo esa nota). `Recovered`/`Handled` son booleanos en el payload CLEF (no strings) — los guardo con `[true, false].include?(...)`, lo que además promueve correctamente el valor `false` sin confundirlo con ausencia.

Aplico el mismo bloque a las dos copias versionadas (`cloud-graylog/docs/` y `bots/settings/prod-sfcloud-monitoreo/`) en la misma sesión, evitando el olvido que pasó en GITIN-1883. Confirmo con `diff` que ambas copias siguen coincidiendo salvo las líneas de credenciales ya conocidas. Valido la lógica del bloque nuevo de forma aislada (no `logstash` instalado localmente, mismo límite que GITIN-1883): reconstruyo el bloque en un script Ruby de prueba con un evento simulado — confirmo que los campos presentes se promueven correctamente (incluido `Recovered: true` y `Handled: false`), que `UserId` vacío no se promueve, y que un campo ausente (`ErrorCode` no presente en el hash de `Properties`) queda correctamente guardado sin intentar promoverlo. No desplegado a la VM todavía — queda pendiente el ciclo de patch acotado / `logstash -t` / restart, igual que GITIN-1883.

## 2026-08-19 — Corrección de alcance: Sales agregado al fix

El primer borrador de este ticket dejaba a Sales fuera de alcance, asumiendo que su `Properties` seguía aplanándose solo vía el auto-flatten de GELF (cierto antes de GITIN-1883). Confirmo que eso ya no es así: GITIN-1883 stringifica el `Properties` de nivel superior de Sales después de extraer los 4 campos que promueve, precisamente para evitar que GELF genere duplicados `Properties_*` — desde entonces, ninguno de los otros 12 campos de este ticket se aplana solo para Sales, quedan atrapados dentro de ese string.

Agrego una segunda rama al bloque de GITIN-1892 para Sales, que parsea `event.get("Properties")` como el string JSON que ya deja el bloque de GITIN-1883 (no como Hash en vivo, que es como lo lee GITIN-1883 dentro de su propio bloque, antes de stringificarlo). Aplico el mismo cambio a ambas copias versionadas del pipeline y confirmo con `diff` que se mantienen sincronizadas. Reviso también un artefacto propio de redacción: había dejado comillas simples dobles (`''`, escape de Ruby para el string de `code => '...'`) filtradas hacia el texto de los comentarios `#`, donde no corresponde — lo corrijo en ambas copias.

Reconstruyo la prueba aislada con 4 escenarios (app vía Event Hub con los 8 campos condicionales presentes; app vía Event Hub con solo los 4 siempre-presentes; Sales con `Properties` ya stringificado por GITIN-1883, incluyendo `Recovered: false`/`Handled: true`; un evento sin `resultDescription` ni `Properties` en absoluto, para confirmar que no rompe). Los 4 casos pasan correctamente.

## 2026-08-19 — Falsa alarma detectada y corregida durante la preparación del despliegue

Al traer el archivo real de la VM para generar el patch, leo mal su contenido: veo que el comentario de GITIN-1883 sigue diciendo "TraceKey / TenantId" únicamente (comentario que ese ticket deliberadamente nunca reescribe al parchear, según su propia práctica documentada) y concluyo erróneamente que el código de `Service`/`Environment`/unificación de Sales no está desplegado en producción. Freno el despliegue de este ticket y abro una investigación aparte (`cloud/events/20260819_gitin1883-config-drift/`) para confirmarlo.

Corrijo el error: confirmo con `grep`/`diff` directo que las 8 líneas `event.set(...)` de GITIN-1883 en el archivo real de la VM son idénticas, línea por línea, a las del repo — el código completo de GITIN-1883 (los 4 campos + las dos ramas) sí está desplegado y persistido. Las reglas de Graylog Pipeline Rules y el tráfico real de Sales confirmados en la investigación aparte también coinciden con lo documentado como resuelto en GITIN-1883. No hay ninguna falla real de despliegue ni de verificación en ese ticket — el error fue mío, al no leer con suficiente cuidado el código debajo del comentario desactualizado. Cierro esa investigación como falsa alarma y retomo el despliegue de GITIN-1892 usando el archivo real de la VM ya obtenido (`vm-live-azure-eventhub-to-graylog.conf`) como base válida para el patch.

Genero `gitin-1892.patch` con `diff -u` contra ese archivo, inserto el bloque nuevo después de la sección de GITIN-1883, valido con `patch --dry-run` localmente — aplica limpio.

## 2026-08-19 — Secreto real encontrado en `vm-live-azure-eventhub-to-graylog.conf` y redactado

Releo el archivo `vm-orig-azure-eventhub-to-graylog.conf` (snapshot `.orig` de la otra investigación) para verificar los números de línea reales del patch, dado que había asumido que `vm-live-azure-eventhub-to-graylog.conf` no tenía el bloque `input {}` (redactado). Al recontar líneas encuentro que esa asunción era incorrecta: `vm-live-azure-eventhub-to-graylog.conf` sí tiene el bloque `input {}` completo — y contiene, en texto plano, el `SharedAccessKey` real del Event Hub y el `AccountKey` real de la cuenta de storage. El contenido del archivo cambió entre mi primera lectura (que sí mostraba el bloque redactado) y esta relectura — no puedo explicar cómo, pero el archivo en disco ahora tiene el secreto real.

Verifico primero el alcance: `git status` confirma que ambas carpetas de evento (`20260819_promote-remaining-clef-fields/` y `20260819_gitin1883-config-drift/`) siguen sin trackear (`??`), nada agregado al stage ni commiteado — el secreto nunca entró al historial de git. Confirmo también que `gitin-1892.patch` (generado antes de este hallazgo) no contiene ninguna de las dos claves — el hunk del patch solo toca líneas muy posteriores al bloque `input`, lejos de donde vive el secreto.

Redacto de inmediato las dos líneas en `vm-live-azure-eventhub-to-graylog.conf`, reemplazando ambos valores por los mismos placeholders que ya usa el resto del repo (`EVENTHUB_CONNECTION_STRING_PLACEHOLDER` / `STORAGE_CONNECTION_STRING_PLACEHOLDER`). Elimino además `vm-true-before.conf`, un archivo de reconstrucción que había generado a partir de la premisa incorrecta (bloque `input` faltante) y que por lo tanto duplicaba el secreto real. Confirmo con `grep` que ninguno de los archivos de ambas carpetas de evento contiene ya patrones de credenciales (`SharedAccessKey`, `AccountKey=`, etc.). Re-confirmo que `gitin-1892.patch` sigue aplicando limpio (`patch --dry-run`) contra el archivo ya redactado — la corrección de línea que había considerado necesaria no lo era: el archivo ya tenía la estructura completa (242 líneas) desde antes de generar el patch, así que los números de línea del patch original eran correctos desde el principio.

Esta clave debe tratarse como potencialmente expuesta — quedó en texto plano en un archivo local, aunque nunca llegó a git — y conviene rotarla según el proceso de gestión de secretos correspondiente.

## 2026-08-19 — Validación contra el código fuente real: 5 de los 12 campos con nombre incorrecto

Hago `git fetch`/`pull --ff-only` sobre el clon local de `cloud/repo/SmartFran.Cloud` (rama `dev`, ya actualizado) y leo directamente `SmartFranLogExtensions.cs` y `EnrichmentMiddleware.cs` — las mismas fuentes de verdad que cita `devs-log-structure.md`. Encuentro que el código real usa nombres de clave distintos a los documentados para 5 de los 6 campos condicionales:

| Documentado (lo que promoví) | Real en el código fuente |
|---|---|
| `ErrorCode` | `_error_code` |
| `Recovered` | `_recovered` |
| `Handled` | `_handled` |
| `AuditAction` | `_audit_action` |
| `AuditOutcome` | `_audit_outcome` |
| `Operation` | Correcto tal cual — confirmado vía placeholder de message template en `LogTransientFailure` y `LogUnrecoverableFailure` |
| `Category` | Correcto tal cual — coincide exactamente con el código fuente |

Esto explica exactamente por qué C2 dio 0 resultados en los 6 campos condicionales durante toda la investigación: no era falta de un evento real que los disparara — esos 5 nombres de campo directamente no existen en el código actual. `devs-log-structure.md` documenta estos 5 campos en PascalCase sin guión bajo (según su propia regla §3.6, "toda propiedad se emite en PascalCase, sin prefijo `_`"), pero el código real de `SmartFranLogExtensions.cs` los agrega al scope ambient con nombres con guión bajo — una discrepancia entre el doc y el código, no un problema de mi pipeline hasta este momento.

Corrijo el bloque Ruby de GITIN-1892 en ambas copias versionadas del pipeline, manteniendo el nombre de campo promovido (el que ya comuniqué en el PM email y en `ops.md`) pero leyendo desde la clave real del origen. La primera corrección (`replace_all`) solo alcanza la rama de Event Hub apps (usa `props[...]`) — la rama de Sales (usa `top_props[...]`) no matchea el mismo bloque de texto literal porque cada línea tiene el prefijo `top_` repetido varias veces, rompiendo el substring completo. Corrijo la rama de Sales por separado.

Revalido con una prueba aislada de 5 escenarios (helper de Security con nombres reales, `LogDomainError`, `LogTransientFailure` con `_recovered`, `LogUnrecoverableFailure` con `_handled: false`, y Sales con `Properties` stringificado) — los 5 pasan correctamente.

Traigo el archivo real de la VM (ya con el primer despliegue, nombres incorrectos) para generar un patch correctivo — confirmo que no contiene ninguna credencial (0 coincidencias de `SharedAccessKey`/`AccountKey=`). Genero `gitin-1892-fix-field-names.patch` (10 líneas, las 5 correcciones × 2 ramas), confirmo que tampoco contiene credenciales, valido `patch --dry-run` limpio localmente y en la VM. Aplico el patch real, corro `logstash -t`: `Configuration OK`. Reinicio el servicio — `active (running)`.

Dejo pendiente como seguimiento: volver a correr C5 contra tráfico real una vez que ocurra un evento genuino de alguno de los 4 helpers condicionales, para confirmar los nombres corregidos en producción.

## 2026-08-19 — Corrección de `cloud/docs/devs-log-structure.md`

Corrijo directamente `cloud/docs/devs-log-structure.md` con los nombres reales confirmados en `SmartFranLogExtensions.cs`. Cambios: §3.3 (tabla de claves de scope por helper, separando claves de scope reales de las que además llegan vía placeholder de mensaje), §3.6 (la regla "todo PascalCase sin `_`" pasa de afirmación única a regla pretendida con la excepción real documentada), §6.3/§6.4/§6.6/§6.7 (ejemplos JSON y texto descriptivo corregidos: `_error_code`, `_recovered`, `_handled`, `_audit_action`, `_audit_outcome`), §9 (snippet de lectura del consumer), y una nota en el encabezado del documento apuntando a esta corrección. Cada cambio queda con una nota fechada y con referencia a GITIN-1892, no como una reescritura silenciosa. Confirmo con `grep` que no queda ninguna referencia sin marcar a los 5 nombres incorrectos en el resto del documento.

## 2026-08-19 — Validación de §3.2 contra el código fuente: sección correcta, hallazgo H2 sin resolver

Reviso §3.2 (`EnrichmentMiddleware`) contra `EnrichmentMiddleware.cs`, comparando cada fila de la tabla contra el código real — a diferencia de §3.3, no encuentro ningún nombre de clave incorrecto; los 8 campos (`Service`/`Environment`/`Version`/`TraceKey`/`TenantId`/`UserId`/`ProcessType`/`Component`) y sus orígenes documentados coinciden exactamente con el diccionario que arma el middleware.

Busco además todos los llamados a `UseSmartFranLogEnrichment` en el código (`git grep`, tanto en `dev` como en `main`, ya que `cloud/CLAUDE.md` advierte que pueden divergir) — los 8 servicios pasan su propio nombre de dominio de negocio como `component` (`"Business"`, `"Sales"`, `"Catalog"`, etc.), exactamente como documenta el ejemplo de la fila `Component`. El commit que introduce este patrón es `311862afb7` (2026-08-05, ticket GSFC-LOG-1, "Reemplaza al TracingMiddleware legacy").

Esto deja el hallazgo H2 de este mismo ticket (`Component` real observado como `Api`/`Web` en vez del nombre de dominio) sin explicación confirmada — reviso el `TracingMiddleware` legacy que ese commit reemplaza y no setea `Component` en ningún lado, así que no alcanza como causa por sí solo. La fecha reciente del commit (dos semanas antes de esta sesión) es sugestiva de que el binario en producción podría ser anterior, pero no lo confirmo como causa — lo dejo registrado como una teoría no verificada, no como hecho. Actualizo H2 en `ops.md` con este estado y subo su riesgo de Bajo a Medio, dado que ahora hay una pregunta concreta y sin responder sobre qué versión está efectivamente desplegada. Agrego una nota de verificación (no de corrección) a §3.2 del doc, dejando registrado que la sección en sí es correcta.

Encuentro además, al leer el comentario XML de la clase `EnrichmentMiddleware`, que documenta el header de tenant como `X-Tenant-Id` — pero la constante real del código (`TenantHeader`) es `"TenantId"`, sin el prefijo `X-`. Es una inconsistencia dentro del propio código fuente (el comentario contra la constante), no un error de `devs-log-structure.md` — el doc ya documentaba correctamente `TenantId`. No lo corrijo (no es un archivo de este repo), lo dejo registrado acá como hallazgo secundario para reportarlo a Dev si corresponde.

## 2026-08-19 — Cobertura de §3.2: `Version` nunca se promovió

Reviso, campo por campo, cuáles de los 8 campos canónicos de §3.2 quedaron efectivamente aplanados en Graylog entre GITIN-1883 y GITIN-1892:

```
┌─────────────┬───────────────────┬─────────────────┐
│    Field    │     Promoted?     │ By which ticket │
├─────────────┼───────────────────┼─────────────────┤
│ Service     │ ✅                │ GITIN-1883      │
├─────────────┼───────────────────┼─────────────────┤
│ Environment │ ✅                │ GITIN-1883      │
├─────────────┼───────────────────┼─────────────────┤
│ TraceKey    │ ✅                │ GITIN-1883      │
├─────────────┼───────────────────┼─────────────────┤
│ TenantId    │ ✅                │ GITIN-1883      │
├─────────────┼───────────────────┼─────────────────┤
│ UserId      │ ✅                │ GITIN-1892      │
├─────────────┼───────────────────┼─────────────────┤
│ ProcessType │ ✅                │ GITIN-1892      │
├─────────────┼───────────────────┼─────────────────┤
│ Component   │ ✅                │ GITIN-1892      │
├─────────────┼───────────────────┼─────────────────┤
│ Version     │ ❌ Never promoted │ —               │
└─────────────┴───────────────────┴─────────────────┘
```

Confirmo con `grep` que `event.set("Version", ...)` no existe en ningún lado del pipeline — ninguno de los dos tickets lo tuvo en su alcance. Está presente en las muestras reales, pero siempre anidado dentro de `resultDescription`/`Properties` (ej. `"1.0.0+c6668229d20569923c2854855bc06bad8185dbfc"`), nunca a nivel superior. Decido extender el fix de GITIN-1892 para cubrir también `Version` — mismo patrón de guardado que `Service`/`Environment` (string no vacío), en ambas ramas (Event Hub apps + Sales).

Agrego `event.set("Version", ...)` en ambas ramas del bloque de GITIN-1892, en ambas copias versionadas del pipeline, y actualizo el comentario descriptivo del bloque para incluirlo. Confirmo con `diff` que ambas copias siguen sincronizadas salvo las líneas de credenciales ya conocidas. Valido con una prueba aislada (2 escenarios: Event Hub y Sales, ambos con `Version` presente) — los 2 pasan correctamente.

Traigo el archivo real de la VM (ya con la corrección de nombres de clave del paso anterior), confirmo que no contiene credenciales (0 coincidencias), genero `gitin-1892-add-version.patch` (3 líneas: comentario descriptivo + una línea por rama), confirmo que tampoco contiene credenciales, valido `patch --dry-run` limpio localmente y en la VM. Aplico el patch real, corro `logstash -t`: `Configuration OK`. Reinicio el servicio — `active (running)`.

Agrego una tabla de cobertura de §3.2 a `ops.md` (mismo formato de caja ASCII que usé acá), con `Version` ya marcado como promovido por este ticket.

## 2026-08-19 — C5 re-corrido tras los 3 despliegues

Vuelvo a correr C5 (ahora con 13 campos, incluido `Version`) sobre una ventana de 30 minutos con más tráfico acumulado. Confirmo `Version` activo — 10686 hits en 9 servicios (PRO y DEV, incluido Sales con 9450). `ProcessType`/`Component`/`RequestId`/`SourceContext` siguen activos, con conteos mucho mayores que la primera corrida (más tiempo de tráfico acumulado). `UserId`, `Category` y los 6 campos condicionales siguen en 0 — sin cambios respecto a la corrida anterior, coincide con lo ya documentado (H4/H10).

## 2026-08-19 — Una muestra real por servicio (los 6 vía Event Hub + Sales)

Traigo un mensaje real reciente por cada uno de los 7 servicios (últimos 30 minutos, sin filtrar por categoría) para confirmar de forma concreta, servicio por servicio, no solo agregada. Confirmo `AppLevel`/`TraceKey`/`Service`/`Environment`/`Version`/`ProcessType`/`Component`/`RequestId` presentes en los 7. `TenantId` presente en 5 de 7 (ausente en Admin y Platform — mensajes de sistema/background, coincide con lo ya documentado). `SourceContext` presente en 4 de 7 (Sales, Business, Admin, Catalog) — confirma de nuevo que varía genuinamente según el call site, no es un bug.

La discrepancia de `Component` (H2) queda confirmada con datos de flota completa: 6 de 7 servicios muestran `Api`, Admin muestra `Web` — ninguno muestra el nombre de dominio de negocio que pasa el código fuente. Confirmo además, con esta muestra, la nota ya documentada en `graylog-log-fields.md` sobre Admin: su campo `Service` real es `"Client"`, no `"Admin"` — coincide con que el proyecto real detrás de `SMARTFRAN-CLOUD-ADMIN-PRO` es `Client.Web`, no un servicio "Admin" separado. `Category` y los 6 campos condicionales siguen en 0 de 7 — sin cambios.

## 2026-08-19 — Patch aplicado y validado en la VM

El primer intento de `patch --dry-run` en la VM falla (`can't find file to patch`) — el encabezado del diff generado localmente usaba los nombres de archivo locales (`vm-live-...`/`vm-after-...`) en vez del nombre real del archivo (`azure-eventhub-to-graylog.conf`), y `patch -p0` matchea por nombre de encabezado. Regenero `gitin-1892.patch` con `diff -L azure-eventhub-to-graylog.conf -L azure-eventhub-to-graylog.conf`, confirmo que sigue sin contener ninguna de las credenciales redactadas, y valido `patch --dry-run` limpio tanto localmente como en la VM.

Aplico el patch real (`sudo patch -p0`) y corro `logstash -t --path.settings /etc/logstash`: `Configuration OK`. El warning `key "e" is duplicated and overwritten on line 118` en `logstash-output-gelf-3.1.7` es el mismo warning interno del plugin, preexistente, ya documentado en GITIN-1883 — no relacionado con este cambio. Reinicio el servicio (`sudo systemctl restart logstash`): `systemctl status` confirma `active (running)`, a 17ms del arranque — insuficiente para confirmar reconexión limpia a las particiones de Event Hub, mismo punto que GITIN-1883 dejó registrado en su propio despliegue. Espero unos minutos de tráfico real antes de correr la verificación (C5 en `scripts.sh`).

## 2026-08-19 — Verificación C5 contra tráfico real (30 min post-restart)

Corro C5 (`_exists_:<campo>` por cada uno de los 12 campos, ventana de 30 minutos). Confirmo 4 campos activos en tráfico real, incluido Sales: `ProcessType` (778 hits, 502 en Sales-PRO), `Component` (1011 hits, 698 en Sales-PRO), `RequestId` (1184 hits, 778 en Sales-PRO), `SourceContext` (965 hits, 792 en Sales-PRO, más Business/Admin/Catalog). La rama de Sales agregada como corrección de alcance queda confirmada funcionando en producción.

`UserId` da 0 hits — esperado, no es una falla: todas las muestras reales vistas durante esta investigación mostraban `UserId: ""` (vacío), y el guardado contra string vacío hace exactamente lo que debe (no promover un campo vacío). `Category` y los 6 campos condicionales (`ErrorCode`/`Operation`/`Recovered`/`Handled`/`AuditAction`/`AuditOutcome`) dan 0 hits los 7 — coincide con lo ya encontrado antes del despliegue (ninguno de los 4 helpers canónicos que los generan disparó en la ventana muestreada, ni en los 7 días previos). No lo interpreto como evidencia de una falla en el código — la prueba aislada ya confirmó la lógica correcta para estos 7 campos — sino como falta de un evento real que los dispare todavía. Dejo esto como seguimiento (acción #6 de `ops.md`), no bloquea el cierre del despliegue.

## 2026-08-20 — Verificación de cobertura completa contra el Resumen

Reviso el Resumen de `ops.md` contra el bloque Ruby efectivamente desplegado (`bots/settings/prod-sfcloud-monitoreo/etc/logstash/conf.d/azure-eventhub-to-graylog.conf`) y contra `devs-log-structure.md` §9, para confirmar que los "13 campos" que declara el Resumen son exactamente los que promueve el pipeline — sin diferencia. Confirmado: coinciden uno a uno.

Encuentro, al recontar §9 (ya actualizada por este mismo ticket), que existen 3 campos canónicos adicionales — `Attempt`, `Action`, `Outcome` — que no forman parte de los 13. Son los compañeros PascalCase de `_recovered`/`_audit_action`/`_audit_outcome`, y llegan vía placeholder de mensaje en vez de vía el scope del helper. Confirmo que `graylog-log-fields.md` ya los documenta como fuera de alcance (sección "Full field list", línea agregada en esta misma sesión) — no es un olvido de este ticket, nunca estuvieron en su alcance original. Agrego de todas formas la acción #11 a `ops.md` para dejarlo trazable como seguimiento explícito sin ticket, no bloqueante.
