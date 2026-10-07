# Eventos — 20260824_poswasmrelay-pro-graylog

## 2026-08-24 09:15 — Confirmación de recurso y ausencia de Diagnostic Settings previos

**Comando:** C1/C2 — `az functionapp list` / `az monitor diagnostic-settings list`
**Resultado:**
`SFC-PosWasmRelay-PRO` existe (RG `SmartFran.Cloud.PRO`, sub. SmartIT Cloud, `functionapp,linux`, `Running`), sin Diagnostic Settings previos.

He confirmado que el recurso existe exactamente donde lo esperaba por analogía con GITIN-1914, y que no hay ningún Diagnostic Setting previo que pueda entrar en conflicto con el nuevo.

## 2026-08-24 09:25 — Diagnostic Setting de SFC-PosWasmRelay-PRO aplicado

**Comando:** C7/C8 — `terraform plan` / `terraform apply gitin-1924.tfplan`
**Resultado:**
`Apply complete! Resources: 1 added, 0 changed, 0 destroyed.`

He agregado el bloque `azurerm_monitor_diagnostic_setting.poswasmrelay_pro` a `function_app_pro.tf` siguiendo el mismo patrón que `poswasmrelay_dev` (GITIN-1901), y lo he aplicado acotado con `-target` para no tocar el resto del drift ya conocido del repo.

## 2026-08-24 10:10 — Enrutamiento Graylog Service+Environment implementado vía Pipeline Rules

**Comando:** C9/C10/C11/C12 — creación de 2 Pipeline Rules, 1 Pipeline, y conexión al Default Stream
**Resultado:**
Pipeline `6a8c612d4814bcaed31a570b` conectado al Default Stream junto al pipeline mutable ya existente (`6a7f29c54814bcaed30c7f9b`), omitiendo el pipeline inmutable `Default Routing`.

He optado por Pipeline Rules en vez de Stream Rules porque los streams `DEV`/`PROD-Pos-AppServicePlan` ya tienen su propia regla dedicada por `name`, y Graylog no permite combinar esa regla con una condición `Service` Y `Environment` dentro del mismo stream sin romper su aislamiento. Antes de conectar he listado las conexiones existentes para no sobrescribir el pipeline que ya estaba activo en el Default Stream.

## 2026-08-24 10:28 — Enrutamiento DEV confirmado contra tráfico real

**Comando:** C13 — búsqueda de mensajes recientes `Service:"smartfran-pos-wasm"`
**Resultado:**
Mensajes posteriores a la conexión muestran `streams: ["000000000000000000000001", "6a7a1b8a34e7b9a985f43cbc"]` (Default + `DEV`, confirmado por título), indexados en `dev__6`.

He confirmado el enrutamiento funcionando de punta a punta para el caso `Environment:"Development"`. El caso `Production` queda pendiente de confirmación equivalente por falta de tráfico real en esa condición durante la sesión.

## 2026-08-24 13:40 — Auditoría de campos promovidos en Graylog para este relay

**Resultado:**
7 de los 8 campos canónicos de `devs-log-structure.md` §3.2 están promovidos a nivel superior para este relay (`Service`, `Environment`, `TenantId`, `ProcessType`, `Component`, `Version`, y `UserId` correctamente vacío). `TraceKey` y `SourceContext` no lo están — quedan anidados bajo `Properties.EntryProperties`.

He documentado el hallazgo en `cloud/docs/graylog-log-fields.md`, incluyendo que el mecanismo de promoción actual funciona por casualidad (la forma cruda del mensaje de este relay coincide con la rama de Sales, no con la de las apps de Event Hub) y no por ningún cambio hecho específicamente para esta fuente.

## 2026-08-24 15:30 — Sincronización de la copia local del pipeline de Logstash y hallazgo de anomalías

**Comando:** C5/C6 — fetch SSH de la configuración real / `az functionapp config appsettings list`
**Resultado:**
La copia local (`cloud-graylog/docs/azure-eventhub-to-graylog.conf`) estaba desactualizada. Al re-sincronizarla he encontrado que `event_hub_connections`/`storage_connection` tienen el valor literal `"NO"` en el archivo en disco — no son credenciales reales ni los placeholders originales.

He descartado que esto sea el pipeline funcionando doblemente duplicado, como había interpretado en un primer momento leyendo mal el diff — al releer el archivo completo he confirmado que cada bloque aparece una sola vez. La anomalía real que queda es el valor `"NO"` en las cadenas de conexión, sin causa confirmada.

## 2026-08-24 15:54 — Fix de promoción TraceKey/SourceContext desplegado

**Comando:** C14/C15/C16/C17 — `patch` + `logstash -t` + `systemctl restart logstash` + `systemctl status`
**Resultado:**
`Configuration OK` en la validación previa. Tras el reinicio, `systemctl status` muestra `active (running)`, arranque limpio a las 15:54:09 UTC.

He aplicado el cambio mediante un diff unificado acotado (`patch -p1`, un solo hunk, cero líneas eliminadas) en vez de sobrescribir el archivo completo, específicamente para no tocar la sección de credenciales de entrada dado el hallazgo del valor `"NO"`. He validado sintaxis antes de reiniciar, siguiendo la convención del proyecto. Falta confirmar el fix contra tráfico real posterior al reinicio — no he tenido actividad del relay en la ventana verificada.

## 2026-08-24 (sesión posterior) — Corrección: origen del tráfico "Production" sin explicación confirmada

**Resultado:**
He registrado que el código de Producción todavía no está desplegado — solo Desarrollo. Al re-verificar `ASPNETCORE_ENVIRONMENT` de `SFC-PosWasmRelay-DEV` he confirmado que está en `Development`, no vacío — por lo que tampoco explica limpiamente por qué los 39 mensajes observados llegaron etiquetados `Environment:"Production"`.

He retirado de `investigation.md` la afirmación de que la entrega end-to-end a Producción estaba confirmada, y he dejado registrado este punto como una contradicción real sin resolver, no como un hallazgo cerrado.

## 2026-08-24 (sesión posterior) — Anomalía "NO" en cadenas de conexión: resuelta

**Resultado:**
El valor `"NO"` en `event_hub_connections`/`storage_connection` de la copia local no corresponde a un problema del archivo real en el VM: es una sustitución intencional aplicada al traer la copia a este repositorio, para no escribir credenciales reales en el repo (regla del proyecto). El archivo real desplegado conserva los valores reales.

He corregido H6 en `investigation.md` y en `ops.md`, marcándolo como resuelto en vez de anomalía pendiente.
