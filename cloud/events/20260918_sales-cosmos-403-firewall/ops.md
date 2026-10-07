# GITIN-2083 — [CLOUD] Cosmos DB 403 Forbidden por firewall (cuenta GRIDO)

**Tags:** SmartCloud, Azure

## Resumen

Se reportaron errores HTTP 403 y de conexión vinculados a Cosmos DB ("sales cosmos sales"), detectados el 2026-09-18. La cuenta de Cosmos DB del franchisee GRIDO (`smartfran-cloud-cosmos-pro-3186bc6d7b2`) tenía su firewall configurado sin ninguna de las IPs de salida reales de los App Services y Function Apps que la consumen — ni una regla de VNet ni el bypass de servicios de Azure estaban habilitados. Se confirmó un evento real de bloqueo (49 excepciones `403 Forbidden`, ráfaga de ~2 minutos el 2026-09-18 entre las 21:08 y 21:09:56 UTC) afectando a Business, Person y Orders API. El relevamiento del alcance real mostró que el problema no está limitado a esa ráfaga puntual: de las 14 IPs de salida confirmadas entre todos los servicios que usan Cosmos en esta cuenta (7 App Services + 3 Function Apps), ninguna está permitida por el firewall — cobertura cero, no parcial. La causa raíz está confirmada; la remediación aún no fue elegida por decisión pendiente del usuario.

## Tabla resumen

| Campo | Valor |
|---|---|
| Ticket Jira | [GITIN-2083](https://smartit-ar.atlassian.net/browse/GITIN-2083) |
| ID alerta | — (reporte de usuario, "sales cosmos sales") |
| Sistema | SmartFran Cloud — CosmosDB cuenta GRIDO (`smartfran-cloud-cosmos-pro-3186bc6d7b2`, RG `SmartFran.Cloud.PRO.GRIDO`) |
| Severidad | Alta — cobertura cero del firewall para todo tráfico legítimo, ya con un bloqueo real confirmado en producción |
| Detectado | 2026-09-18 |
| Resuelto | No — causa raíz confirmada, remediación pendiente de decisión (ver Acciones propuestas) |
| Responsable | Dante Paniagua (SRE) |

## Causa raíz

El `ipRules` de la cuenta Cosmos de GRIDO solo contiene 4 entradas ajenas a la infraestructura de SmartFran Cloud (el valor centinela `0.0.0.0` de Azure para acceso desde Portal/Data Explorer, y 3 IPs estáticas tipo oficina/VPN), con `isVirtualNetworkFilterEnabled: false`, `virtualNetworkRules: []` y `networkAclBypass: "None"`. Ninguna de las IPs de salida reales de los App Services (Business, Orders, Person, Platform, Catalog, Sales, y potencialmente Security) ni de los Function Apps que acceden a esta cuenta (`SFC-CodeGenerator-PRO`, `SFC-TicketProcess-PRO`, `SFC-ScheduledJobs-PRO`) está en esa lista — confirmado por lectura directa de la configuración (`az cosmosdb show`), no inferido. No está determinado aún si esto es una regresión reciente o un gap preexistente que recién empezó a manifestarse.

## Hallazgos

| # | Hallazgo | Riesgo |
|---|---|---|
| H1 | 49 excepciones reales `Microsoft.Azure.Cosmos.CosmosException` / `Forbidden (403)` confirmadas en Graylog, tenant GRIDO, Producción, ráfaga de ~2 min (2026-09-18T21:08:00–21:09:56 UTC), afectando `Business.API`, `Person.API` y `Orders.API` | Alto |
| H2 | Causa raíz confirmada por lectura directa del firewall (`az cosmosdb show`): ninguna IP de salida real de los servicios consumidores está en `ipRules`, sin VNet rule ni `networkAclBypass` activo | Alto |
| H3 | Alcance real más amplio que la ráfaga observada: 7 App Services + 3 Function Apps (10 recursos) tienen acceso directo o indirecto (logging) a Cosmos en esta cuenta. De las 14 IPs de salida confirmadas entre todos ellos, 0 están permitidas por el firewall — cobertura cero | Alto |
| H4 | La IP reportada originalmente por el usuario (`20.253.36.226`) se confirmó como IP de salida propia de Sales-PRO — consistente con el reporte original, tras una atribución incorrecta inicial (se la había visto primero en tráfico entrante de POS a Business-API) | Medio |
| H5 | Posible relación (no confirmada) con el pico de CPU investigado en `cloud/events/20260918_sales-cpu-live-metrics-discrepancy/` (GITIN-2073) — los consumers de Service Bus de Sales (`MoneyMovementConsumer`/`StockMovementConsumer`) tienen un circuit breaker de "retry storm" que reintenta continuamente ante fallos sostenidos de Cosmos, lo que un bloqueo de firewall dispararía | Medio (no confirmado) |
| H6 | No determinado si el gap de firewall es una regresión reciente o preexistente — no se revisó aún el historial de cambios de la cuenta Cosmos | Informativo — gap de investigación |

## Recursos afectados

| Recurso | Detalle |
|---|---|
| `smartfran-cloud-cosmos-pro-3186bc6d7b2` (RG `SmartFran.Cloud.PRO.GRIDO`) | Cuenta CosmosDB con firewall sin cobertura real |
| `SmartFran-Cloud-Business-PRO`, `SmartFran-Cloud-Orders-PRO`, `SmartFran-Cloud-Person-PRO` | Afectados en el bloqueo real confirmado del 18/09 |
| `SmartFran-Cloud-Platform-PRO`, `SmartFran-Cloud-Catalog-PRO`, `SmartFran-Cloud-Sales-PRO` | Con acceso directo o indirecto a Cosmos, misma exposición, no capturados en esta ráfaga puntual |
| `SFC-CodeGenerator-PRO`, `SFC-TicketProcess-PRO`, `SFC-ScheduledJobs-PRO` | Function Apps con acceso directo a Cosmos, misma exposición |

## Comandos ejecutados

| # | Comando / Script | Propósito |
|---|---|---|
| C1 | Graylog full-text, intento 1 (descartado) | Búsqueda del mensaje de firewall — el query no filtró realmente (891.990 resultados, todos placeholders genéricos), no usar como referencia |
| C1b | Graylog `firewall AND Cosmos AND NOT message:AppServiceHTTPLogs`, 7 días | Encontró los 49 errores reales de firewall Cosmos |
| C1c | Graylog free-text `"20.253.36.226"`, 7 días | Localizar la IP reportada por el usuario en los logs |

Detalle completo en `cloud/events/20260918_sales-cosmos-403-firewall/scripts.sh`. Nota: los comandos posteriores que confirmaron la causa raíz (`az webapp show --query outboundIpAddresses`/`possibleOutboundIpAddresses` para cada App Service, `az cosmosdb show` sobre la cuenta GRIDO, y el grep sobre `cloud/repo/SmartFran.Cloud` para mapear qué servicios usan Cosmos) no quedaron registrados en `scripts.sh` — solo C1/C1b/C1c (Graylog) lo están.

## Acciones propuestas

1. **(SRE) Pendiente, decisión del usuario** — elegir el mecanismo de remediación entre las 3 opciones documentadas en `investigation.md`: (a) agregar las IPs de salida actuales o el pool completo `possibleOutboundIpAddresses` al `ipRules`, (b) habilitar `networkAclBypass=AzureServices`, o (c) migrar a integración VNet. No se debe actuar unilateralmente sobre este punto.
2. **(SRE) Pendiente** — si se opta por allow-list de IPs, confirmar el pool completo `possibleOutboundIpAddresses` (no solo las activas) para evitar que una rotación de IP de salida vuelva a abrir el gap.
3. **(SRE) Pendiente** — revisar el historial de cambios / activity log de la cuenta Cosmos de GRIDO para determinar si el gap es una regresión reciente o preexistente.
4. **(SRE) Pendiente** — verificar si Sales-PRO y Platform-PRO (con código Cosmos directo confirmado pero no capturados en la ráfaga observada) sufrieron bloqueos 403 en otras ventanas.
5. **(SRE) Pendiente** — actualizar `cloud/docs/infrastructure.md` con la excepción de nombre de cuenta Cosmos de GRIDO (mismo patrón `-pro-<tenant truncado>` ya documentado para WEISS) una vez cerrado el ticket.
6. **(SRE) Pendiente** — confirmar o descartar la relación con el pico de CPU de GITIN-2073 (`cloud/events/20260918_sales-cpu-live-metrics-discrepancy/`) vía los consumers de Service Bus de Sales.
