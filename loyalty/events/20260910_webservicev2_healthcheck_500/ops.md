# GITIN-2025 — WebServiceV2: healthcheck retornaba HTTP 500 desde el despliegue del 2026-09-01

**Tags:** `SmartLoyalty`, `Azure`, `SRE`, `PROD`

## Resumen

El escenario web de Zabbix `[PROD] WebServiceV2` (paso `Healthcheck`, contra `https://webservicev2.smartfran.com:8080/healthcheck.ashx`) detectó código de respuesta HTTP 500 de forma sostenida desde el 2026-09-02 09:13:25 (UTC-3) hasta el 2026-09-10, con severidad Alta y sin reconocer durante los 8 días de duración del problema. La causa fue la eliminación del archivo `healthcheck.ashx` en ambas VMs de WebServiceV2 (`SFCG-WSV2-01` y `SFCG-WSV2-02`) durante el despliegue del 2026-09-01. El archivo fue restaurado en ambas máquinas y la corrección quedó verificada.

## Tabla resumen

| Campo | Valor |
|---|---|
| Ticket Jira | [GITIN-2025](https://smartit-ar.atlassian.net/browse/GITIN-2025) |
| Caso | Healthcheck de WebServiceV2 (`/healthcheck.ashx`) retornaba HTTP 500 de forma sostenida |
| Plataforma | Zabbix (escenario web) / IIS — `SFCG-WSV2-01`, `SFCG-WSV2-02` (detrás de `SFCG-WSV2-LB`) |
| Severidad | Alta (severidad del trigger de Zabbix) |
| Detectado | 2026-09-02 09:13:25 (UTC-3) |
| Resuelto | 2026-09-10 |
| Responsable | Dante Paniagua |

## Causa raíz

El despliegue realizado el 2026-09-01 eliminó el archivo `healthcheck.ashx` de ambas instancias de WebServiceV2 (`SFCG-WSV2-01` y `SFCG-WSV2-02`). A partir de ese momento, toda solicitud a `https://webservicev2.smartfran.com:8080/healthcheck.ashx` — incluidas las ejecutadas por el escenario web de Zabbix desde el proxy `sfcg-monitoreo` — era rechazada por el enrutamiento de ASP.NET MVC con la excepción `Controlador healthcheck.ashx no válido.` (`ControllerFactory.CreateController`), devolviendo HTTP 500 en lugar de los 200 requeridos por el escenario. Se confirmó en el log de eventos de Aplicación de `SFCG-WSV2-01` (Event ID 1309), con múltiples ocurrencias desde el 2026-09-02 y dirección de origen `172.191.99.60` (IP propia del proxy Zabbix `sfcg-monitoreo`), confirmando que se trataba de los propios sondeos del monitoreo.

## Hallazgos

| # | Hallazgo | Riesgo |
|---|---|---|
| H1 | El despliegue del 2026-09-01 eliminó `healthcheck.ashx` de ambas VMs de WebServiceV2, dejando sin healthcheck funcional el endpoint monitoreado durante 8 días | Alto |
| H2 | El trigger `WebServiceV2. HTTP Code not 200` no tiene tags asignados — ninguna acción de enrutamiento basada en tags (Google Chat / Email) pudo procesarlo; solo la acción sin condiciones pudo haber notificado | Medio |

## Recursos afectados

| Recurso | Detalle |
|---|---|
| `SFCG-WSV2-01` | WebServiceV2 (`D:\SmartLoyalty.WebServiceV2\`) — afectada |
| `SFCG-WSV2-02` | WebServiceV2 (`D:\SmartLoyalty.WebServiceV2\`) — afectada |
| `SFCG-WSV2-LB` | Load Balancer frente a ambas VMs — no afectado directamente |
| `sfcg-monitoreo` | Proxy Zabbix — origen de los sondeos que revelaron el problema |

## Métricas del evento

| Métrica | Valor |
|---|---|
| Duración del problema | 2026-09-02 09:13:25 a 2026-09-10 (~8 días) |
| Item de Zabbix afectado | `web.test.rspcode["[PROD] WebServiceV2",Healthcheck]` |
| Código de respuesta observado | 500 (sostenido) |
| Código de respuesta requerido | 200 |
| VMs afectadas | 2 (`SFCG-WSV2-01`, `SFCG-WSV2-02`) |
| Verificación post-corrección | `curl` externo vía LB → 200; AppPool `Running` sin recycles en ambas VMs; puerto `{$IIS.PORT}` arriba en ambas |

## Comandos ejecutados

Historial completo de diagnóstico en `investigation.md`. Comandos centrales:

| # | Comando | Propósito |
|---|---|---|
| C1 | `httptest.get` (API Zabbix) | Obtener la definición exacta del escenario web `[PROD] WebServiceV2` |
| C2 | `trigger.get` (API Zabbix) | Confirmar tags y estado del trigger `WebServiceV2. HTTP Code not 200` |
| C3 | `Get-WinEvent` (Event ID 1309) | Confirmar la excepción real en el log de Aplicación de `SFCG-WSV2-01` |
| C4 | `curl` directo a `https://webservicev2.smartfran.com:8080/healthcheck.ashx` | Verificar el código de respuesta real post-corrección |
| C5 | `item.get` (API Zabbix, filtrado por `hostid`) | Confirmar estado de IIS/AppPool/servicios en ambas VMs post-corrección |

## Acciones propuestas

1. (Realizado) Se restauró el archivo `healthcheck.ashx` en `SFCG-WSV2-01` y `SFCG-WSV2-02`.
2. (Realizado) Se verificó la recuperación del endpoint mediante prueba directa (HTTP 200) y telemetría nativa de Zabbix en ambas VMs.
3. (Pendiente) Confirmar con el equipo de despliegue por qué el artefacto `healthcheck.ashx` fue eliminado en el despliegue del 2026-09-01, para evitar que se repita en futuros despliegues.
4. (Pendiente, opcional) Evaluar asignar tags al trigger `WebServiceV2. HTTP Code not 200` (por ejemplo `scope:OPE`, `service_group:LOYALTY`) para que quede cubierto por el enrutamiento de notificaciones ya vigente para otros triggers de LOYALTY — actualmente depende únicamente de la acción sin condiciones para notificar.

## Archivos de evidencia

| Archivo | Contenido |
|---|---|
| `investigation.md` | Registro completo de la investigación, hipótesis descartadas y evidencia técnica |
| `httptest_prod_webservicev2.json` | Definición del escenario web de Zabbix |
| `trigger_webservicev2_httpcode.json` | Detalle del trigger, incluyendo tags |
| `trigger_status_post_fix.json` | Estado del trigger luego de restaurar el archivo |
| `event1309_SFCG-WSV2-01.txt` | Entradas del log de eventos de Aplicación confirmando la excepción |
| `latest_data_wsv2_01_02.json` | Datos actuales de Zabbix (IIS/AppPool/servicios) en ambas VMs post-corrección |
| `hosts_wsv2_search.json` | Intento de búsqueda por nombre sin resultados (conservado como referencia) |
