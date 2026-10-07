**Tags:** SmartCloud, CloudPOS, Azure, Graylog, Terraform, Obserbavilidad

## Resumen

`SFC-PosWasmRelay-PRO` (y su par `SFC-PosWasmRelay-DEV` en menor medida) carecía de un Diagnostic Setting hacia el Event Hub compartido, por lo que su salida de consola no llegaba a Graylog — a diferencia del resto de los App Services y Function Apps ya onboardeados (GITIN-1794/1834/1901/1914). Además, una vez confirmado que sí hay tráfico real fluyendo a través de este relay, se detectó que dos de los ocho campos canónicos requeridos por `devs-log-structure.md` §3.2 (`TraceKey` y `SourceContext`) no se promovían a nivel superior en Graylog para esta fuente en particular, a diferencia de todos los demás servicios ya onboardeados — impidiendo correlacionar una traza de este relay contra el resto del stack vía `TraceKey`. Sistema: SmartFran Cloud / Graylog (`smartfran-graylog-pro`). Detectado y trabajado el 2026-08-24, como continuación proactiva de GITIN-1901/1914 (mismo patrón de onboarding), no por un incidente.

## Tabla resumen

| Campo | Valor |
|---|---|
| Ticket Jira | GITIN-1924 |
| ID alerta | N/A — trabajo proactivo de onboarding |
| Sistema | SmartFran Cloud — `SFC-PosWasmRelay-PRO`/`-DEV`, Graylog (`smartfran-graylog-pro`) |
| Severidad | Media |
| Detectado | 2026-08-24 |
| Resuelto | No cerrado — pendiente confirmar entrega end-to-end en Producción real (ver Hallazgos secundarios) |
| Responsable | Dante Paniagua, SRE |

## Causa raíz

Dos causas independientes, ambas de configuración/diseño, no de una falla puntual:

1. **Sin Diagnostic Setting:** `SFC-PosWasmRelay-PRO` nunca tuvo un `azurerm_monitor_diagnostic_setting` configurado hacia el Event Hub compartido — simplemente no se había hecho, mismo patrón que resolvió GITIN-1901 para `-DEV` y GITIN-1914 para las otras tres Function Apps de PROD.
2. **`TraceKey`/`SourceContext` sin promover:** el relay (`IngestLogs.cs`, GSFC-839) anida las propiedades propias del cliente WASM un nivel más profundo que el resto de los servicios — bajo una clave `EntryProperties` dentro de `Properties` — específicamente para no pisar los campos canónicos que el propio relay agrega (`Service`, `Environment`, `TenantId`, etc.). El pipeline de Logstash compartido (`azure-eventhub-to-graylog.conf`, lógica GITIN-1883/1892) solo lee `Properties` directamente y nunca llega a ese nivel anidado, por lo que `TraceKey`/`SourceContext` quedaban invisibles para búsquedas en Graylog pese a estar presentes en el dato crudo.

## Hallazgos

| # | Hallazgo | Riesgo |
|---|---|---|
| H1 | `SFC-PosWasmRelay-PRO` sin Diagnostic Setting hacia Graylog | Medio |
| H2 | `TraceKey`/`SourceContext` no promovidos a nivel superior para el tráfico de este relay, a diferencia de todos los demás servicios ya onboardeados | Medio |
| H3 | Las reglas de stream nativas de Graylog no permiten combinar "(regla existente) O (Service Y Environment)" dentro de un mismo stream sin romper el aislamiento de los streams dedicados por app — resuelto vía Pipeline Rules en vez de Stream Rules | Bajo |
| H4 | Tráfico real con `Environment:"Production"` observado en Graylog (39 mensajes en 30 días) sin origen confirmado: el usuario confirmó que el código de Producción no está desplegado, pero `ASPNETCORE_ENVIRONMENT` de `SFC-PosWasmRelay-DEV` está confirmado como `Development` — ninguno de los dos ambientes explica limpiamente el dato observado | Medio |
| H5 | La copia de referencia local del pipeline de Logstash (`cloud-graylog/docs/azure-eventhub-to-graylog.conf`) estaba desactualizada respecto a lo efectivamente desplegado en producción | Bajo |
| H6 | ~~El archivo de configuración de Logstash tiene el valor literal `"NO"` en `event_hub_connections`/`storage_connection`~~ — resuelto: sustitución intencional aplicada al traer la copia al repo, para no escribir credenciales reales en el repositorio (regla del proyecto). El archivo real en el VM conserva los valores reales. | Bajo |
| H7 | `TenantId` en el tráfico de este relay tiene un formato distinto (`org_id` de Auth0, ej. `org_g4qPlLbxcJZx5e7U`) al del resto de los servicios (hash opaco de 12 caracteres, ej. `d3186bc6d7b2`) | Bajo |

## Recursos afectados

| Recurso | Detalle |
|---|---|
| `SFC-PosWasmRelay-PRO` | Function App, RG `SmartFran.Cloud.PRO`, sub. SmartIT Cloud (`85c76dea...`) |
| `SFC-PosWasmRelay-DEV` | Function App, RG `SmartFran.Cloud`, sub. Smart IT - Grido (`0190fa7d...`) — solo consultado, no modificado en Azure |
| `smartfran-graylog-pro` | VM — Graylog + Logstash |
| Stream `DEV` | Graylog — nueva regla de enrutamiento vía Pipeline |
| Stream `PROD-Pos-AppServicePlan` | Graylog — nueva regla de enrutamiento vía Pipeline |
| `cloud-graylog/terraform/function_app_pro.tf` | Nuevo recurso `azurerm_monitor_diagnostic_setting.poswasmrelay_pro` |
| `/etc/logstash/conf.d/azure-eventhub-to-graylog.conf` | Parcheado — nuevo bloque de fallback `TraceKey`/`SourceContext` |

## Comandos ejecutados

| # | Comando / Script | Propósito |
|---|---|---|
| C1 | Confirmar existencia de `SFC-PosWasmRelay-PRO` | Validación previa |
| C2 | Confirmar ausencia de Diagnostic Settings previos | Validación previa |
| C3 | Conteo de mensajes Graylog por `Environment` | Investigación (origen de H4) |
| C4 | Fetch de mensaje completo (todos los campos) | Investigación (confirma H2, H4, H7) |
| C5 | ⚠️ Fetch de la configuración real de Logstash en producción | Auditoría (origen de H5) |
| C6 | Confirmar `ASPNETCORE_ENVIRONMENT` en `SFC-PosWasmRelay-DEV` | Investigación (H4) |
| C7 | `terraform plan`, acotado al recurso nuevo | Remediación — previo a apply |
| C8 | ⚠️ `terraform apply` — crea el Diagnostic Setting | Remediación (H1) |
| C9 | ⚠️ Creación de 2 Graylog Pipeline Rules | Remediación (enrutamiento) |
| C10 | ⚠️ Creación del Graylog Pipeline | Remediación (enrutamiento) |
| C11 | Listar conexiones de pipelines a streams antes de modificar | Validación previa (evitar sobrescribir) |
| C12 | ⚠️ Conectar el pipeline al Default Stream | Remediación (enrutamiento) |
| C13 | Verificación de mensaje real ruteado al stream `DEV` | Confirmación post-cambio |
| C14 | ⚠️ Deploy del fix `TraceKey`/`SourceContext` vía `patch` (no overwrite completo) | Remediación (H2) |
| C15 | Validación de sintaxis (`logstash -t`) antes de reiniciar | Validación previa al reinicio |
| C16 | ⚠️ Reinicio de Logstash | Remediación — aplica el fix |
| C17 | Confirmación post-reinicio (`systemctl status`) | Confirmación post-cambio |

Detalle completo en `scripts.sh`.

## Acciones propuestas

1. **Diagnostic Setting de `SFC-PosWasmRelay-PRO`** — completado (Terraform aplicado, `1 added, 0 changed, 0 destroyed`).
2. **Enrutamiento Graylog `Service`+`Environment` → streams `DEV`/`PROD-Pos-AppServicePlan`** — completado vía Pipeline Rules; confirmado funcionando contra tráfico real para el caso `DEV`.
3. **Fix de promoción `TraceKey`/`SourceContext`** — desplegado en el pipeline de Logstash compartido, validado sintácticamente (`logstash -t`); confirmar contra tráfico real una vez se registre la próxima ráfaga de actividad del relay.
4. **Investigar el origen real del tráfico etiquetado `Environment:"Production"`** (H4) — no cerrar este ticket como resuelto en el frente de Producción hasta confirmar de dónde proviene, dado que ni `SFC-PosWasmRelay-PRO` (sin código desplegado) ni `SFC-PosWasmRelay-DEV` (`ASPNETCORE_ENVIRONMENT=Development`) explican el dato tal cual se observó.
5. **Confirmar `ASPNETCORE_ENVIRONMENT` en `SFC-PosWasmRelay-PRO`** una vez se despliegue código real en ese ambiente.
6. **Confirmar enrutamiento a `PROD-Pos-AppServicePlan`** contra tráfico genuino de Producción, una vez el relay esté efectivamente desplegado allí.
7. ~~Investigar el valor `"NO"` en `event_hub_connections`/`storage_connection`~~ — resuelto (H6), sin acción pendiente.
8. **Elevar a desarrollo la discrepancia de formato de `TenantId`** (H7) observada en este tráfico.
9. **Corregir la referencia desactualizada** ("GSFC-839 solo en `dev`, sin código en PRO") en la investigación relacionada `20260824_pos-wasm-logging-graylog-review`.

## Hallazgos secundarios

Ninguno fuera de lo ya listado en Hallazgos — H4, H6 y H7 son hallazgos periféricos al objetivo original del ticket (onboarding de Diagnostic Settings) pero se mantienen en la tabla principal por estar directamente relacionados con la misma fuente de datos investigada.
