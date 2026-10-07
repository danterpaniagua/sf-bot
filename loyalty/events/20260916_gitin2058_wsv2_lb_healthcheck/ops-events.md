# Eventos — 20260916_gitin2058_wsv2_lb_healthcheck

## 2026-09-16 12:30 — Inicio del ticket, mismo patrón que GITIN-1228

He iniciado este ticket aplicando el mismo patrón de health check implementado en GITIN-1228, esta vez para WebServiceV2. He documentado las diferencias conocidas frente al caso de MobileAppService: puerto de aplicación distinto (8080), `SFCG-WSV2-02` no corre 24/7, y `SFCG-WSV2-02` tiene disco efímero.

## 2026-09-16 13:00 — Revisión de código de un handler ya desplegado

He revisado un `healthcheck.ashx` ya escrito y desplegado en WebServiceV2. He encontrado un bug crítico: el código de estado HTTP era siempre `200` sin importar el resultado real de las verificaciones, lo cual habría impedido que el Load Balancer detectara cualquier falla real. He señalado también un lookup de cadena de conexión frágil (coincidencia parcial de texto, con riesgo de tomar la base de datos incorrecta) y un descubrimiento de configuración de Redis igualmente frágil.

## 2026-09-16 13:20 — Confirmación del fallback de Redis y reescritura del handler

He confirmado directamente en el código fuente (`RedisCacheService.cs`) que la aplicación real tiene un fallback genuino a base de datos cuando Redis no está disponible — esto valida la decisión de no sacar al servidor de rotación solo por falla de Redis. He obtenido de ese mismo archivo los nombres reales de las claves de configuración de Redis. He reescrito el handler combinando el patrón de CPU/RAM/cola de GITIN-1228 con verificaciones directas (no frágiles) de base de datos y Redis.

## 2026-09-16 13:45 — Despliegue confirmado en ambos servidores

He confirmado el handler respondiendo correctamente en `SFCG-WSV2-01` y `SFCG-WSV2-02`, con conectividad real a base de datos y Redis en ambos casos.

## 2026-09-16 14:00 — Probe existente encontrado y reutilizado

He revisado el inventario de probes de `SFCG-WSV2-LB` y he encontrado un probe HTTP ya configurado (`healthcheck`, puerto 80, `/healthcheck.ashx`) que coincidía exactamente con lo necesario, sin uso previo. He migrado `SFCG-WSV2-LB-lbrule01` a este probe. He confirmado ambos servidores en estado `Up` en el Load Balancer.

## 2026-09-16 14:15 — Hallazgo sobre Admin State en `SFCG-WSV2-01`

He detectado que `SFCG-WSV2-01` tiene su Admin State en `Up`, un override manual que lo mantiene siempre elegible para tráfico nuevo independientemente del resultado real del probe (confirmado en documentación oficial de Azure). He dejado pendiente la decisión de limpiar este override.

## 2026-09-16 14:30 — Redacción del ticket

He redactado `ops.md` con el estado consolidado: probe HTTP implementado y en producción en ambos servidores; pendiente decidir sobre el override de Admin State en `-01` y confirmar la persistencia de la configuración en el disco efímero de `-02`.
