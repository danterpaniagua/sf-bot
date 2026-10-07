# GITIN-1956 — Zabbix: item calculado de IIS sin datos en SFCG-WSV2-02 (Post/Get Requests/Sec)

**Tags:** `SmartLoyalty`, `Azure`, `SRE`, `INFRADEVOPS`, `PROD`

## Resumen

El item calculado del template `IIS by Zabbix agent active` (`Avg Requests (POST + GET)`), que suma
`Post Requests/Sec` + `Get Requests/Sec` para el sitio `SmartLoyalty.WebServiceV2`, reportaba error
en el host `SFCG-WSV2-02`. La investigación encontró **tres problemas independientes**, cada uno
necesario de corregir para que el item calculado volviera a evaluar correctamente: el set de
contadores de rendimiento "Web Service" de Windows no estaba iniciado en la VM; un bug conocido de
Zabbix Agent 2 (`ZBX-22463`) impedía que el item crudo `Post Requests/Sec` recolectara datos aun con
el set de contadores activo; y el item crudo `Get Requests/Sec` nunca había sido creado en este host,
a diferencia de `SFCG-WSV2-01`. Los tres se corrigieron el 2026-08-28; el item calculado quedó
`Enabled` y sin error en ambos hosts.

## Tabla resumen

| Campo | Valor |
|---|---|
| Ticket Jira | [GITIN-1956](https://smartit-ar.atlassian.net/browse/GITIN-1956) |
| Caso | Item calculado de Zabbix (IIS Requests/Sec) sin datos en `SFCG-WSV2-02` |
| Plataforma | Zabbix (`sf-monitoreo.smartfran.com`) — template `IIS by Zabbix agent active`, host `SFCG-WSV2-02` |
| Severidad | Baja — brecha de observabilidad (item de monitoreo sin datos), sin impacto en el servicio real |
| Detectado | 2026-08-28 |
| Resuelto | 2026-08-28 |
| Responsable | Dante Paniagua |

## Causa raíz

Tres causas independientes, todas necesarias para explicar el error observado:

1. **Set de contadores "Web Service" no iniciado en `SFCG-WSV2-02`.** Sin ese set activo, Windows no
   exponía ninguna instancia `\Web Service(SmartLoyalty.WebServiceV2)\...`, por lo que ningún item
   crudo `perf_counter_en` podía recolectar datos. Corregido iniciando el set de contadores.
2. **Bug conocido de Zabbix Agent 2 (`ZBX-22463` — "Detected performance counter with negative
   denominator ... giving up").** Aun con el set de contadores activo y la instancia disponible, el
   agente fallaba en calcular la tasa del contador `Post Requests/Sec` en cada intento de sondeo,
   dejando el item crudo sin ningún valor. El log del agente muestra un corte breve de conectividad
   hacia el proxy Zabbix (`172.191.99.60:10051`) la noche anterior (2026-08-27 23:20), seguido horas
   después por las primeras fallas de este tipo — posible disparador, no confirmado como causa. La
   solución documentada por la comunidad (reinicio del servicio del agente) resolvió el problema en
   este host.
3. **Item crudo `Get Requests/Sec` nunca creado en `SFCG-WSV2-02`.** A diferencia de `Post
   Requests/Sec`, este item no formaba parte de la configuración clonada desde `SFCG-WSV2-01` durante
   la incorporación de monitoreo documentada en `GITIN-1238` — brecha pre-existente, no introducida
   por este ticket. Corregido creando el item en `SFCG-WSV2-02`, replicando la configuración de
   `SFCG-WSV2-01`.

La macro `{$IIS.APP.NAME}` fue verificada idéntica en ambos hosts desde el inicio de la investigación
y descartada como causa.

## Hallazgos

| # | Hallazgo | Riesgo |
|---|---|---|
| H1 | El set de contadores de rendimiento "Web Service" no estaba iniciado en `SFCG-WSV2-02` | Bajo |
| H2 | El item crudo `Post Requests/Sec` en `SFCG-WSV2-02` quedaba atrapado por el bug conocido de Zabbix Agent 2 `ZBX-22463`, sin recolectar datos hasta reiniciar el servicio del agente | Bajo |
| H3 | El item crudo `Get Requests/Sec` nunca fue creado en `SFCG-WSV2-02` — brecha en la configuración clonada desde `SFCG-WSV2-01` (`GITIN-1238`) | Bajo |

## Recursos afectados

| Recurso | Detalle |
|---|---|
| `SFCG-WSV2-02` | VM — set de contadores iniciado, servicio del agente Zabbix reiniciado, item `Get Requests/Sec` creado |
| Item calculado `Avg Requests (POST + GET)` (`IIS by Zabbix agent active`) | Restablecido — `Enabled`, sin error, en ambos hosts |

## Métricas del evento

| Métrica | Valor |
|---|---|
| Host afectado | `SFCG-WSV2-02` (host hermano `SFCG-WSV2-01` no afectado) |
| Instancia IIS confirmada | `SmartLoyalty.WebServiceV2` |
| Secuencia de errores observada | `item ... does not exist` → (tras iniciar el set de contadores) `not enough data` (Post) → (tras reiniciar el agente) valor real en Post, `item ... Get Requests/Sec ... does not exist` → (tras crear el item) `not enough data` (Get) → item calculado `Enabled` en ambos hosts |
| Bug de Zabbix Agent 2 identificado | `ZBX-22463` (Windows, contadores IIS/rendimiento) |

## Acciones propuestas

1. (Realizado) Se inició el set de contadores de rendimiento "Web Service" en `SFCG-WSV2-02`.
2. (Realizado) Se reinició el servicio Zabbix Agent 2 en `SFCG-WSV2-02` para resolver el bug conocido `ZBX-22463`.
3. (Realizado) Se creó el item crudo `Get Requests/Sec` en `SFCG-WSV2-02`, replicando la configuración de `SFCG-WSV2-01`.
4. (Pendiente, opcional) Confirmar si el set de contadores "Web Service" persiste iniciado tras el
   próximo ciclo de apagado/encendido programado de `SFCG-WSV2-02` (ventana 00:00–09:00 UTC-3, ver
   `GITIN-1238`) — si no persiste, definir una corrección permanente (arranque automático) para
   evitar que el problema se repita en cada ciclo.
5. (Pendiente, opcional) El bug `ZBX-22463` está documentado como intermitente en reportes de la
   comunidad de Zabbix; si vuelve a ocurrir en este host o en otros, considerar una mitigación de más
   largo plazo (reinicio automático del servicio ante fallo) en lugar de tratar cada recurrencia como
   un incidente nuevo.

## Archivos de evidencia

| Archivo | Contenido |
|---|---|
| `investigation.md` | Registro completo de la investigación, las tres causas identificadas y su corrección |

## Hallazgos secundarios

- El item `Get Requests/Sec` en `SFCG-WSV2-01` tiene un nombre inconsistente respecto al de `Post
  Requests/Sec` (`IIS Method GET requests per second` vs. `SmartLoyalty.WebServiceV2: IIS Method
  POST requests per second`) — inconsistencia de nomenclatura preexistente, no introducida por este
  ticket, sin impacto funcional. No corregida aquí.
