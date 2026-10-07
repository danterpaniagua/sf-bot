# Eventos — 20260910_webservicev2_healthcheck_500

## 2026-09-10 — Apertura de investigación (GITIN-2025)

He abierto esta investigación a partir de una alerta de Zabbix (`WebServiceV2. HTTP Code not 200`, severidad Alta) activa desde 2026-09-02 09:13:25 (UTC-3) y sin reconocer durante 8 días. He revisado la investigación previa `20260826_wsv2lb_vm2_trustedlaunch_no_traffic` (`GITIN-1238`) por tratarse de la misma infraestructura (`SFCG-WSV2-01`/`SFCG-WSV2-02`), que ya había documentado un bug conocido en `SFCG-WSV2-01` sobre el mismo endpoint `/healthcheck.ashx`.

## 2026-09-10 — Confirmación de la definición del escenario web y del trigger

He confirmado, vía `httptest.get` de la API de Zabbix, que el escenario `[PROD] WebServiceV2` ejecuta un único paso `Healthcheck` contra `https://webservicev2.smartfran.com:8080/healthcheck.ashx`, requiriendo código 200, desde el proxy `sfcg-monitoreo`. He confirmado, vía `trigger.get`, que el trigger `WebServiceV2. HTTP Code not 200` no tiene tags asignados — por lo tanto ninguna acción de enrutamiento basada en tags puede procesarlo, dejando únicamente la acción sin condiciones como vía posible de notificación.

## 2026-09-10 — Confirmación de la causa en el log de eventos de Aplicación

He confirmado, vía `Get-WinEvent` (Event ID 1309) en `SFCG-WSV2-01`, múltiples excepciones no controladas desde el 2026-09-02 con el mensaje `Controlador healthcheck.ashx no válido.`, originadas en `ControllerFactory.CreateController`, con dirección de origen `172.191.99.60` — la propia IP del proxy Zabbix `sfcg-monitoreo`, confirmando que se trata de los propios sondeos del escenario web.

## 2026-09-10 — Corrección: se identificó y confirmó la eliminación del archivo en el despliegue del 2026-09-01

Se confirmó que el archivo `healthcheck.ashx` fue eliminado en el despliegue del 2026-09-01 en ambas VMs (`SFCG-WSV2-01` y `SFCG-WSV2-02`) — no se trataba del bug preexistente de `SFCG-WSV2-01` documentado en `GITIN-1238`, sino de una regresión introducida por ese despliegue. He restaurado el archivo `healthcheck.ashx` en ambas VMs.

## 2026-09-10 — Verificación de la corrección

He verificado mediante `curl` externo, a través del Load Balancer, que `https://webservicev2.smartfran.com:8080/healthcheck.ashx` responde HTTP 200. He verificado, vía `item.get` de la API de Zabbix filtrado por `hostid`, que ambos application pools de `SmartLoyalty.WebServiceV2` están en estado `Running`, sin recycles registrados, con el puerto `{$IIS.PORT}` arriba y los servicios W3SVC/WAS en ejecución en ambas VMs. He verificado el estado del trigger post-corrección: seguía en estado de problema (`value:1`) con `lastchange` sin cambios respecto al inicio original de la alerta — consistente con la ventana de 20 minutos requerida por la expresión de recuperación, no con una falla persistente.

## 2026-09-10 — Cierre técnico de la investigación

Investigación convergida: causa raíz confirmada (eliminación de `healthcheck.ashx` en el despliegue del 2026-09-01, ambas VMs), corrección aplicada (archivo restaurado en ambas VMs) y verificada (respuesta HTTP 200 real + telemetría nativa de Zabbix saludable en ambas VMs). He redactado `ops.md` para el cierre del ticket GITIN-2025.
