**Tags:** SmartCloud, CloudPOS, Performance, PROD

## Resumen

Canning (sucursal del tenant WEISS) reporta demoras en POS al tocar "Cobrar Orden" (transición NUEVO → COBRADO) y en "Anular Venta", con esperas de hasta ~19 segundos sobre una acción que debería resolverse casi instantáneamente. La investigación descarta CosmosDB, Sales-PRO/Business-PRO/Catalog-PRO y Service Bus como causa — dos capturas HAR independientes sobre el terminal POS real de Canning, más el trazado del código fuente del cliente POS, ubican la causa raíz del lado cliente: la generación de la vista previa del ticket imprimible (`html2canvas`, sin timeout y con dependencias de CDNs externos) bloquea la UI del lado del navegador después de que el backend ya respondió. Esta es una corrección de desarrollo, no un cambio de infraestructura Azure.

## Tabla resumen

| Campo | Valor |
|---|---|
| Ticket Jira | GITIN-1917 |
| ID alerta | — (reporte directo, no alerta automática) |
| Sistema | SmartFran Cloud — POS (Blazor WASM), Sales-PRO |
| Severidad | Media — afecta la experiencia de caja en Canning (WEISS), sin pérdida de datos ni errores de backend |
| Detectado | 2026-08-23 (reportado por Canning; el patrón de latencia en `Sale/Close` también aparece en telemetría del 2026-08-22) |
| Resuelto | Pendiente — causa raíz identificada, corrección pendiente en Desarrollo |
| Responsable | SRE (investigación) / Desarrollo (corrección) |

## Causa raíz

La función `getBase64()` (`Source/Pos/SmartFran.Cloud.Pos/SmartFran.Cloud.Pos.Wasm/wwwroot/js/clientPrint.js`), invocada desde `Sale.razor.cs:Print()` en todo cierre de venta (incondicionalmente, sin importar si se solicitó factura o si la venta se cancelará después), renderiza la vista previa del ticket vía `html2canvas` con `useCORS: true` — lo que hace que la propia librería solicite cada imagen y fuente referenciada en el DOM clonado (logo, `LogoTicket`, fuentes de Google Fonts, avatares de gravatar/Auth0) como parte del renderizado del canvas — y con `logging: true` (logging de debug activo en producción). La llamada no tiene ningún timeout: si algún recurso externo tarda en responder, la espera queda sin cota. La llamada HTTP `Sale/Close` en sí se despacha del lado cliente de forma fire-and-forget (nunca se espera su resultado), por lo que la demora percibida por el cajero no corresponde al backend — confirmado con dos capturas HAR reales sobre el terminal de Canning, donde el backend respondió en ~1 segundo en ambos casos.

## Hallazgos

| # | Hallazgo | Riesgo |
|---|---|---|
| H1 | Causa raíz: `getBase64()`/`html2canvas` sin timeout, con dependencia de recursos de CDNs externos (Google Fonts, gravatar, Auth0), ejecutada en cada cierre de venta | Alto |
| H2 | `Sale/Close` se despacha fire-and-forget del lado cliente — la demora visible en pantalla no corresponde a la llamada al backend | Informativo |
| H3 | Telemetría de servidor del 2026-08-22 muestra latencia máxima real en `Sale/Close` (hasta 13.5s) correlacionada con una cadena de llamadas sincrónicas a Business-PRO y Catalog-PRO (`StockMovementCreator`) — hallazgo independiente, no reconciliado con H1, requiere seguimiento propio | Medio |
| H4 | App Insights (`SmartFran-Cloud-Sales-PRO_new`) captura solo ~2.3% del tráfico real de Sales-PRO frente a las métricas de plataforma del App Service — gap de sampling severo, específico de este servicio | Medio |
| H5 | La identidad usada para consultas no tiene el rol de datos App Configuration Data Reader/Owner sobre `SmartFran-Cloud-Settings-PRO` (403 con body vacío) — además, la CLI de Azure falla con un `JSONDecodeError` en lugar de mostrar el error real | Bajo |
| H6 | No verificado en esta sesión si "Anular Venta" (`Sale/Cancel`) pasa por el mismo camino de renderizado de ticket que H1 — permanece abierto | Medio |

## Recursos afectados

| Recurso | Detalle |
|---|---|
| `SmartFran-Cloud-Pos-PRO` (App Service) | Cliente Blazor WASM — `Sale.razor.cs`, `clientPrint.js` |
| `SmartFran-Cloud-Sales-PRO` (App Service) | Backend de `Sale/Close`/`Sale/Cancel` — descartado como causa raíz, pero parte de H3 |
| Tenant WEISS, sucursal Canning | Sucursal afectada por el reporte original |
| Recursos externos (fuera de Azure) | `fonts.googleapis.com`, `fonts.gstatic.com`, `s.gravatar.com`, `cdn.auth0.com` — dependencias del renderizado del ticket |

## Comandos ejecutados

Ver `scripts.sh` en este mismo directorio de evento.

| # | Comando / Script | Propósito |
|---|---|---|
| C1 | `az appconfig kv show` (organizations) | Resolución de tenant CAC/Canning — bloqueado por permisos (H5) |
| C2 | `curl` REST directo a App Configuration | Confirmación del 403 vacío, bypass del bug de la CLI (H5) |
| C3 | `az monitor app-insights query` (Sales-PRO_new) | Intento inicial de telemetría por operación — vacío (H4) |
| C4 | `az monitor metrics list` (Sales-PRO, plataforma) | Métricas de respuesta/requests/errores del App Service |
| C5 | `az monitor metrics list` (CosmosDB, 429) | Verificación de throttling — descartado |
| C6 | `az monitor log-analytics query` (AppRequests, workspace directo) | Desglose real por operación, bypass del gap de H4 |
| C7 | `git fetch`/`checkout main`/`diff origin/dev origin/main` | Verificación de rama del código fuente contra PRO real |
| C8 | Análisis local de dos capturas HAR (navegador, terminal real de Canning) | Identificación de la causa raíz (H1) |

## Acciones propuestas

1. (Dev) Agregar un timeout a la llamada `html2canvas`/`getBase64` en `clientPrint.js` para que un recurso externo lento degrade de forma controlada (por ejemplo, imprimir sin el logo) en lugar de bloquear "Cobrar Orden" sin límite de tiempo.
2. (Dev) Quitar `logging: true` de la configuración de `html2canvas` en producción.
3. (Dev) Eliminar la dependencia de recursos externos (Google Fonts, gravatar, avatares de Auth0) en el template del ticket imprimible — auto-hospedar fuentes e imágenes para sacar el renderizado del ticket de la exposición a CDNs de terceros.
4. (Dev) Verificar si "Anular Venta" (`Sale/Cancel`) pasa por el mismo código de renderizado de ticket que "Cobrar Orden" (H6) — si es así, la misma corrección resolvería ambos síntomas reportados; si no, "Anular Venta" requiere su propio análisis.
5. (SRE, seguimiento no bloqueante) Repetir la medición de métricas de Business-PRO/Catalog-PRO contra la ventana correcta para cerrar H3 de forma independiente del fix de H1.
6. (SRE, seguimiento no bloqueante) Solicitar el rol App Configuration Data Reader/Owner sobre `SmartFran-Cloud-Settings-PRO` para destrabar futuras lecturas del key `organizations` (H5).

## Hallazgos secundarios

- **H4** (gap de sampling ~97% en App Insights para Sales-PRO) y **H5** (permisos de App Configuration + bug de la CLI) quedan fuera del alcance de este ticket — ambos ameritan seguimiento propio.
