# Eventos — 20260810_dev-environment-onboarding

## 2026-08-10 — Apertura de ticket

He abierto GITIN-1794 para incorporar el ambiente DEV de SmartFran Cloud al pipeline de Graylog (proyecto `cloud-graylog`, repo separado). He definido el alcance inicial: RG `SmartFran.Cloud`, subscripción `Smart IT - Grido` (`0190fa7d-4ccf-4e3d-beb1-323b5780bfc8`) — ninguno de los dos estaba documentado en `cloud-graylog` (que solo cubría `SmartFran.Cloud.PRO` y `.TEST`, subscripción `SmartIT Cloud`). He entregado los comandos de relevamiento inicial (C1–C3) para ejecutar y pegar de vuelta — no ejecuto comandos Azure directamente.

## 2026-08-10 — Relevamiento inicial (C1–C3)

He recibido el resultado de los tres comandos. C2 confirmó el RG `SmartFran.Cloud` existe en `Smart IT - Grido`, región `eastus2` (metadata del RG). C3 (`az webapp list`) reveló que el RG no aloja un único ambiente DEV sino **33 App Services** en al menos 5 tiers (DEV, DEV2, STG, TEST, POC) sobre 8 dominios, todas en región `East US`, más dos apps sin sufijo de ambiente — anomalía de naming a confirmar. Esto ha cambiado el alcance real del ticket: el pedido original ("ambiente DEV") es más chico que el inventario encontrado.

## 2026-08-10 — Alcance acotado a DEV (sin DEV2)

He confirmado el alcance: solo tier `DEV`, explícitamente sin `DEV2`. Alcance final: 8 apps (`Sales-DEV`, `Pos-DEV`, `Catalog-DEV`, `Platform-DEV`, `Admin-DEV`, `Person-DEV`, `Business-DEV`, `Orders-DEV`). He agregado C4 — releva Diagnostic Settings actuales de las 8 apps DEV, a la espera del resultado.

## 2026-08-10 — C4 pegado: 8 apps DEV sin ningún Diagnostic Setting

Resultado de C4: las 8 apps `*-DEV` no tienen ningún Diagnostic Setting configurado (output vacío para las 8). He revisado `cloud-graylog/terraform/main.tf`, `app_services.tf`, `eventhub.tf` y `variables.tf` para entender el patrón usado en PRO. He encontrado que el provider `azurerm` tenía `subscription_id` fijo a `SmartIT Cloud` — las apps DEV están en otra subscripción, por lo que he agregado un provider aliasado (`azurerm.development`) + `data.azurerm_resource_group.dev` en `main.tf`, variable `dev_resource_group_name` en `variables.tf`, y las 8 apps DEV en el nuevo archivo `cloud-graylog/terraform/app_services_dev.tf` (mismo patrón que PRO: `data` source de solo lectura + `azurerm_monitor_diagnostic_setting`, Terraform nunca gestiona la App Service en sí). No he ejecutado ningún comando `terraform` — he entregado `plan`/`apply` para ejecutar y validar.

## 2026-08-10 — Renombre del provider alias a `development`

He renombrado el provider aliasado de `grido` a `azurerm.development` en `main.tf` y en las 8 referencias de `app_services_dev.tf` — mejor nomenclatura.

## 2026-08-10 — He aclarado el alcance del import Terraform

He confirmado que el enfoque usado (`data` source de solo lectura + `azurerm_monitor_diagnostic_setting` como único recurso gestionado) ya cumple con "solo modificar Diagnostic Settings" — no es un `terraform import` real de las App Services, que las pondría bajo control completo de Terraform (riesgo de que un `destroy` futuro las afecte). No ha hecho falta ningún cambio, el patrón ya existente para PRO cubre este requisito.

## 2026-08-10 — He entregado el comando `terraform plan` (targeted y completo)

He entregado dos variantes de `terraform plan` — completa (`terraform plan -out=tfplan`, evalúa todo el state existente) y con `-target` (acotada a los 8 `azurerm_monitor_diagnostic_setting` nuevos, evita reevaluar VM/red/Event Hub existentes en esta corrida). He recomendado la variante `-target` para esta primera revisión.

## 2026-08-10 — Bloqueo por variable `ssh_public_key`

El plan sin `-target` pidió un valor para `ssh_public_key` (variable de `cloud-graylog/terraform/vm.tf`, usada por la VM de Graylog en producción, sin relación con las apps DEV). He advertido que un valor incorrecto ahí puede forzar el reemplazo de la VM real (`admin_ssh_key` es inmutable en `azurerm_linux_virtual_machine`). He entregado un comando de solo lectura (`az vm show ... --query osProfile.linuxConfiguration.ssh.publicKeys[0].keyData`) para obtener el valor real en vez de adivinarlo, y como alternativa más segura he recomendado seguir usando `-target` (evita que la VM entre en el grafo de recursos de este plan).

## 2026-08-10 — Plan `-target` validado: 8 to add, 0 to change, 0 to destroy

He recibido el resultado del `terraform plan -target` corrido: **8 to add, 0 to change, 0 to destroy** — coincide exactamente con lo esperado (los 8 `azurerm_monitor_diagnostic_setting`), sin tocar ningún recurso existente. He documentado como H7 en el ticket. Pendiente: `apply`.

## 2026-08-10 — Apply confirmado: 8 added, 0 changed, 0 destroyed

He entregado el comando `terraform apply tfplan` con el banner de comando destructivo (crea recursos reales en dos subscripciones, aunque no borra nada). He recibido primero el bloque de outputs del state (VM/red/Event Hub, sin cambios — no confirma nada sobre los 8 recursos nuevos por sí solo) y he pedido específicamente la línea de resumen. He confirmado: **Apply complete! Resources: 8 added, 0 changed, 0 destroyed.** He documentado como H8. Los 8 Diagnostic Settings de las apps DEV quedaron creados, apuntando al Event Hub compartido `app-logs`. He entregado comandos de verificación (métrica `IncomingMessages` del Event Hub + búsqueda directa en Graylog) — pendiente confirmar que los datos realmente llegan antes de crear el stream dedicado de DEV.

## 2026-08-10 — Métrica del Event Hub: tráfico presente pero no atribuible

He recibido el resultado de la métrica `IncomingMessages`: actividad real entre 14:59 y 15:24 (1189 mensajes totales), luego cero hasta las 15:54. He señalado que esta métrica es agregada sobre todo el hub compartido — no distingue tráfico DEV de tráfico PRO (Sales/Business ya fluyen ahí continuamente) — y que no alcanza para confirmar el routing cross-subscription por sí sola. He pedido la búsqueda específica en Graylog por `resourceId` conteniendo un app DEV.

## 2026-08-10 — He aclarado la topología del Event Hub compartido

He confirmado que no hay ningún recurso Event Hub en el RG DEV (`SmartFran.Cloud`) — por diseño. El Diagnostic Setting es un sub-recurso de cada App Service DEV y solo referencia el Event Hub por resource ID completo; el Event Hub real vive enteramente en `SmartFran.Cloud.PRO` (subscripción `SmartIT Cloud`). He explicado por qué el mecanismo de autenticación (SAS authorization rule, no RBAC) hace que cross-subscription no sea un problema estructural aquí — el único constraint real de Azure es que la región coincida (ya cumplido).

## 2026-08-10 — Campos de identificación ya existían, sin necesidad de tocar el pipeline

He revisado `cloud-graylog/docs/azure-eventhub-to-graylog.conf` para agregar un campo de filtro DEV en Graylog y he confirmado que el pipeline ya descompone `resourceId` en `subscription`, `resource_group`, `name`, `type` desde el piloto original — no hace falta ningún cambio de Logstash. He recomendado filtrar por `subscription` (más seguro que `name`/`resourceId` con wildcard, que colisionaría con `-DEV2`).

## 2026-08-10 — Confirmación end-to-end con mensaje real

He recibido un mensaje real de Graylog: `resourceId` → `SMARTFRAN-CLOUD-POS-DEV`, `subscription` → la subscripción DEV, `resource_group` → `SMARTFRAN.CLOUD`, categoría `AppServiceHTTPLogs`, tráfico real de GitHub Actions desplegando `Pos-DEV` vía API Kudu. He confirmado que el routing cross-subscription funciona de punta a punta, no solo que el plan/apply fue válido. He documentado como H9, he cerrado el ítem abierto de H6, y he marcado el paso de verificación como completado en Acciones propuestas. Queda pendiente: crear el stream dedicado de Graylog para DEV.

## 2026-08-10 — Stream de Graylog en pausa

No toco el stream de Graylog por ahora — el equipo de desarrollo está trabajando en mejoras de logging y crear un stream nuevo en este momento podría pisar ese trabajo. He marcado el paso 8 (creación del stream DEV) como en pausa en Acciones propuestas, dejando el criterio de filtro documentado para cuando se retome. He actualizado el estado general del ticket: el alcance técnico de GITIN-1794 (Diagnostic Settings de las 8 apps DEV) está completo y confirmado; solo el stream queda deliberadamente afuera por ahora.

## 2026-08-10 — Reversión de la pausa: he retomado el stream de Graylog

He retomado el trabajo del stream de Graylog, revirtiendo la pausa anterior, para extraer `name:/.*-DEV$/` del index set Default hacia uno nuevo. Esto revierte la decisión de no tocar el stream — he corregido el regex (`.*-DEV$` con ancla de fin, ya que `.*-DEV` sin anclar también matchearía `-DEV2`) y he dado los pasos de UI para crear el index set `DEV` y el stream correspondiente.

## 2026-08-10 — He recomendado valores para el index set DEV

Ante el formulario de creación de index set, he recomendado shards=1 y réplicas=0 (cluster OpenSearch de un solo nodo, confirmado en `cloud-graylog/CLAUDE.md`) y he dejado la decisión de retención abierta, señalando que no tengo visibilidad de la configuración real del index set por defecto para poder espejarla con certeza.

## 2026-08-10 — He diagnosticado dos errores de configuración en el stream DEV

Con los datos de la lista de streams pegados, he identificado dos problemas sucesivos: primero el stream `DEV` apuntaba a `Default index set` en vez del índice `DEV` recién creado (corregido); luego, aun con el índice correcto, la regla del stream seguía sin dar resultados — el badge de cantidad de reglas visible en la lista de streams no mostraba el mismo patrón que los streams PRO. He confirmado en la página de reglas del stream que el tipo configurado era "Match exactly" (comparación literal) en vez de "Match regular expression" — bug real, no un problema de rango de tiempo ni de stream de búsqueda.

## 2026-08-10 — Verificación vía API REST, no UI

He dado comandos `curl` contra la API REST de Graylog (usando el token que se compartió — no lo he escrito en ningún archivo, solo lo he usado en los comandos entregados) para confirmar de forma inequívoca el estado real, evitando seguir interpretando texto de UI copiado/pegado que venía siendo ambiguo. He recibido la confirmación: stream `DEV` con `index_set_id` correcto (índice `DEV`, prefix `dev_`) y una única regla `field: name`, `type: 2` (REGEX), `value: .*-DEV$` — ambos problemas quedaron efectivamente corregidos. He documentado como H10, he marcado el paso 8 de Acciones propuestas como completado, y he agregado el paso 9 (confirmar tráfico real ruteado) como pendiente.

## 2026-08-10 — "Unknown field: name" explicado

He recibido un warning de Graylog Search ("Unknown field: name") al buscar `name:/.*-DEV/` dentro del stream `DEV`. He confirmado que era el síntoma esperado de un índice recién creado sin documentos aún — el campo no existe en el mapping hasta que llegue el primer mensaje, no un problema de configuración. He sugerido generar tráfico real con un `curl` GET contra un endpoint público de `Pos-DEV` para completar la verificación sin depender de tráfico orgánico. He actualizado el paso 9 de Acciones propuestas con esta nota.

## 2026-08-10 — Tercer bug: `$` no es ancla válida en Lucene regex

He recibido un dato clave: `name:/.*-DEV$/` no devuelve nada en Default Stream, pero `name:/.*-DEV/` (sin ancla) sí. He identificado la causa: las queries `regexp` de Lucene (motor detrás de OpenSearch/Graylog) ya hacen fullmatch implícito contra el término completo — no soportan `^`/`$` como anclas, los tratan como caracteres literales. El valor guardado en la regla del stream (`.*-DEV$`) nunca iba a matchear nada real, ni en el stream ni en ninguna búsqueda manual. He documentado como H11 y he corregido el valor de la regla a `.*-DEV` (sin ancla, sigue siendo seguro contra `-DEV2` por el fullmatch implícito) vía `PUT /streams/{id}/rules/{id}` en la API REST. He marcado el paso 9 de Acciones propuestas como completado y he agregado el paso 10 (confirmar tráfico real) como el único pendiente restante.

## 2026-08-10 — Verificación final: 187 documentos en el índice DEV

He confirmado que la corrección de la regla quedó guardada (`GET /streams/.../rules`: `value: ".*-DEV"`, `type: 2`) y que el stream no estaba pausado (`disabled: false`, `remove_matches_from_default_stream: true`). Con eso confirmado, he pedido generar tráfico de prueba real (`curl` GET a `Pos-DEV`, respondió 200) y esperar unos minutos. He recibido la confirmación final: el index set `DEV` ya muestra 187 documentos, 580 KiB — el routing end-to-end funciona de punta a punta. He documentado como H12, he marcado el paso 10 de Acciones propuestas como completado y he actualizado el estado general del ticket a completo. Queda pendiente solo el cierre formal en Jira.

## 2026-08-10 — Último red herring: rango de tiempo en la búsqueda

He recibido un reporte de que buscar sin ningún filtro dentro del stream `DEV` seguía sin mostrar nada, pese a los 187 documentos confirmados en el index set. He descartado un bug de routing dado que el conteo de documentos ya probaba que los datos existían, y he señalado que era casi con certeza el rango de tiempo del buscador (mismo patrón que ya había aparecido antes en esta misma investigación). He confirmado que ampliar el rango resolvió la búsqueda. He actualizado el paso 10 de Acciones propuestas con esta nota final — GITIN-1794 queda técnicamente completo, solo falta el cierre formal en Jira.

## 2026-08-10 — He migrado ticket y eventos a este repo (`bots/cloud/`)

A pedido explícito, he movido el seguimiento de GITIN-1794 de `cloud-graylog/operations/events/20260810_dev-environment-onboarding/` a este folder — el código de infraestructura (Terraform) sigue viviendo en `cloud-graylog`, pero el ticket, el log de eventos y el `investigation.md` viven acá. He actualizado las referencias cruzadas en `cloud-graylog/CLAUDE.md` y `docs/architecture.md` para apuntar al ticket Jira en vez de a la ruta local que ya no existe en ese repo.

## 2026-08-11 — Corrección de tiempo verbal en todo el archivo

Recibí la observación de que este archivo completo usaba pretérito indefinido ("Abrí", "Confirmé", "Recibí") en vez del pretérito perfecto compuesto ("He abierto", "He confirmado", "He recibido") que exige la convención de voz de este proyecto. He reescrito el archivo completo con el tiempo verbal correcto — el chequeo grep que venía corriendo después de cada edición solo detecta marcadores de tercera persona/voz impersonal, nunca tiempo verbal, por lo que esta clase de error pasó sin detectar en las ~20 entradas anteriores.
