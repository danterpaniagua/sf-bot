# GITIN-2058 — Mejora del Health Check del Load Balancer de WebServiceV2

## Resumen

`SFCG-WSV2-LB` (Load Balancer de WebServiceV2, `SFCG-WSV2-01`/`SFCG-WSV2-02`, sirve **SmartCloud**) usaba un health probe **TCP puro** (`sfcg-sondeo02`, puerto 8080) que solo verificaba que el puerto estuviera abierto, sin verificación a nivel de aplicación. Aplicando el mismo patrón implementado en [GITIN-1228](https://smartit-ar.atlassian.net/browse/GITIN-1228) (MobileAppService), se implementó un health check HTTP real (`healthcheck.ashx`) que reporta CPU, RAM, cola de requests, conectividad a base de datos y conectividad a Redis, se desplegó en ambos servidores, y se migró el rule del Load Balancer a un probe HTTP ya existente pero no utilizado (`healthcheck`, puerto 80, `/healthcheck.ashx`).

## Tabla resumen

| Campo | Valor |
|---|---|
| Ticket Jira | [GITIN-2058](https://smartit-ar.atlassian.net/browse/GITIN-2058) |
| Caso | Mejora del health check del Load Balancer — WebServiceV2 |
| Servidor/Plataforma | `SFCG-WSV2-01`/`SFCG-WSV2-02` (WebServiceV2, IIS), `SFCG-WSV2-LB` (Azure Standard Load Balancer) |
| Severidad | Media |
| Detectado (origen) | Patrón derivado de GITIN-1228/GITIN-2053 |
| Resuelto | Sí — probe HTTP implementado y en producción en ambos servidores |
| Responsable | Dante Paniagua (SRE) |

## Causa raíz

El health probe original (`sfcg-sondeo02`, TCP, puerto 8080) solo confirma que el socket TCP acepta conexiones — no puede detectar saturación de CPU/RAM, cola de requests, ni problemas de conectividad a base de datos o Redis. Esto ya había causado un problema relacionado (no idéntico) en `GITIN-1238` (2026-08-27): una regla de NSG faltante dejaba a `SFCG-WSV2-02` sin tráfico real mientras el probe seguía reportándolo saludable (la evaluación de NSG no aplica a los probes del propio Load Balancer).

## Hallazgos

| # | Hallazgo | Riesgo |
|---|---|---|
| H1 | Handler `healthcheck.ashx` implementado y desplegado en ambos servidores, reportando CPU, RAM, cola de requests, conectividad a base de datos y a Redis | — **implementado** |
| H2 | Una primera versión del handler (escrita antes de esta revisión) tenía un bug crítico: el código HTTP de respuesta era siempre `200` sin importar el estado real (`status == "Unhealthy" ? 200 : 200`) — el Load Balancer nunca podría haber detectado una falla real | Alto — **corregido** antes de desplegar |
| H3 | El binding HTTPS en el puerto 8080 está limitado por hostname (`webservicev2.smartfran.com`), mismo problema encontrado en GITIN-1228 — el probe del LB solo puede conectar por IP privada | Alto — **resuelto**, probe migrado a HTTP puerto 80 (binding sin restricción de hostname, ya existente en este LB) |
| H4 | `SFCG-WSV2-01` tiene su Admin State en el Load Balancer seteado en `Up` — este override hace que el servidor sea considerado siempre saludable independientemente del resultado real del probe (confirmado en documentación oficial de Azure) | Medio — **pendiente**, no se sabe si este override es intencional o accidental |
| H5 | `SFCG-WSV2-02` tiene disco `D:\` efímero (almacenamiento temporal de Azure) — cualquier desasignación/reimagen de la VM borra lo desplegado ahí, incluyendo este handler. No confirmado de forma concluyente si la configuración sobrevive el apagado nocturno programado (`00:00`–`09:00` UTC-3) | Medio — **pendiente de confirmación**, no bloqueante |

## Métricas del evento

| Métrica | Valor |
|---|---|
| Servidores afectados | `SFCG-WSV2-01`, `SFCG-WSV2-02` |
| Probe anterior | TCP, puerto 8080 (`sfcg-sondeo02`), `probeThreshold=1` |
| Probe actual | HTTP, puerto 80, `/healthcheck.ashx` (probe `healthcheck`, ya existente), intervalo 5s, `probeThreshold=1` (no ajustado) |
| Umbral CPU/RAM del handler | 80% (mismas claves de configuración que GITIN-1228) |
| Timeout de conectividad DB/Redis | 2 segundos cada uno |
| Comportamiento ante falla de Redis | No saca al servidor de rotación — la aplicación tiene fallback confirmado a base de datos (`RedisCacheService.GetOrSetCache`) |

## Referencia técnica del handler

**Campos de la respuesta JSON:**

| Campo | Significado |
|---|---|
| `status` | `Healthy` (200), `Warning` (400 — CPU o RAM sobre el umbral), o `Error` (500 — falla de conectividad a base de datos) |
| `cpu` / `memory` / `requestsQueued` | Mismos contadores de performance que GITIN-1228 |
| `database.healthy` / `database.message` / `database.responseTimeMs` | Resultado de `SELECT 1` real contra la base, sin tocar tablas |
| `redis.healthy` / `redis.message` / `redis.responseTimeMs` | Conectividad TCP al host/puerto de `RedisConnection` — informativo, no afecta el código HTTP |

**Dónde están almacenadas las variables de configuración:**

| Variable | Ubicación |
|---|---|
| `HealthCheck_CpuThreshold` / `HealthCheck_MemThreshold` | `Config\AppSettings.config` (claves agregadas por este ticket) |
| Cadena de conexión a base de datos | `Config\ConnectionStrings.config`, clave `SmartFran.Solution.SmartLoyalty.Data.Context.SmartLoyaltyContext` |
| Configuración de Redis | `Config\AppSettings.config`, claves `RedisConnection`/`TimeoutRedis` (ya existentes, usadas también por la aplicación real) |

## Acciones propuestas

1. **(SRE)** — Implementado y desplegado `healthcheck.ashx` en `SFCG-WSV2-01` y `SFCG-WSV2-02`. Aplicado.
2. **(SRE)** — Migrado el health probe de `SFCG-WSV2-LB-lbrule01` de TCP puerto 8080 a HTTP puerto 80 (`healthcheck`, ya existente en el Load Balancer). Aplicado, ambos servidores confirmados en estado `Up`.
3. **(SRE)** — Decidir si corresponde limpiar el override de Admin State en `SFCG-WSV2-01` (actualmente `Up`) para que su salud dependa realmente del probe, igual que `-02`.
4. **(SRE)** — Confirmar que el handler y la configuración sobreviven el ciclo de apagado nocturno de `SFCG-WSV2-02` (disco efímero) — no confirmado de forma concluyente.
5. **(SRE)** — Evaluar si conviene subir `probeThreshold` a `2` (mismo ajuste aplicado en GITIN-1228, mismo alcance limitado: solo protege contra timeouts del probe, no contra respuestas explícitas no-200 del propio handler).
6. **(Dev/SRE) — CRÍTICO, urgente.** Mismo riesgo que GITIN-1228: `healthcheck.ashx` fue colocado manualmente en el filesystem de ambos servidores, sin agregarlo al código fuente real de la aplicación. Un deploy estándar probablemente lo elimine, rompiendo el health check en ambos servidores a la vez (más grave aún en `-02`, cuyo disco es efímero — ver punto 4). Agregar el archivo al proyecto fuente y desplegarlo por el pipeline normal antes del próximo release.

## Archivos de evidencia

| Archivo | Contenido |
|---|---|
| `healthcheck.ashx` | Handler C# desplegado — CPU, RAM, cola de requests, conectividad a base de datos y a Redis |
| `data/sfcg-wsv2-lb_probes_current.json` | Inventario de probes existentes en `SFCG-WSV2-LB` (incluye el probe `healthcheck` ya existente, reutilizado) |
| `data/sfcg-wsv2-lb_probe_healthcheck_current.json` | Configuración final del probe migrado (HTTP, puerto 80, `probeThreshold=1`) |
