# Eventos — 20260825_webapps-console-app-http-logs-graylog

## 2026-08-25 18:50 — Relevamiento de estado vivo en PRO

**Comando:** C1 — Diagnostic Settings, 8 apps PRO
**Resultado:**
He confirmado que `Admin-PRO`, `Platform-PRO`, `Catalog-PRO` y `Pos-PRO` ya tenían habilitadas más categorías que las declaradas en Terraform (drift), mientras que `Business-PRO`, `Person-PRO`, `Orders-PRO` y `Sales-PRO` sólo tenían `AppServiceConsoleLogs` en su Diagnostic Setting apuntando al Event Hub. También he encontrado, en `Business-PRO`/`Person-PRO`/`Sales-PRO`, una segunda Diagnostic Setting no gestionada por Terraform, con nombre mal formado (espacio inicial), apuntando únicamente a un Log Analytics Workspace en una suscripción hasta ahora no documentada.

## 2026-08-25 18:52 — Confirmación de alcance DEV en ambas suscripciones

**Resultado:**
He confirmado, vía scan de la suscripción SmartIT Cloud, que no existe ningún App Service `-DEV` fuera de la suscripción Smart IT - Grido. He relevado el estado de las 8 apps DEV y confirmado que coincide exactamente con lo declarado en `app_services_dev.tf` — sólo `AppServiceConsoleLogs`, sin drift.

## 2026-08-25 19:05 — Edición de Terraform y generación del plan

**Comando:** C4 — `terraform plan` (scoped, 16 recursos)
**Resultado:**
Plan: 0 to add, 16 to change, 0 to destroy.

He agregado `AppServiceAppLogs` y `AppServiceHTTPLogs` a las 16 Diagnostic Settings (8 PRO + 8 DEV) en `cloud-graylog/terraform/app_services.tf` y `app_services_dev.tf`, siguiendo la decisión de normalizar los 4 App Services PRO con drift a exactamente las 3 categorías pedidas por este ticket, sin preservar las categorías adicionales no solicitadas.

## 2026-08-25 19:08 — Verificación del plan sin colapsar bloques

**Comando:** C5 — `terraform show -json`
**Resultado:**
He confirmado que el estado `after` de los 16 recursos contiene exactamente `AppServiceAppLogs`/`AppServiceConsoleLogs`/`AppServiceHTTPLogs`, sin ninguna categoría adicional — el resumen en texto plano del plan colapsaba esta información y no permitía confirmarlo directamente.

## 2026-08-25 19:12 — Apply

**Comando:** C6 — `terraform apply`
**Resultado:**
Apply complete! Resources: 0 added, 16 changed, 0 destroyed.

He aplicado el cambio sobre los 16 recursos sin errores, coincidiendo exactamente con lo planeado.

## 2026-08-25 19:31 — Falsa alarma de corte total de ingesta

**Comando:** C8 — Métrica `IncomingMessages`, Event Hub
**Resultado:**
La métrica reportó `0.0` de forma sostenida durante varias lecturas consecutivas, tras un pico de tráfico normal inmediatamente posterior al apply.

He considerado seriamente revertir el cambio ante la posibilidad de un corte real de entrega hacia Graylog para las 16 apps.

## 2026-08-25 19:38 — Descarte de throttling como causa

**Comando:** C9 — Métrica `ThrottledRequests`, Event Hub
**Resultado:**
`0.0` en toda la ventana verificada.

He descartado el throttling por capacidad del Event Hub como causa de la lectura en cero.

## 2026-08-25 19:41 — Confirmación de que la caída fue una falsa alarma

**Comando:** C11 — Búsqueda Graylog, conteo total últimos 30 min
**Resultado:**
`total_results: 109414`, con el mensaje más reciente prácticamente en tiempo real respecto del momento de la consulta.

He confirmado que Graylog nunca dejó de recibir mensajes durante la ventana en la que la métrica de Azure Monitor marcaba cero — la métrica `IncomingMessages` de este namespace no es confiable para este tipo de verificación y no debe usarse sola en próximas validaciones de este proyecto.

## 2026-08-25 19:42 — Confirmación de entrega de la nueva categoría

**Comando:** C12 — Búsqueda Graylog, `AppServiceHTTPLogs` en Business-PRO
**Resultado:**
Mensajes reales y recientes con detalle completo de request HTTP (`CsUriStem`/`CsMethod`/`ScStatus`), categoría `AppServiceHTTPLogs`.

He confirmado la entrega end-to-end de la categoría agregada por este ticket para `Business-PRO`. No he verificado individualmente `AppServiceAppLogs` ni el resto de las 7 apps restantes de la misma forma — lo he dejado como pendiente de cierre si se requiere mayor rigurosidad.
