# Eventos — 20260823_pos-salesorder-delay-cac

## 2026-08-23 13:00 — Apertura de la investigación y resolución de tenant

He abierto la investigación a partir del reporte de demora en POS al tocar "Cobrar Orden" (transición NUEVO → COBRADO) y en "Anular Venta". He identificado que "CAC" es la abreviatura usada para la sucursal Canning, dentro del tenant WEISS (ya onboardeado y documentado) — no se trata de un tenant nuevo ni de un gap de onboarding.

## 2026-08-23 13:10 — Intento de lectura de `organizations` en App Configuration

**Comando:** C1 — `az appconfig kv show` sobre `SmartFran-Cloud-Settings-PRO`
**Resultado:**
`JSONDecodeError` en la CLI, sin mensaje de error legible.

He determinado que la CLI está fallando al intentar parsear como JSON una respuesta de error vacía, en lugar de mostrar el error real.

## 2026-08-23 13:20 — Confirmación del gap de permisos vía REST directo

**Comando:** C2 — `curl` con token AAD contra el endpoint de datos de App Configuration
**Resultado:**
`HTTP/2 403`, `content-length: 0`.

He confirmado que la identidad usada no tiene el rol de datos App Configuration Data Reader/Owner sobre `SmartFran-Cloud-Settings-PRO` — `Reader`/`Contributor` a nivel de recurso no alcanza. He decidido no bloquear la investigación principal por este hallazgo y lo he registrado como seguimiento aparte (H5).

## 2026-08-23 13:35 — Primeros intentos contra App Insights (Sales-PRO)

**Comando:** C3 — `az monitor app-insights query` sobre `SmartFran-Cloud-Sales-PRO_new`, `requests` filtrado por `SaleOrder`/`pay`
**Resultado:**
Vacío, en ventanas de 24h y 7d.

He verificado que el componente de App Insights existe y está correctamente provisionado, y que la app tiene configurada la instrumentation key correcta — he descartado un problema de configuración. Más adelante he confirmado que el gap real es de sampling (H4), no de conectividad.

## 2026-08-23 13:50 — Métricas de plataforma de Sales-PRO

**Comando:** C4 — `az monitor metrics list` sobre `Microsoft.Web/sites/SmartFran-Cloud-Sales-PRO`, `HttpResponseTime`/`Requests`/`Http5xx`, 2026-08-22 13:00–23:59 UTC
**Resultado:**
Promedio estable (~0.3–0.55s) con volumen de tráfico creciente; máximo por bucket de 15 min persistentemente alto desde ~14:45 UTC (hasta 23.2s); `Http5xx` prácticamente en cero.

He identificado un patrón de latencia de cola alta sin errores, consistente con reintentos transparentes o con llamadas sincrónicas encadenadas — a confirmar contra el código fuente.

## 2026-08-23 14:05 — Verificación de throttling en CosmosDB

**Comando:** C5 — `az monitor metrics list` sobre la cuenta Cosmos compartida, `TotalRequests` filtrado por `StatusCode eq '429'`, mismo período
**Resultado:**
Cero resultados, contra una dimensión validada (`StatusCode` confirmado como dimensión real) y una lectura sin filtro que sí devolvió datos reales (~875K–1.1M requests/hora).

He descartado el throttling de RU de CosmosDB como causa de la latencia observada.

## 2026-08-23 14:20 — Desglose real por operación vía Log Analytics

**Comando:** C6 — `az monitor log-analytics query` sobre el workspace `SmartFranCloudPro`, tabla `AppRequests`, `AppRoleName == 'smartfran-cloud-sales-pro'`
**Resultado:**
`Sale/Close` con máximo de 13.457ms sobre 537 llamadas; `WsFeAr/CaeRequest` (AFIP) con promedio 2.355ms y máximo 11.228ms sobre 374 llamadas. Ninguna operación de la familia `SaleOrder` presente en la muestra.

He corregido el mapeo inicial de endpoints: Canning/WEISS usa el flujo clásico `Sale/Create` → `Sale/Close`, no el modelo de 3 pasos `SaleOrder`. He identificado `Sale/Close` como la operación con mayor latencia máxima observada del lado servidor.

## 2026-08-23 14:35 — Verificación de rama del repositorio fuente

**Comando:** C7 — `git fetch`/`checkout main`/`pull --ff-only` + `git diff origin/dev origin/main --stat`
**Resultado:**
El working tree local estaba en `dev`, 181 commits detrás de `origin/main` (la rama real de PRO). El diff puntual sobre los archivos ya leídos (`SaleService.cs`, `StockMovementCreator.cs`) mostró una sola divergencia, ajena a la investigación (conversión de unidades de stock mayorista).

He corregido el checkout a `main` antes de continuar cualquier lectura de código fuente, y he revalidado que las lecturas previas seguían siendo válidas para lo específico que estaba investigando.

## 2026-08-23 15:35 — Análisis de la primera captura HAR real (terminal POS de Canning)

**Resultado:**
`Sale/Close` con tiempo total de 19.383ms en la entrada visible para la página, pero con tiempo real de red de 1.141ms (`_workerRespondWithSettled` del Service Worker coincide con esa cifra). Body de respuesta de 0 bytes. Silencio total de red entre +0.87s y +15.62s, seguido de una ráfaga simultánea de recursos estáticos (logo, fuentes, CSS, `LogoTicket`).

He determinado que el backend respondió rápido y que la demora percibida no corresponde a la llamada HTTP de `Sale/Close` en sí.

## 2026-08-23 15:40 — Trazado del código cliente POS (`Sale.razor.cs`)

**Resultado:**
`SaleCloseAsync` se despacha de forma fire-and-forget (doble `_ = ...`, nunca se espera). Inmediatamente después, el código sí espera de forma genuina `PrintOrderIfNeeded()` — que se ejecuta incondicionalmente en todo cierre de venta, sin depender de si se solicitó factura o de si la venta se va a cancelar después.

He determinado que la demora visible en pantalla no puede deberse a la llamada de cierre en sí, y he redirigido el foco hacia la cadena de impresión.

## 2026-08-23 15:55 — Segunda captura HAR — confirmación del patrón

**Resultado:**
Mismo patrón exacto en una reproducción independiente: `Sale/Close` con 17.390ms totales vs. 984ms de red real; 13.75s de silencio; misma ráfaga de assets. He verificado además que las llamadas `Kds/orders` en ambas capturas ocurrieron ~40–45s antes del cierre (al momento de crear la orden), con latencia baja (~400ms) — he descartado la creación de orden KDS como causa de esta demora puntual.

He confirmado que el patrón es determinístico (dos reproducciones independientes, misma firma), no ruido de red aleatorio.

## 2026-08-23 16:05 — Identificación de la causa raíz

**Resultado:**
`Print()` invoca `_js.InvokeAsync("window.getBase64", ...)`. La función `getBase64` (`clientPrint.js`) usa `html2canvas` con `useCORS: true` (que hace que la librería misma solicite cada imagen/fuente referenciada en el DOM clonado — coincide exactamente con la ráfaga de assets observada, incluyendo recursos externos: Google Fonts, gravatar, avatares de Auth0), `logging: true` (logging de debug activo en producción), y sin ningún timeout en toda la llamada.

He identificado la causa raíz como un problema de rendimiento del lado cliente (renderizado de la vista previa del ticket vía `html2canvas`), ajeno a la infraestructura de Azure/SmartFran Cloud — Sales-PRO, Business-PRO, Catalog-PRO, CosmosDB y Service Bus quedan descartados como causa de este síntoma puntual.

## 2026-08-23 16:15 — Confirmación con la colaboradora en Canning

**Resultado:**
No hubo congelamiento de pantalla — se mostró una imagen de espera de forma continua durante la transición NUEVO → COBRADO. La reproducción fue sobre el terminal POS real de Canning, no un equipo remoto sin hardware de impresión. No se imprimió nada porque las ventas de prueba se cancelan inmediatamente después (sin solicitar factura).

He verificado que la reproducción es representativa del terminal real, y he dejado registrado como abierto si "Anular Venta" comparte esta misma causa (no verificado en esta sesión).
