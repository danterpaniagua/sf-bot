# GITIN-2028 — SSL MobileAppService: alerta falsa por contexto de macro incorrecto (FACTURASEND)

**Tags:** `SmartLoyalty`, `SRE`, `PROD`

## Resumen

El trigger de Zabbix `SSL MobileAppService a menos de 25 dias de vencer` permaneció activo desde el 2026-09-02 22:04:52 sin poder auto-recuperarse, pese a que el certificado real tenía 54 días de validez restante — un estado saludable, sin riesgo real de vencimiento. La causa fue que los tres triggers de vencimiento de certificado SSL de MobileAppService estaban referenciando el contexto de macro `:FACTURASEND` en lugar de uno propio, un caso de clonación de configuración sin actualizar el contexto. Como el umbral de recuperación heredado (`{$SSL_CERT_OK:FACTURASEND}=80`) es mayor que el valor que el certificado de MobileAppService alcanza en la práctica, el trigger no podía auto-recuperarse nunca por ese mecanismo. Se creó un contexto de macro dedicado (`:MOBI`) con umbrales acordes al ciclo de renovación automática de MobileAppService, y se corrigieron los tres triggers para usarlo.

## Tabla resumen

| Campo | Valor |
|---|---|
| Ticket Jira | [GITIN-2028](https://smartit-ar.atlassian.net/browse/GITIN-2028) |
| Caso | Trigger SSL de MobileAppService no se auto-recupera — contexto de macro incorrecto (FACTURASEND) |
| Base de datos / Plataforma | Zabbix (`Zabbix server`, hostid 10084) — monitoreo de vencimiento SSL centralizado |
| Severidad | Media — falsa alarma sostenida, sin riesgo real de vencimiento de certificado |
| Detectado | 2026-09-02 22:04:52 (inicio del problema); identificado como falso positivo el 2026-09-11 |
| Resuelto | 2026-09-11 |
| Responsable | Dante Paniagua |

## Causa raíz

Los tres triggers de vencimiento SSL de MobileAppService (`WARN`, `AVERAGE`, `HIGH`) referenciaban el contexto de macro `{$SSL_CERT_*:FACTURASEND}` en lugar de uno propio — el único otro servicio que usa ese contexto es FacturaSend, un servicio no relacionado. El trigger `WARN` (`triggerid 25914`) usa `recovery_mode: 1` (expresión de recuperación separada, no la negación de la condición de problema): `last(item)>{$SSL_CERT_OK:FACTURASEND}`, es decir, requiere más de 80 días de validez restante para recuperarse. El certificado de MobileAppService se mantuvo en 54 días durante toda la investigación (ítem `log[/var/log/zabbix/ssl_mobileappservice.log,...]`, no obsoleto — `lastclock` vigente), por lo que el trigger nunca pudo satisfacer esa condición pese a que el certificado está en buen estado.

## Hallazgos

| # | Hallazgo | Riesgo |
|---|---|---|
| H1 | Los tres triggers SSL de MobileAppService (WARN/AVERAGE/HIGH) usaban el contexto de macro `:FACTURASEND` en lugar de uno propio — umbral de recuperación (80 días) inalcanzable para el ciclo real de MobileAppService | Alto |
| H2 | El campo `description` de los tres triggers es un texto separado de `expression` — quedó desactualizado (seguía mostrando `:FACTURASEND`) incluso después de corregir la lógica de evaluación, mostrando un umbral incorrecto en el nombre de la alerta | Medio |
| H3 | El ítem subyacente es de tipo `unsigned integer` (`value_type: 3`) — la diferencia entre operador `>` y `>=` en el umbral de recuperación es real (un día completo de diferencia), no cosmética | Bajo (informativo, ya corregido) |

## Recursos afectados

| Recurso | Detalle |
|---|---|
| `Zabbix server` (hostid 10084) | Host donde corre el monitoreo centralizado de vencimiento SSL |
| `triggerid 25914` | `SSL MobileAppService a menos de {$SSL_CERT_WARN:...} dias de vencer` |
| `triggerid 26282` | `SSL MobileAppService a menos de {$SSL_CERT_AVERAGE:...} dias de vencer` |
| `triggerid 26284` | `SSL MobileAppService a menos de {$SSL_CERT_HIGH:...} dias de vencer` |
| `itemid 53392` | `log[/var/log/zabbix/ssl_mobileappservice.log,,utf-8,,,,,,]` |

## Comandos ejecutados

Historial completo en `investigation.md`. Llamadas centrales a la API de Zabbix:

| # | Comando | Propósito |
|---|---|---|
| C1 | `host.get` (filtro por nombre) | Obtener el hostid de `Zabbix server`, dado que `search` no fue confiable en esta instancia |
| C2 | `trigger.get` (por `hostids`) | Listar todos los triggers SSL del host para ubicar los de MobileAppService sin depender de `search` |
| C3 | `trigger.get` (`selectItems`, `selectFunctions`, `expandExpression`) | Obtener expresión, ítem y función real de cada trigger de MobileAppService |
| C4 | `usermacro.get` (`globalmacro: true`) | Confirmar los valores reales de los macros `SSL_CERT_*` base y `:FACTURASEND` |
| C5 | `usermacro.createglobal` (×4) | Crear los macros `{$SSL_CERT_WARN\|AVERAGE\|HIGH\|OK:MOBI}` |
| C6 | `item.get` | Confirmar `value_type` del ítem subyacente (entero, no fraccional) |
| C7 | `trigger.update` (×3, dos rondas) | Repuntar `expression`/`recovery_expression` de `:FACTURASEND` a `:MOBI`, y corregir el operador de recuperación a `>=` |
| C8 | `trigger.update` (×3) | Corregir el campo `description` de los tres triggers para reflejar `:MOBI` |

## Acciones propuestas

1. (Realizado) Se crearon los macros globales `{$SSL_CERT_WARN:MOBI}=15`, `{$SSL_CERT_AVERAGE:MOBI}=10`, `{$SSL_CERT_HIGH:MOBI}=2`, `{$SSL_CERT_OK:MOBI}=30`.
2. (Realizado) Se repuntaron los tres triggers de MobileAppService de `:FACTURASEND` a `:MOBI`, incluyendo la corrección del operador de recuperación (`>` → `>=`) y del campo `description`.
3. (Pendiente) Confirmar que `triggerid 25914` efectivamente pasó a estado recuperado (`value:"0"`) tras el próximo chequeo del ítem — no reconfirmado al cierre de este ticket.
4. (Pendiente, opcional) Revisar si FacturaSend en sí tiene el mismo problema en sentido inverso (es decir, si su propio ciclo de certificado es compatible con `{$SSL_CERT_OK:FACTURASEND}=80`) — no evaluado en esta investigación, dado que el foco fue exclusivamente MobileAppService.
5. (Pendiente, opcional) Documentar este hallazgo en `docs/zabbix_observability.md` como un caso más de contexto de macro mal propagado por clonación, en la misma línea que los ya documentados para la familia `PERF_COUNT_TRIG_*`.

## Archivos de evidencia

| Archivo | Contenido |
|---|---|
| `investigation.md` | Registro completo de la investigación y de la corrección aplicada |
| `data/01_host_zabbixserver.json` | Resolución del hostid de `Zabbix server` |
| `data/02_ssl_trigger_descriptions_zabbixserver.txt` | Listado completo de triggers SSL del host, confirmando que solo FacturaSend y MobileAppService usan contexto `:FACTURASEND` |
| `data/03_mobileappservice_triggers_initial.txt` | Detalle inicial de los 4 triggers de MobileAppService (expresión, recovery, ítem) |
| `data/04_globalmacros_ssl_cert.txt` | Valores reales de los macros globales `SSL_CERT_*` (base y `:FACTURASEND`) |
| `data/05_usermacro_createglobal_mobi_results.txt` | Resultado de la creación de los 4 macros `:MOBI` |
| `data/06_trigger_update_expression_attempt1_rejected.txt` | Intento fallido de `trigger.update` usando el formato `{funcid}` — error de API documentado |
| `data/07_trigger_functions_and_expandexpression.txt` | Detalle de función/ítem y expresión expandida usados para construir la sintaxis válida |
| `data/08_trigger_update_final_results.txt` | Resultados de las actualizaciones finales (expresión, operador `>=`, descripción) y verificaciones intermedias |
