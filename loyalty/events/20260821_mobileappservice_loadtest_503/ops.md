**Resumen**

Grido reportó errores 503 durante una prueba de carga contra MobileAppService, con el mensaje de cliente "Unable to read data from the transport connection: An existing connection was forcibly closed by the remote host." Graylog no registró ningún 503 para la ventana reportada. Se confirmó, mediante escaneo exhaustivo de `httperr.log` en `SFCG-MOBI-01`, que no se envió ningún 503 real durante el incidente original: el mecanismo real es el cierre de conexiones inactivas por parte de IIS (`connectionTimeout=15s`, configuración deliberada de hardening), que colisiona con el comportamiento de reuso de conexiones de un cliente HTTP con pooling bajo condiciones de prueba de carga.

**Tabla resumen**

| Campo | Valor |
|---|---|
| Ticket Jira | [GITIN-1909](https://smartit-ar.atlassian.net/browse/GITIN-1909) |
| Caso | Errores 503 reportados por Grido durante prueba de carga contra MobileAppService |
| Host / Componente | `SFCG-MOBI-01` / `SFCG-MOBI-02` (IIS, MobileAppService) detrás de `SFCG-MOBI-LB` |
| Severidad | Media (sin impacto real confirmado — ver Causa raíz) |
| Detectado | 2026-08-21 |
| Resuelto | 2026-08-21 — cierre de diagnóstico. Sin cambios de infraestructura aplicados; según lo reportado, la prueba de carga posterior se completó. No se confirmó si esa corrida tuvo cero resets de conexión o simplemente un volumen tolerado — la acción propuesta 1 (coordinación con Grido) queda como seguimiento abierto, no bloqueante para el cierre |
| Responsable | Dante Paniagua, SRE |

**Causa raíz**

El sitio MobileAppService tiene configurado `connectionTimeout=15s` en IIS (confirmado idéntico en `SFCG-MOBI-01` y `SFCG-MOBI-02`), muy por debajo del valor por defecto de IIS (120s) — configuración deliberada de hardening de seguridad contra agotamiento de conexiones inactivas, no un error de configuración. Bajo prueba de carga, un cliente HTTP con connection pooling intenta reutilizar conexiones que ya fueron cerradas por el servidor tras 15s de inactividad, lo que produce del lado del cliente exactamente el error reportado ("connection forcibly closed by remote host"). Este es un reset de conexión a nivel de transporte — IIS nunca llega a generar una respuesta HTTP, y por eso Graylog no registra nada. La herramienta de prueba de carga de Grido clasifica este tipo de falla de transporte como "503" en su propio reporte, sin que ningún componente de la infraestructura haya emitido realmente ese código de estado.

Se confirmó además que ningún componente del camino de red hacia MobileAppService, salvo IIS mismo, tiene capacidad de generar un código de estado HTTP: el camino real es NSG (allow-list IP a IP uno a uno) → `SFCG-MOBI-LB` (Azure Load Balancer Standard, Capa 4) → IIS, sin ningún Application Gateway/WAF en el medio (`WAF_APPs` existe en el mismo resource group pero enruta únicamente WebSite/ClubGrido, no MobileAppService).

**Hallazgos**

| # | Hallazgo | Riesgo |
|---|---|---|
| H1 | `connectionTimeout=15s` en MobileAppService (ambas instancias) colisiona con el reuso de conexiones pooled de clientes HTTP bajo carga, generando resets de conexión — configuración deliberada, no defecto | Medio |
| H2 | Confirmado mediante escaneo completo de `httperr.log` en `SFCG-MOBI-01` (969 entradas, ventana 2026-08-21T11:00:00Z–12:06:37Z): cero respuestas HTTP 503 reales durante el incidente original | Bajo (informativo — descarta un 503 real como causa) |

**Recursos afectados**

| Recurso | Rol | Estado |
|---|---|---|
| `SFCG-MOBI-01` | MobileAppService (IIS) | Operativo — `connectionTimeout=15s` confirmado |
| `SFCG-MOBI-02` | MobileAppService (IIS) | Operativo — `connectionTimeout=15s` confirmado |
| `SFCG-MOBI-LB` | Azure Load Balancer (Standard, L4) | Operativo |

**Métricas del evento**

| Métrica | Valor |
|---|---|
| Ventana de análisis (inicio de prueba de carga → arranque de `SFCG-MOBI-02`) | 2026-08-21 11:00:00–12:06:37 GMT (08:00–09:06 UTC-3) |
| Entradas totales en `httperr.log` de `SFCG-MOBI-01` en la ventana | 969 |
| Entradas con `sc-status=503` en la ventana | 0 |
| `connectionTimeout` configurado (ambas instancias) | 15s |
| `connectionTimeout` por defecto de IIS | 120s |
| Pruebas de carga previas sobre el mismo LB sin este reporte | >800 requests |

**Diagnósticos ejecutados**

No se ejecutaron queries SQL en este ticket — el diagnóstico fue íntegramente sobre infraestructura Azure/IIS (Azure CLI, PowerShell, `httperr.log`). Detalle completo paso a paso disponible en `investigation.md`.

| # | Diagnóstico | Propósito |
|---|---|---|
| D1 | `az network lb` (rule/probe/address-pool/public-ip) | Relevó la configuración del Load Balancer `SFCG-MOBI-LB`, no documentada previamente |
| D2 | `az monitor metrics list` (`DipAvailability`) | Ubicó la única caída de salud del LB en la ventana de prueba (12:07–12:08 GMT) |
| D3 | `Get-WinEvent` (`Microsoft-Windows-WAS`) en `SFCG-MOBI-01`/`SFCG-MOBI-02` | Descartó recycling de application pool en `-01`; confirmó dos reinicios de WAS en `-02` |
| D4 | Lectura de `httperr*.log` en `SFCG-MOBI-01`/`SFCG-MOBI-02` | Localizó el patrón `Timer_ConnectionIdle`; confirmó ausencia total de `sc-status=503` en la ventana del incidente original |
| D5 | `Get-ItemProperty IIS:\Sites\... -Name limits.connectionTimeout` | Confirmó `connectionTimeout=15s` en ambas instancias |
| D6 | `az resource list` / `az network application-gateway` | Confirmó que `WAF_APPs` no enruta tráfico a MobileAppService |

**Acciones propuestas**

1. Coordinar con Grido para que el tráfico hacia MobileAppService tolere el cierre de una conexión pooled inactiva por parte del servidor y reintente automáticamente sobre una conexión nueva — comportamiento estándar esperado en cualquier cliente HTTP con connection pooling contra un servidor con timeout de inactividad. Confirmar primero con Grido el componente real detrás de `172.191.0.208` (una fuente externa no verificada lo identifica como su Azure API Management, pero esto no está confirmado de forma independiente) antes de dirigir la coordinación de reintentos a un componente específico. (SRE)
2. Documentar explícitamente que `connectionTimeout=15s` es una configuración deliberada de hardening, para que no vuelva a investigarse como posible defecto en futuros incidentes similares. (SRE)
