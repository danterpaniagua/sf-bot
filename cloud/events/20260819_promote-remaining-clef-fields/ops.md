# Promover campos canónicos restantes de Properties en Graylog — GITIN-1892

**Tags:** `SmartCloud`, `Graylog`, `Azure`, `PROD`

## Resumen

De los 16 campos canónicos de `Properties` documentados en `cloud/docs/devs-log-structure.md` §9, GITIN-1883 (cerrado 2026-08-18) promovió 4 (`TraceKey`, `TenantId`, `Service`, `Environment`) a campos de nivel superior en Graylog para los 6 servicios que ingestan vía Event Hub (Business, Admin, Platform, Person, Catalog, Orders) y para Sales (ingesta directa vía GELF). Los 12 campos restantes documentados en §9 (`UserId`, `Component`, `ProcessType`, `Category`, `ErrorCode`, `Operation`, `Recovered`, `Handled`, `AuditAction`, `AuditOutcome`, `RequestId`, `SourceContext`) seguían sin promoverse: existían en los logs de aplicación, pero no eran buscables ni filtrables como columna propia en Graylog — quedaban atrapados dentro de un bloque de texto JSON anidado (`resultDescription` en los 6 servicios vía Event Hub; `Properties` ya stringificado por el propio fix de GITIN-1883 en el caso de Sales). Al revisar la cobertura completa de §3.2 (los 8 campos que arma `EnrichmentMiddleware`, no solo los que ya promovió GITIN-1883) se encontró un 13er campo con el mismo problema: `Version`, documentado en §3.2 desde el principio pero nunca promovido por ningún ticket. Este ticket habilita los 13 campos como planos, para los 6 servicios vía Event Hub y para Sales. Pos queda fuera de alcance — no emite mensajes `AppServiceConsoleLogs` (GITIN-1811, categoría no soportada en Windows/.NET).

## Tabla resumen

| Campo | Valor |
|---|---|
| Ticket Jira | GITIN-1892 (padre: GITIN-1835) |
| ID alerta | N/A — tarea planificada, no alerta |
| Sistema | SmartFran Cloud — pipeline de logs a Graylog (Logstash `azure-eventhub-to-graylog.conf`, repo `cloud-graylog`) |
| Severidad | Baja — mejora de búsqueda/visibilidad, no hay pérdida de datos ni impacto en disponibilidad |
| Detectado | 2026-08-18/19, continuación directa de GITIN-1883 |
| Resuelto | Sí — 2026-08-19. Desplegado y confirmado contra tráfico real: `ProcessType`/`Component`/`RequestId`/`SourceContext` activos, incluido Sales. `UserId` en 0 hits por diseño (siempre vacío en la app, guardado correctamente no promueve). Se validó además el fix contra el código fuente real (`cloud/repo/SmartFran.Cloud`) y se corrigieron 5 nombres de clave incorrectos (`ErrorCode`/`Recovered`/`Handled`/`AuditAction`/`AuditOutcome` — ver H9), con un segundo despliegue correctivo el mismo día. `Category` y los 6 campos condicionales siguen en 0 hits en tráfico real — ningún helper que los genera disparó todavía en la ventana muestreada, no implica que el fix (ya corregido) no vaya a funcionar; seguimiento no bloqueante (acción 6) |
| Responsable | SRE |

## Causa raíz

El bloque Ruby de GITIN-1883 en `azure-eventhub-to-graylog.conf` que parsea `resultDescription` (para los 6 servicios vía Event Hub) y el `Properties` de nivel superior (para Sales) solo lee y promueve 4 campos (`TraceKey`/`TenantId`/`Service`/`Environment`). El resto de los campos canónicos documentados en `devs-log-structure.md` §9 quedan sin leer por ese bloque — no es una limitación del pipeline en sí, sino que GITIN-1883 nunca los tuvo en su alcance original.

Para Sales específicamente, GITIN-1883 introdujo un efecto adicional: al stringificar el `Properties` de nivel superior después de extraer los 4 campos (para evitar que GELF genere duplicados `Properties_*`), el resto de los campos dejó de aplanarse automáticamente para Sales también — antes de GITIN-1883, GELF los aplanaba solo con el prefijo `Properties_`; después de GITIN-1883, ni siquiera con prefijo, porque quedan dentro del string.

## Cobertura de §3.2 (`devs-log-structure.md`)

Los 8 campos canónicos que arma `EnrichmentMiddleware`, y qué ticket promovió cada uno a nivel superior en Graylog:

```
┌─────────────┬─────────────┬──────────────────────────────┐
│    Field    │  Promoted?  │        By which ticket        │
├─────────────┼─────────────┼──────────────────────────────┤
│ Service     │ ✅          │ GITIN-1883                    │
├─────────────┼─────────────┼──────────────────────────────┤
│ Environment │ ✅          │ GITIN-1883                    │
├─────────────┼─────────────┼──────────────────────────────┤
│ TraceKey    │ ✅          │ GITIN-1883                    │
├─────────────┼─────────────┼──────────────────────────────┤
│ TenantId    │ ✅          │ GITIN-1883                    │
├─────────────┼─────────────┼──────────────────────────────┤
│ UserId      │ ✅          │ GITIN-1892                    │
├─────────────┼─────────────┼──────────────────────────────┤
│ ProcessType │ ✅          │ GITIN-1892                    │
├─────────────┼─────────────┼──────────────────────────────┤
│ Component   │ ✅          │ GITIN-1892                    │
├─────────────┼─────────────┼──────────────────────────────┤
│ Version     │ ✅          │ GITIN-1892 (ver H10)          │
└─────────────┴─────────────┴──────────────────────────────┘
```

Los 8 campos de §3.2 quedan cubiertos. Ver H9 para los 5 campos de §3.3 (condicionales) que requirieron una corrección adicional de nombre de clave.

## Formato JSON — antes / después

Dos mensajes reales (Business vía Event Hub, Sales vía GELF directo), solo los campos de nivel superior relevantes — el resto de campos técnicos de Azure/Graylog (`gl2_*`, `resourceId`, `EventStamp*`, etc.) se omiten por brevedad. `resultDescription`/`Exception` se truncan — su contenido completo puede incluir datos sensibles (ej. headers de request con token de autorización) que no corresponde citar en un ticket.

**Antes de este ticket** (solo lo que promovió GITIN-1883 — `TraceKey`/`TenantId`/`Service`/`Environment`/`AppLevel`):

```json
{
  "AppLevel": "Information",
  "TraceKey": "SFCADMWEB.POS:14.2026-08-19T14:20:19.6120000+00:00",
  "TenantId": "d3186bc6d7b2",
  "Service": "Business",
  "Environment": "Production",
  "resultDescription": "{\"Properties\":{\"UserId\":\"\",\"ProcessType\":\"Api\",\"Component\":\"Api\",\"RequestId\":\"0HNNTTQ6EU0I1:00000058\",\"SourceContext\":\"SmartFran.Cloud.Business...\", ...}}",
  "name": "SMARTFRAN-CLOUD-BUSINESS-PRO",
  "category": "AppServiceConsoleLogs"
}
```

**Después de este ticket** (mismo mensaje real — `Version` confirmado por separado en tráfico real vía C10, valor real observado en la misma muestra):

```json
{
  "AppLevel": "Information",
  "TraceKey": "SFCADMWEB.POS:14.2026-08-19T14:20:19.6120000+00:00",
  "TenantId": "d3186bc6d7b2",
  "Service": "Business",
  "Environment": "Production",
  "Version": "1.0.0+c6668229d20569923c2854855bc06bad8185dbfc",
  "ProcessType": "Api",
  "Component": "Api",
  "RequestId": "0HNNTTQ6EU0I1:00000058",
  "SourceContext": "SmartFran.Cloud.Business.Infrastructure.Repositories.Domain.Entities.Movement.POSMovementType",
  "resultDescription": "{...}",
  "name": "SMARTFRAN-CLOUD-BUSINESS-PRO",
  "category": "AppServiceConsoleLogs"
}
```

`UserId` no aparece — llegó vacío en este mensaje real (`""`), y el guardado no promueve strings vacíos, mismo criterio que GITIN-1883.

**Segundo ejemplo real — Sales, `AppLevel: Error`** (confirma la rama de Sales, incluida la stringificación de `Properties` que dejó GITIN-1883, funcionando correctamente en un mensaje de error real):

```json
{
  "AppLevel": "Error",
  "Level": "Error",
  "TraceKey": "SFCADMWEB.POS:5.2026-08-19T16:44:59.4790000+00:00",
  "TenantId": "d3186bc6d7b2",
  "Service": "Sales",
  "Environment": "Production",
  "Version": "1.0.0+c6668229d20569923c2854855bc06bad8185dbfc",
  "ProcessType": "Api",
  "Component": "Api",
  "RequestId": "40008dd8-0000-c300-b63f-84710c7967bb",
  "SourceContext": "SmartFran.Cloud.Sales.Infrastructure.Repositories.Domain.Entities.Sale",
  "MessageTemplate": "Sale.Close.StockMovement.Failed: SaleId=... Stage=stock_movement ExceptionType=ApiException",
  "Exception": "SpecsBusiness.ApiException: The HTTP status code of the response was not expected (403)...",
  "Properties": "{...stringificado, ver Causa raíz...}",
  "name": "SMARTFRAN-CLOUD-SALES-PRO"
}
```

Este ejemplo confirma también, con un caso real (no ilustrativo), el hallazgo H3/H4: aunque `AppLevel` es `Error`, `Category` y `ErrorCode` **no** aparecen — este log se generó con un `LogError` estándar (`ex`, template), no con el helper `LogDomainError`, que es el único que agrega esos dos campos. Severidad `Error` y el helper `LogDomainError` son cosas distintas.

**`Category` y los 6 campos condicionales cuando sí se originan en su helper correspondiente** — **no confirmados todavía en tráfico real** (ver H4), forma tomada del ejemplo documentado en `devs-log-structure.md` §6.3 (`LogDomainError`):

```json
{
  "Category": "Error",
  "ErrorCode": "PAYMENT_PROVIDER_FAILED"
}
```

## Confirmación por servicio (C11)

Un mensaje real por servicio (últimos 30 min, sin filtrar por categoría), los 6 vía Event Hub + Sales:

```
┌───────────┬──────────┬──────────┬───────────┬───────────┬───────────────┬─────────┐
│  Service  │ TenantId │ Version  │ ProcessTy │ Component │ SourceContext │ Category│
├───────────┼──────────┼──────────┼───────────┼───────────┼───────────────┼─────────┤
│ Sales     │ ✅       │ ✅       │ ✅ Api    │ ✅ Api    │ ✅            │ —       │
│ Business  │ ✅       │ ✅       │ ✅ Api    │ ✅ Api    │ ✅            │ —       │
│ Admin     │ —        │ ✅       │ ✅ Api    │ ✅ Web    │ ✅            │ —       │
│ Platform  │ —        │ ✅       │ ✅ Api    │ ✅ Api    │ —             │ —       │
│ Person    │ ✅       │ ✅       │ ✅ Api    │ ✅ Api    │ —             │ —       │
│ Catalog   │ ✅       │ ✅       │ ✅ Api    │ ✅ Api    │ ✅            │ —       │
│ Orders    │ ✅       │ ✅       │ ✅ Api    │ ✅ Api    │ —             │ —       │
└───────────┴──────────┴──────────┴───────────┴───────────┴───────────────┴─────────┘
```

`AppLevel`/`TraceKey`/`Service`/`Environment`/`RequestId` presentes en los 7, omitidos de la tabla por brevedad. `TenantId` ausente en Admin/Platform — mensajes de sistema/background, consistente con lo ya documentado. `SourceContext` presente en 4/7 — varía genuinamente según el call site (repositorio/controller vs. middleware genérico), no es un bug. `Component` confirma H2 con datos de flota completa: 6/7 muestran `Api`, ninguno muestra el nombre de dominio de negocio. `Category` y los 6 campos condicionales: 0/7, sin cambios respecto a H4. Nota adicional: el `Service` real de Admin es `"Client"` (no `"Admin"`) — el proyecto detrás de `SMARTFRAN-CLOUD-ADMIN-PRO` es `Client.Web`, ya documentado en `graylog-log-fields.md`.

## Hallazgos

| # | Hallazgo | Riesgo |
|---|---|---|
| H1 | `UserId`, `ProcessType`, `Component`, `RequestId` confirmados presentes en 8 muestras reales de `AppServiceConsoleLogs` (Business, Admin, Platform, Person, Catalog, Orders) independientemente del helper que originó el log — candidatos seguros para el mismo patrón de guardado (string vacío) que usó GITIN-1883. | Bajo |
| H2 | `Component` no coincide con el ejemplo documentado en `devs-log-structure.md` §3.2 (nombre de dominio de negocio, ej. `"Sales"`) — los valores reales observados son `Api` (5/6 servicios) y `Web` (Admin). **Actualización 2026-08-19:** confirmado directamente contra el código fuente (`dev` y `main`) que la sección del doc es correcta — los 8 servicios pasan su nombre de dominio real como `component`, commit `311862afb7` (2026-08-05, GSFC-LOG-1). La discrepancia sigue sin explicación confirmada — el middleware legacy que reemplaza (`TracingMiddleware`) tampoco setea `Component`, así que no alcanza como causa. Sigue pendiente que Dev confirme qué build está efectivamente desplegado en producción. | Medio |
| H3 | `Category` no apareció en ninguna de las 8 muestras reales — ninguna de las muestreadas pasó por los 6 helpers canónicos (`LogBusinessEvent`, etc.), son logs planos de `ILogger` o de middleware. `SourceContext` apareció de forma inconsistente incluso dentro del mismo servicio (presente en logs de repositorio/controller, ausente en logs de `RequestHandlingMiddleware`). Ambos campos requieren guardado contra clave ausente, no solo contra string vacío — mismo criterio aplicado también a los 6 campos condicionales (`ErrorCode`/`Operation`/`Recovered`/`Handled`/`AuditAction`/`AuditOutcome`). | Bajo |
| H4 | Los 6 campos condicionales (ligados a `LogDomainError`/`LogTransientFailure`/`LogUnrecoverableFailure`/`LogSecurityAudit`) no se confirmaron presentes en tráfico real dentro de la ventana de 7 días consultada — no implica ausencia real, solo que ninguno de esos 4 helpers disparó un log en esa ventana para los 6 servicios muestreados. Las formas exactas de estos campos se tomaron de los ejemplos documentados en `devs-log-structure.md` §6.3/§6.4/§6.6/§6.7 en lugar de una muestra en vivo. El patrón de guardado (clave ausente) no representa riesgo si algún campo resulta más raro de lo esperado en producción — simplemente no se promueve. | Bajo |
| H5 | El primer borrador de este ticket dejaba a Sales fuera de alcance, por asumir que sus campos seguían aplanándose vía el auto-flatten de GELF (cierto antes de GITIN-1883, no después — ver Causa raíz). Corregido antes de desplegar: se agregó una segunda rama al fix que parsea el `Properties` ya stringificado por el bloque de GITIN-1883 para Sales. | Medio |
| H6 | Metodología de consulta en Graylog: `resultDescription` resultó ser un campo tipo `keyword` (no analizado/tokenizado) — ni una búsqueda de término simple ni un wildcard (`*X*`, bloqueado por este cluster de OpenSearch para wildcards al inicio del término) funcionan contra ese campo. Una consulta por expresión regular (`resultDescription:/.*X.*/`) sí funciona — confirmado con 97306 resultados reales para `TraceKey` en Business. Deja registrada la forma de consulta correcta para cualquier verificación futura contra este campo. | Bajo |
| H7 | Durante la preparación del despliegue, un archivo local temporal (`vm-live-azure-eventhub-to-graylog.conf`, fuera de este documento) contuvo brevemente el `SharedAccessKey` real del Event Hub y el `AccountKey` real de la cuenta de storage en texto plano. Confirmado que nunca llegó a git (carpeta sin trackear, nada agregado al stage) y que `gitin-1892.patch` nunca contuvo esas credenciales. Redactado de inmediato. La clave debe tratarse como potencialmente expuesta y rotarse según el proceso correspondiente — detalle completo en `ops-events.md`. | Alto |
| H8 | Investigación aparte (`cloud/events/20260819_gitin1883-config-drift/`, cerrada como falsa alarma) descartó una sospecha inicial de que el fix de GITIN-1883 (Service/Environment + unificación de Sales) no estaba realmente desplegado en producción — confirmado que sí lo está, el malentendido fue por no leer con cuidado el código bajo un comentario deliberadamente desactualizado. | Bajo |
| H9 | Validación directa contra `SmartFranLogExtensions.cs`/`EnrichmentMiddleware.cs` en `cloud/repo/SmartFran.Cloud` (rama `dev`, actualizada) encontró que 5 de los 6 campos condicionales tenían el nombre de clave incorrecto en el fix ya desplegado: el código real usa `_error_code`/`_recovered`/`_handled`/`_audit_action`/`_audit_outcome` (con guión bajo, agregados directamente al scope de `BeginScope`), no `ErrorCode`/`Recovered`/`Handled`/`AuditAction`/`AuditOutcome` como documenta `devs-log-structure.md` §3.6. `Operation` y `Category` sí coinciden exactamente con el código real — sin cambios. Esto explica los 0 hits de C2/C5 en estos campos: no era ausencia de un evento real, los nombres de campo directamente no existían. Corregido y redesplegado el mismo día (ver Comandos ejecutados C6/C7). La discrepancia del propio `devs-log-structure.md` queda como acción de seguimiento (#10) — no se corrige ese documento en este ticket. | Alto |
| H10 | Al validar la cobertura completa de §3.2 de `devs-log-structure.md` (los 8 campos que arma `EnrichmentMiddleware`, no solo los 4 que promovió GITIN-1883) se encontró que `Version` nunca fue promovido por ningún ticket — confirmado con `grep`, ningún `event.set("Version", ...)` existía en el pipeline. Extendido el fix de GITIN-1892 para cubrir también `Version` (mismo patrón de guardado que `Service`/`Environment`, ambas ramas), redesplegado el mismo día (ver Comandos ejecutados C8/C9). | Medio |

## Recursos afectados

| Recurso | Detalle |
|---|---|
| App Services PROD/DEV | `SmartFran-Cloud-{Business,Admin,Platform,Person,Catalog,Orders,Sales}-PRO` y equivalentes DEV — origen de los mensajes con los campos a aplanar |
| Logstash | VM `sfcloud-monitoreo`, `/etc/logstash/conf.d/azure-eventhub-to-graylog.conf` — pipeline modificado y en producción |
| Repo `cloud-graylog` | `docs/azure-eventhub-to-graylog.conf` — copia de referencia, ya editada y validada en esta sesión |
| Repo `bots` (este monorepo) | `settings/prod-sfcloud-monitoreo/etc/logstash/conf.d/azure-eventhub-to-graylog.conf` — segunda copia versionada (hallada desactualizada durante GITIN-1883), ya editada en paralelo en esta sesión |
| Graylog Pipeline Rules | Ninguna regla conocida depende por nombre de los 12 campos de este ticket — a confirmar antes de desplegar (ver Acciones propuestas) |

## Comandos ejecutados

| # | Comando/Script | Propósito |
|---|---|---|
| C1 | `scripts.sh` — una muestra plana de `AppServiceConsoleLogs` por servicio (6 servicios vía Event Hub), guardada en `field-samples/` | Confirmar forma real de `UserId`/`ProcessType`/`Component`/`RequestId`/`Category`/`SourceContext` antes del fix |
| C2 | `scripts.sh` — búsqueda por marcador de texto (regex) por cada uno de los 6 campos condicionales, combinando los 6 servicios | Buscar al menos una muestra real de `ErrorCode`/`Operation`/`Recovered`/`Handled`/`AuditAction`/`AuditOutcome` — resultado: 0 hits en los 6, dentro de la ventana de 7 días consultada (ver H4) |
| — | Prueba aislada del bloque Ruby nuevo (4 escenarios simulados, sin `logstash` instalado localmente) | Validar sintaxis y comportamiento de los dos guardados (string vacío / clave ausente) y de la rama Sales — resultado: los 4 escenarios pasan correctamente |
| C3 ⚠️ | `scripts.sh` — `patch --dry-run` + `patch` en la VM, `logstash -t` | Aplicar el cambio — resultado: `Configuration OK` |
| C4 ⚠️ | `scripts.sh` — `sudo systemctl restart logstash` | Recargar el pipeline — resultado: `active (running)` |
| C5 | `scripts.sh` — `_exists_:<campo>` por cada uno de los 12 campos (ventana de 30 min) vía Views Search API | Confirmar contra tráfico real — resultado: 4 campos activos (`ProcessType`/`Component`/`RequestId`/`SourceContext`, incluido Sales), `UserId` en 0 por diseño, `Category` + 6 condicionales en 0 (sin evento real en la ventana, ver H4) |
| — | Lectura directa de `SmartFranLogExtensions.cs`/`EnrichmentMiddleware.cs` en `cloud/repo/SmartFran.Cloud` (`git fetch`/`pull --ff-only` primero) | Validar los 12 campos contra el código fuente real — resultado: 5 nombres de clave incorrectos encontrados (ver H9) |
| C6 ⚠️ | `gitin-1892-fix-field-names.patch` — `patch --dry-run` + `patch` en la VM, `logstash -t` | Corregir los 5 nombres de clave — resultado: `Configuration OK` |
| C7 ⚠️ | `sudo systemctl restart logstash` | Recargar el pipeline con la corrección — resultado: `active (running)` |
| — | Revisión campo por campo de §3.2 contra el pipeline (`grep event.set("Version"`) | Confirmar cobertura completa de los 8 campos de §3.2 — resultado: `Version` nunca promovido (ver H10) |
| C8 ⚠️ | `gitin-1892-add-version.patch` — `patch --dry-run` + `patch` en la VM, `logstash -t` | Agregar `Version` a ambas ramas — resultado: `Configuration OK` |
| C9 ⚠️ | `sudo systemctl restart logstash` | Recargar el pipeline con `Version` incluido — resultado: `active (running)` |
| C10 | `scripts.sh` — re-corrida de `_exists_:<campo>` sobre los 13 campos (ventana de 30 min, más tráfico acumulado) | Confirmar los 3 despliegues juntos — resultado: `Version` activo (10686 hits, 9 servicios PRO/DEV incluido Sales); `ProcessType`/`Component`/`RequestId`/`SourceContext` siguen activos con conteos mucho mayores; `UserId`/`Category`/los 6 condicionales siguen en 0, sin cambios respecto a C5 |
| C11 | `field-samples-final/` — un mensaje real por servicio (30 min, sin filtro de categoría), los 6 vía Event Hub + Sales | Confirmación individual por servicio, no solo agregada — resultado: ver tabla "Confirmación por servicio" |

## Acciones propuestas

1. ~~Confirmar forma real de los 4 campos siempre-presentes (`UserId`/`ProcessType`/`Component`/`RequestId`) contra tráfico real~~ — **HECHO 2026-08-19.**
2. ~~Redactar el bloque Ruby nuevo, con los dos patrones de guardado (string vacío / clave ausente) y las dos ramas (Event Hub apps + Sales)~~ — **HECHO 2026-08-19.** Aplicado a ambas copias versionadas del pipeline (`cloud-graylog/docs/` y `bots/settings/prod-sfcloud-monitoreo/`), confirmadas sincronizadas salvo las líneas de credenciales ya conocidas.
3. ~~Validar el bloque de forma aislada (sin `logstash` instalado localmente)~~ — **HECHO 2026-08-19.** 4 escenarios simulados, todos correctos.
4. ~~Diferenciar el archivo del repo contra el real de la VM antes de tocarlo~~ — **HECHO 2026-08-19.** Confirmado idéntico salvo credenciales (ver H7 sobre la exposición temporal encontrada y corregida en un archivo local).
5. ~~Generar un patch acotado, aplicarlo en la VM, `logstash -t`, reiniciar el servicio~~ — **HECHO 2026-08-19.** `Configuration OK`, `active (running)`.
6. ~~Validar los 12 campos contra el código fuente real y corregir los nombres de clave incorrectos~~ — **HECHO 2026-08-19** (ver H9). 5 campos corregidos y redesplegados; queda como seguimiento opcional confirmar en una ventana más amplia que `Category` y los 6 condicionales se promueven correctamente cuando el helper correspondiente dispare en producción — no bloquea el cierre, la lógica ya está validada de forma aislada con los nombres reales.
6b. ~~Validar cobertura completa de §3.2 y promover `Version`~~ — **HECHO 2026-08-19** (ver H10). El ticket queda en 13 campos totales, no 12.
7. **(SRE, seguimiento opcional)** Confirmar si algún Graylog Pipeline Rule depende, directa o indirectamente, de alguno de los 12 campos por su ausencia actual — no identificado ninguno durante esta investigación, pero no verificado exhaustivamente.
8. **(SRE)** Actualizar `cloud/docs/graylog-log-fields.md` reflejando el set final de campos planos — incluye también el punto pendiente de GITIN-1883 (acción #9 de ese ticket, sección "Known naming inconsistency"), para no dejarlo duplicado entre dos tickets.
9. **(SRE)** Rotar el `SharedAccessKey` de Event Hub y el `AccountKey` de storage encontrados expuestos en texto plano en un archivo local durante esta sesión (H7) — nunca llegaron a git, pero deben tratarse como potencialmente comprometidos.
10. ~~Reportar/corregir `cloud/docs/devs-log-structure.md`~~ — **HECHO 2026-08-19.** Corregidas §3.3, §3.6, §6.3, §6.4, §6.6, §6.7 y §9 con los nombres reales (`_error_code`/`_recovered`/`_handled`/`_audit_action`/`_audit_outcome`), cada corrección con nota explícita fechada y referenciando este ticket.
11. **(SRE, seguimiento opcional, sin ticket)** `Attempt`/`Operation`/`Action`/`Outcome` — de estos, `Operation` sí fue promovido (ver Tabla §3.2/13 campos); `Attempt`/`Action`/`Outcome` son 3 campos canónicos adicionales documentados en `devs-log-structure.md` §9 (compañeros PascalCase de `_recovered`/`_audit_action`/`_audit_outcome`, llegan vía placeholder de mensaje, no vía scope) que existen en `Properties` pero no fueron promovidos por este ticket ni por ningún otro — ya registrado como fuera de alcance en `graylog-log-fields.md` (sección "Full field list"). No bloquea el cierre de GITIN-1892.
