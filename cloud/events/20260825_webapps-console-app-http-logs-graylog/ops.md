# GITIN-1937 — Habilitar Console/Application/HTTP Logs para todos los Web Apps de SmartFran Cloud hacia Graylog

**Tags:** `SmartCloud`, `Azure`, `Graylog`, `Terraform`, `Obserbavilidad`, `PROD`

## Resumen

Los 8 App Services compartidos de SmartFran Cloud (PRO y DEV, 16 recursos en total) sólo enviaban la categoría `AppServiceConsoleLogs` hacia Graylog vía Diagnostic Settings — reducción aplicada de forma uniforme por GITIN-1882. Esto dejaba fuera del pipeline el detalle de nivel HTTP (método, URI, status code, latencia) y el detalle de aplicación (`AppServiceAppLogs`), limitando la observabilidad disponible en Graylog al log de consola/CLEF únicamente. Se solicitó agregar `AppServiceAppLogs` y `AppServiceHTTPLogs` para los 8 Web Apps, cubriendo tanto PRO como DEV. Se actualizó y aplicó el Terraform correspondiente en `cloud-graylog/terraform/` (`app_services.tf` y `app_services_dev.tf`) para las 16 Diagnostic Settings, y se confirmó la llegada real de mensajes `AppServiceHTTPLogs` a Graylog post-aplicación.

Durante la investigación previa a implementar el cambio se detectó drift entre el estado real en Azure y el código Terraform en 4 de los 8 App Services PRO (`Admin`/`Platform`/`Catalog`/`Pos`), que ya tenían categorías adicionales habilitadas manualmente sin reflejo en el código. Se decidió, junto con el solicitante, normalizar los 8 App Services PRO a exactamente las 3 categorías pedidas por este ticket, dejando que `apply` recorte las categorías adicionales no solicitadas.

## Tabla resumen

| Campo | Valor |
|---|---|
| Ticket Jira | [GITIN-1937](https://smartit-ar.atlassian.net/browse/GITIN-1937) |
| ID alerta | N/A — solicitud directa, no originada por alerta |
| Sistema | SmartFran Cloud — App Services (PRO + DEV) → Event Hub → Graylog |
| Severidad | Baja — mejora de observabilidad planificada, no incidente productivo |
| Detectado | N/A |
| Resuelto | 2026-08-25 |
| Responsable | Dante Paniagua, SRE |

## Causa raíz

Todas las Diagnostic Settings de los 8 Web Apps (PRO y DEV) fueron reducidas a únicamente `AppServiceConsoleLogs` por GITIN-1882 ("verbosity reduction"), sin que esa reducción fuera revertida en ningún ticket posterior. Además, 4 de los 8 App Services PRO (`Admin`/`Platform`/`Catalog`/`Pos`) tenían categorías adicionales habilitadas directamente en Azure Portal por fuera de Terraform, sin que ese estado quedara reflejado en el código — un `terraform apply` sobre el código previo a este ticket hubiera revertido silenciosamente esas 4 apps a solo Console.

## Hallazgos

| # | Hallazgo | Riesgo |
|---|---|---|
| H1 | Drift confirmado entre Terraform y estado real en Azure para `Admin-PRO`/`Platform-PRO`/`Catalog-PRO`/`Pos-PRO`: tenían entre 7 y 9 categorías habilitadas en vivo mientras el código sólo declaraba `AppServiceConsoleLogs`. Resuelto como parte de este ticket — Terraform ahora declara exactamente las 3 categorías solicitadas para estos 4 recursos. | Medio |
| H2 | `AppServiceConsoleLogs` está configurada pero es inerte en `Sales` y `Pos` (PRO y DEV) — limitación de plataforma para App Services Windows/.NET, ya root-causeada en GITIN-1811. No corregible desde este ticket. | Bajo |
| H3 | Configuraciones de Diagnostic Settings duplicadas y no gestionadas por Terraform en `Business-PRO`/`Person-PRO`/`Sales-PRO` (nombre con typo de espacio inicial), apuntando únicamente a un Log Analytics Workspace en una suscripción no documentada previamente (`d6ab1add-4bc8-40b0-8cf8-e7291f7171b0`). No apuntan al Event Hub de Graylog. No modificadas en este ticket. | Bajo |
| H4 | `docs/infrastructure.md` contenía una afirmación desactualizada ("`AppServiceHTTPLogs` confirmado funcionando en DEV, GITIN-1794") que dejó de ser cierta desde que GITIN-1882 redujo la configuración DEV a solo Console. Corregida como parte del cierre de este ticket. | Bajo |
| H5 | Falsa alarma de corte total del pipeline: la métrica `IncomingMessages` del namespace de Event Hub reportó `0.0` durante ~30-48 minutos post-`apply`, sugiriendo un corte total de entrega. Se descartó throttling (`ThrottledRequests` en `0.0`) y se confirmó vía búsqueda directa en Graylog que el pipeline nunca dejó de recibir mensajes (109.414 mensajes en la misma ventana de 30 minutos). La métrica de Azure Monitor no es confiable para este tipo de verificación en este recurso. | Bajo |

## Recursos afectados

| Recurso | Suscripción | Resource Group |
|---|---|---|
| `SmartFran-Cloud-Business-PRO` | SmartIT Cloud (`85c76dea...`) | `SmartFran.Cloud.PRO` |
| `SmartFran-Cloud-Admin-PRO` | SmartIT Cloud | `SmartFran.Cloud.PRO` |
| `SmartFran-Cloud-Platform-PRO` | SmartIT Cloud | `SmartFran.Cloud.PRO` |
| `SmartFran-Cloud-Person-PRO` | SmartIT Cloud | `SmartFran.Cloud.PRO` |
| `SmartFran-Cloud-Catalog-PRO` | SmartIT Cloud | `SmartFran.Cloud.PRO` |
| `SmartFran-Cloud-Orders-PRO` | SmartIT Cloud | `SmartFran.Cloud.PRO` |
| `SmartFran-Cloud-Sales-PRO` | SmartIT Cloud | `SmartFran.Cloud.PRO` |
| `SmartFran-Cloud-Pos-PRO` | SmartIT Cloud | `SmartFran.Cloud.PRO` |
| `SmartFran-Cloud-Business-DEV` | Smart IT - Grido (`0190fa7d...`) | `SmartFran.Cloud` |
| `SmartFran-Cloud-Admin-DEV` | Smart IT - Grido | `SmartFran.Cloud` |
| `SmartFran-Cloud-Platform-DEV` | Smart IT - Grido | `SmartFran.Cloud` |
| `SmartFran-Cloud-Person-DEV` | Smart IT - Grido | `SmartFran.Cloud` |
| `SmartFran-Cloud-Catalog-DEV` | Smart IT - Grido | `SmartFran.Cloud` |
| `SmartFran-Cloud-Orders-DEV` | Smart IT - Grido | `SmartFran.Cloud` |
| `SmartFran-Cloud-Sales-DEV` | Smart IT - Grido | `SmartFran.Cloud` |
| `SmartFran-Cloud-Pos-DEV` | Smart IT - Grido | `SmartFran.Cloud` |
| `smartfran-graylog-evhns-pro` (Event Hub, hub `app-logs`) | SmartIT Cloud | `SmartFran.Cloud.PRO` |

## Comandos ejecutados

| # | Comando / Script | Propósito |
|---|---|---|
| C1 | Diagnostic Settings — 8 apps PRO | Relevar estado vivo de las 3 categorías en PRO |
| C2 | Scan `-DEV` en suscripción SmartIT Cloud | Confirmar que no existen App Services DEV fuera de la suscripción Grido |
| C3 | Diagnostic Settings — 8 apps DEV | Relevar estado vivo de las 3 categorías en DEV |
| C4 | `terraform plan` (scoped, 16 recursos) | ⚠️ Generar plan de cambio para las 16 Diagnostic Settings |
| C5 | `terraform show -json` | Verificar estado post-cambio exacto por recurso, sin colapsar bloques |
| C6 | `terraform apply` | ⚠️ Aplicar las 16 Diagnostic Settings actualizadas |
| C7 | Diagnostic Settings — Business-PRO (post-apply) | Confirmar que el recurso quedó sano tras el apply |
| C8 | Métrica `IncomingMessages` — Event Hub | Verificar ingreso de mensajes al Event Hub (generó falsa alarma, ver H5) |
| C9 | Métrica `ThrottledRequests` — Event Hub | Descartar throttling como causa de la falsa alarma |
| C10 | Activity Log — RG `SmartFran.Cloud.PRO` | Descartar otros cambios concurrentes en la ventana de la falsa alarma |
| C11 | Búsqueda Graylog — conteo total últimos 30 min | Confirmar que Graylog seguía recibiendo mensajes con normalidad |
| C12 | Búsqueda Graylog — `AppServiceHTTPLogs` en Business-PRO | Confirmar entrega real de la nueva categoría agregada por este ticket |

Detalle completo en `scripts.sh` (este directorio).

## Acciones propuestas

1. **[Completado]** Actualizar `cloud-graylog/terraform/app_services.tf` y `app_services_dev.tf` agregando `AppServiceAppLogs` y `AppServiceHTTPLogs` a las 16 Diagnostic Settings (8 PRO + 8 DEV), normalizando también las 4 apps PRO con drift a exactamente las 3 categorías solicitadas.
2. **[Completado]** Aplicar el cambio (`terraform apply`) y confirmar que las 16 Diagnostic Settings quedaron en el estado esperado.
3. **[Completado]** Confirmar en Graylog la llegada real de mensajes `AppServiceHTTPLogs` para `Business-PRO`.
4. **[Pendiente]** Verificar puntualmente la entrega de `AppServiceAppLogs` y del resto de las 7 apps restantes de forma individual, si se requiere mayor rigurosidad de cierre.
5. **[Completado]** Corregir `docs/infrastructure.md` (afirmación desactualizada sobre `AppServiceHTTPLogs` en DEV).
6. **[Pendiente, fuera de alcance]** Decidir qué hacer con las 3 Diagnostic Settings duplicadas y no gestionadas por Terraform en `Business-PRO`/`Person-PRO`/`Sales-PRO` (H3) — no forman parte de este ticket, se deja como candidato a limpieza en un ticket aparte.

## Hallazgos secundarios

- **H1 (drift Terraform/Azure)** y **H5 (falsa alarma de métrica)** están detallados arriba — ambos resueltos/descartados dentro de este mismo ticket, no requieren seguimiento adicional.
- **H3 (configuraciones duplicadas no gestionadas)** queda como candidato a un ticket de limpieza aparte — no bloquea el cierre de GITIN-1937.
