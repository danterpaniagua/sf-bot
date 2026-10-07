# Eventos — 20260828_wsv2-02_zabbix_iis_calc_item_error

## 2026-08-28 11:18 — Diagnóstico y corrección del item calculado de IIS en SFCG-WSV2-02

He recibido el reporte de error en el item calculado de Zabbix (`IIS by Zabbix agent active`) que
suma `Post Requests/Sec` + `Get Requests/Sec` para `SFCG-WSV2-02`, con mensaje "item ... does not
exist". He descartado como causa una diferencia en la macro `{$IIS.APP.NAME}` entre `SFCG-WSV2-01` y
`SFCG-WSV2-02` — he confirmado que el valor es idéntico en ambos hosts. He identificado que el set de
contadores de rendimiento "Web Service" de Windows no estaba iniciado en `SFCG-WSV2-02`, por lo que
Windows no exponía ninguna instancia `\Web Service(...)\` para que la LLD de Zabbix la descubriera.
Se inició el set de contadores en la VM; he confirmado que la instancia `SmartLoyalty.WebServiceV2` con
los contadores `Post Requests/sec` y `Get Requests/sec` ya está disponible.

## 2026-08-28 11:18 — Error transitorio esperado tras la corrección

Tras iniciar el set de contadores, el error del item calculado cambió de "item ... does not exist" a
"not enough data" — confirmando que el item crudo ya fue descubierto y creado en Zabbix, y que solo
falta que acumule historial suficiente para que `last()` pueda evaluarlo. Queda pendiente confirmar
la limpieza definitiva del error y si el set de contadores persiste iniciado tras el próximo ciclo de
apagado/encendido programado de `SFCG-WSV2-02`.

## 2026-08-28 12:18 — Segunda causa encontrada: bug conocido de Zabbix Agent 2 (ZBX-22463)

He detectado en `zabbix_agent2.log` que el item crudo `Post Requests/Sec` seguía sin recolectar datos
pese al set de contadores activo, con el mensaje repetido "Detected performance counter with negative
denominator the second time after retry, giving up...". He confirmado, vía búsqueda web, que se trata
de un bug conocido de Zabbix Agent 2 en Windows (`ZBX-22463`, relacionado con `ZBX-21661`, `ZBX-22438`
y `ZBX-20356`), no de un problema de configuración propio de este host. Se reinició el servicio
Zabbix Agent 2 en `SFCG-WSV2-02` (host confirmado vía `$env:COMPUTERNAME` antes del reinicio) —
solución documentada en reportes de la comunidad. Tras el reinicio, he confirmado que el item `Post
Requests/Sec` volvió a recolectar datos con normalidad.

## 2026-08-28 12:18 — Tercera causa encontrada: item Get Requests/Sec nunca creado en VM2

Al reaparecer el error del item calculado, esta vez específicamente sobre `Get Requests/Sec` con el
mensaje "item ... does not exist", he identificado que ese item crudo nunca había sido creado en
`SFCG-WSV2-02` — a diferencia de `SFCG-WSV2-01`, donde sí existe y el item calculado funciona
correctamente. Se creó el item en `SFCG-WSV2-02`, replicando la configuración de `SFCG-WSV2-01`.
He confirmado que, tras acumular historial suficiente, el item calculado `Avg Requests (POST + GET)`
quedó `Enabled` y sin error en ambos hosts.

## 2026-08-28 12:18 — Ticket cerrado

He dado por resueltas las tres causas independientes que afectaban al item calculado en `SFCG-WSV2-02`:
set de contadores no iniciado, bug conocido de Zabbix Agent 2 (`ZBX-22463`) y item `Get Requests/Sec`
nunca creado. He dejado como seguimiento opcional, no bloqueante para este ticket: confirmar si el set de
contadores persiste iniciado tras el próximo apagado/encendido programado de `SFCG-WSV2-02`, y
evaluar una mitigación de más largo plazo si el bug `ZBX-22463` vuelve a ocurrir.
