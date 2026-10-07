# GITIN-1228 — Mejora del Health Check del Load Balancer de MobileAppService

## Resumen

`SFCG-MOBI-LB` (Load Balancer de MobileAppService, `SFCG-MOBI-01`/`SFCG-MOBI-02`) usaba un health probe **TCP puro** que solo verificaba que el puerto 8043 estuviera abierto, sin ninguna verificación a nivel de aplicación (thread pool, conectividad a base de datos, CPU/RAM). Esta limitación ya había sido señalada como deuda técnica en GITIN-1909 (2026-08-21) y quedó directamente relacionada con hallazgos de [GITIN-2053](https://smartit-ar.atlassian.net/browse/GITIN-2053) (desbalance de tráfico entre los dos servidores del pool no detectado por el probe). Se implementó un health check HTTP real (`healthcheck.ashx`) que reporta CPU, RAM y conectividad a base de datos, se desplegó en ambos servidores, y se migró el rule del Load Balancer al nuevo probe. El objetivo más amplio del ticket original — balanceo ponderado por CPU/RAM — queda pendiente de investigación de factibilidad (ver Hallazgos).

## Tabla resumen

| Campo | Valor |
|---|---|
| Ticket Jira | [GITIN-1228](https://smartit-ar.atlassian.net/browse/GITIN-1228) |
| Caso | Mejora del health check del Load Balancer — MobileAppService |
| Servidor/Plataforma | `SFCG-MOBI-01`/`SFCG-MOBI-02` (MobileAppService, IIS), `SFCG-MOBI-LB` (Azure Standard Load Balancer) |
| Severidad | Media |
| Detectado (origen) | 2026-09-15 (GITIN-2053) |
| Resuelto | Parcial — probe HTTP implementado y en producción; balanceo ponderado por CPU/RAM aún no resuelto |
| Responsable | Dante Paniagua (SRE) |

## Causa raíz

El health probe original (`SFCG-MOBI-LB-probe02`, TCP, puerto 8043, `numberOfProbes=1`) solo confirma que el socket TCP acepta conexiones — no puede detectar saturación de CPU/RAM, cola de requests, ni problemas de conectividad a base de datos en la aplicación. Esto significa que un servidor puede estar sirviendo respuestas lentas o con errores de aplicación sin que el Load Balancer lo saque de rotación.

## Hallazgos

| # | Hallazgo | Riesgo |
|---|---|---|
| H1 | Handler `healthcheck.ashx` implementado y desplegado en ambos servidores, reportando CPU, RAM, cola de requests (`ASP.NET\Requests Queued`) y conectividad a base de datos vía HTTP | — **implementado** |
| H2 | El probe original en `https://8043` no es viable para el Load Balancer: el binding HTTPS de IIS está limitado por hostname (`mobileservice.clubgrido.com.ar`), y el probe del LB solo puede conectar por IP privada, sin poder enviar ese hostname — la solicitud nunca llega a coincidir con el binding | Alto — **resuelto**, probe migrado a HTTP puerto 8080 (binding wildcard, sin restricción de hostname) |
| H3 | Un solo servidor bajo carga completa de producción puede superar el umbral de 80% CPU/RAM del propio handler y reportarse como no saludable — comportamiento seguro solo si el otro servidor está disponible para absorber el tráfico | Medio — **pendiente**, necesita ajuste de umbral o lógica de histéresis |
| H4 | El objetivo original del ticket (balanceo ponderado por CPU/RAM) no es una capacidad nativa de Azure Standard Load Balancer — el probe HTTP/HTTPS solo soporta saludable/no saludable binario, no distribución ponderada por métrica | Medio — **pendiente**, necesita definición de alcance (¿Traffic Manager, Application Gateway, mecanismo propio, o el pass/fail actual es suficiente?) |

## Métricas del evento

| Métrica | Valor |
|---|---|
| Servidores afectados | `SFCG-MOBI-01`, `SFCG-MOBI-02` |
| Probe anterior | TCP, puerto 8043, `numberOfProbes=1` |
| Probe actual | HTTP, puerto 8080, `/healthcheck.ashx`, intervalo 5s, `probeThreshold=2` |
| Umbral CPU/RAM del handler | 80% (configurable vía `AppSettings.config`, no ajustado desde el valor por defecto) |
| Cola de requests (`requestsQueued`) | Reportada, informativa por ahora — no afecta el status HTTP del health check |
| Timeout de verificación de base de datos | 2 segundos (conexión y comando) |

## Acciones propuestas

1. **(SRE)** — Implementado y desplegado `healthcheck.ashx` en `SFCG-MOBI-01` y `SFCG-MOBI-02`, reportando CPU, RAM y conectividad a base de datos. Aplicado.
2. **(SRE)** — Migrado el health probe de `SFCG-MOBI-LB-lbrule02` de TCP puerto 8043 a HTTP puerto 8080 (binding wildcard de IIS, evita el problema de binding por hostname del puerto 8043). Aplicado, ambos servidores confirmados saludables bajo el nuevo probe.
3. **(SRE)** — Definir el umbral de CPU/RAM final o implementar histéresis para evitar que un servidor se saque a sí mismo de rotación bajo carga legítima de un único servidor.
4. **(SRE)** — Investigar si el objetivo de balanceo ponderado por CPU/RAM requiere un mecanismo distinto a `SFCG-MOBI-LB` (Azure Standard LB no soporta distribución ponderada por métrica de forma nativa) — de ser así, escalar como decisión de arquitectura antes de continuar.
5. **(SRE)** — Confirmar el umbral `HealthCheck_CpuThreshold`/`HealthCheck_MemThreshold` (actualmente en el valor por defecto 80%) contra el comportamiento real de ambos servidores bajo carga normal compartida, no solo bajo carga consolidada de un único servidor.
6. **(Dev/SRE) — CRÍTICO, urgente.** `healthcheck.ashx` fue colocado manualmente en el filesystem de ambos servidores, sin agregarlo al código fuente real de la aplicación ni al pipeline de deploy. Un deploy estándar probablemente lo elimine, rompiendo el health check en ambos servidores a la vez. Agregar el archivo al proyecto fuente y desplegarlo por el pipeline normal antes del próximo release.

## Referencia técnica del handler

**Campos de la respuesta JSON** (`healthcheck.ashx`):

| Campo | Significado |
|---|---|
| `status` | `Healthy` (200), `Warning` (400 — CPU o RAM sobre el umbral), o `Error` (500 — falla de conectividad a base de datos) |
| `cpu` | % de uso de CPU (`Processor\% Processor Time\_Total`, muestreado en una ventana de 500ms) |
| `memory` | % de memoria comprometida sobre el límite (`Memory\Committed Bytes` / `Memory\Commit Limit`) |
| `requestsQueued` | Cantidad de requests en cola (`ASP.NET\Requests Queued`) — informativo, no afecta `status`/código HTTP |
| `database` | `Healthy` o `Error` — resultado de abrir una conexión real y ejecutar `SELECT 1` (sin tocar ninguna tabla, para no quedar bloqueado por mantenimiento de índices — ver GITIN-2053) |
| `databaseError` | Solo presente si `database:"Error"` — mensaje de la excepción SQL |

**Dónde están almacenadas las variables de configuración:**

| Variable | Ubicación | Valor actual |
|---|---|---|
| `HealthCheck_CpuThreshold` | `Config\AppSettings.config` (clave agregada por este ticket) | `80` |
| `HealthCheck_MemThreshold` | `Config\AppSettings.config` (clave agregada por este ticket) | `80` |
| Cadena de conexión a base de datos | `Config\ConnectionStrings.config`, clave `SmartFran.Solution.SmartLoyalty.Data.Context.SmartLoyaltyContext` (ya existente, no agregada por este ticket) | — |
| Timeout de conexión/comando SQL | Constante en el código del handler (`DbTimeoutSeconds`), no configurable externamente | `2` segundos |

Si una clave de `AppSettings.config` falta o no es numérica, el handler usa el valor por defecto (`80`) en lugar de fallar — ver `GetThreshold()` en `healthcheck.ashx`.

## Hallazgos secundarios

Durante la revisión de `AppSettings-Template.config` (plantilla de configuración de MobileAppService en el clon local de referencia) se encontró lo que parece ser una credencial real en texto plano (`SmtpPassword`). Hallazgo independiente del alcance de este ticket — no investigado más a fondo aquí, y no se repite el valor en ningún archivo de este repositorio.

## Archivos de evidencia

| Archivo | Contenido |
|---|---|
| `healthcheck.ashx` | Handler C# desplegado — reporta CPU, RAM, conectividad a base de datos |
| `data/sfcg-mobi-lb_probes_current.json` | Inventario de probes existentes en `SFCG-MOBI-LB` (incluye el probe huérfano `healthcheck.ashx` reutilizado) |
| `data/sfcg-mobi-lb_activitylog_30d.json`, `data/sfcg-mobi-lb_activitylog_90d_rg.json` | Activity Log de Azure — confirma que el Admin State de `-01` fue seteado manualmente para una prueba controlada |
| `data/sfcg-mobi-lb_probe_healthcheck_current.json` | Configuración final del probe migrado (HTTP, puerto 8080, `probeThreshold=2`) |
