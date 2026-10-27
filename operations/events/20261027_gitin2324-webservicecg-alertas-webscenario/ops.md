# [GITIN-2324](https://smartit-ar.atlassian.net/browse/GITIN-2324) — [OPE] WebServiceCG: Alertas y WebScenario

**Tags:** `Operaciones`, `WebserviceCG`, `Obserbavilidad`, `SRE`, `PROD`, `PREPRO`, `TEST02`

## Qué pasó

- WebServiceCG no tenía ningún web scenario propio en PROD: el 2026-10-27 a las 14:57 UTC no existía un web scenario con "WebServiceCG" en su nombre en ningún host de Zabbix.
- En Test02 el web scenario `Loyalty Test02` tenía un step `WebServiceCG` (step 7), y en PreProd el web scenario `Loyalty PreProd` (8 steps) no tenía ninguno para WebServiceCG.
- Ningún trigger colgaba de los items de `Loyalty Test02` ni de `Loyalty PreProd` (lectura de las 14:51 UTC), por lo que una respuesta distinta de 200 del endpoint de WebServiceCG no generaba ninguna alerta en ningún entorno.

## Resumen

WebServiceCG no tenía monitoreo de disponibilidad por HTTP en Zabbix: ni un web scenario en PROD, ni un step en PreProd, y ningún trigger sobre el step de Test02, así que una respuesta distinta de 200 en `/swagger/ui/index` no alertaba. Se agregaron los web scenarios en PROD, Test02 y PreProd sobre el host `sfcg-monitoreo` (10610) y un trigger por entorno que se activa cuando el endpoint no responde 200: severidad High con tag `env:PROD` en PROD, e Information con tag `env:DEV` en Test02 y PreProd. A las 16:22 UTC los tres endpoints respondían 200 y los tres triggers estaban en estado OK.

## Tabla resumen

| Campo | Valor |
|---|---|
| Ticket Jira | [GITIN-2324](https://smartit-ar.atlassian.net/browse/GITIN-2324) |
| ID alerta | NA |
| Sistema | Zabbix (`sf-monitoreo.smartfran.com`), host `sfcg-monitoreo`; WebServiceCG PROD / Test02 / PreProd |
| Severidad | High (PROD) / Information (Test02, PreProd) |
| Detectado | 2026-10-27 |
| Resuelto | 2026-10-27 (monitoreo activo; ver Acciones propuestas) |
| Responsable | SRE |

## Causa raíz

NA

## Hallazgos

| # | Hallazgo | Riesgo |
|---|---|---|
| H1 | En `Loyalty Test02` el step 7 `WebServiceCG` apunta a `https://azsl-webservicev2-test02.smartfran.com:805/swagger/ui/index` (host `azsl-webservicev2-test02`), no a `azsl-webservicecg-test02` como la URL indicada en el ticket. Responde 200 en unos 0,03 s. Con `follow_redirects` desactivado y `retrieve_mode` 2 (solo headers). | Medio |
| H2 | Antes del cambio no había triggers sobre los items de `Loyalty Test02` ni de `Loyalty PreProd`. | Medio |
| H3 | `web.test.fail` guarda el número del primer step que falla y los steps siguientes no se ejecutan: si falla un step anterior, el de WebServiceCG no se evalúa. Los triggers de Test02 y PreProd miran además el item `web.test.rspcode` del propio step. | Bajo |
| H4 | Los web scenarios del host tienen `verify_peer` y `verify_host` desactivados (ya era así en los 16 existentes y se mantuvo en los nuevos), por lo que un problema de certificado no hace fallar el scenario. | Bajo |

## Acciones Tomadas

| # | Hora (UTC) | Acción |
|---|---|---|
| 1 | Antes de las 15:05 | Creado el web scenario `[PROD] WebServiceCG` (httptestid 21) en `sfcg-monitoreo`, con un step `swagger` contra `https://bot-security.smartfran.com/swagger/ui/index` (200, timeout 15 s, intervalo 1m, 1 retry). |
| 2 | Antes de las 15:05 | Agregado el step 9 `WebServiceCG` (`https://azsl-webservicecg-preprod.smartfran.com:8185/swagger/ui/index`) al web scenario `Loyalty PreProd`. |
| 3 | 15:07 | Creado el trigger `WebServiceCG PROD: swagger no responde 200` (id 27069), High, tags `env:PROD`, `service_group:LOYALTY`. Se activa si el response code del step es distinto de 200, o si el scenario falla, en 2 checks consecutivos. Operational data: código HTTP. |
| 4 | 15:08 | Creados los triggers `WebServiceCG Test02: swagger no responde 200` (id 27070) y `WebServiceCG PreProd: swagger no responde 200` (id 27071), Information, tags `env:DEV`, `service_group:LOYALTY`. Misma condición que el de PROD, más el número de step (7 en Test02, 9 en PreProd). |
| 5 | 15:20 y 16:22 | Verificación: `web.test.rspcode` = 200 y `web.test.fail` = 0 en los tres scenarios, y los tres triggers con valor 0 y estado normal. |

Ruteo (lectura del 14:54 UTC): la action 12 `Notify OPERACIONES env PROD (Chat + Telegram)` está habilitada y filtra solo por `env = PROD`, por lo que el trigger de PROD notifica por ahí. Ninguna otra action de triggers tiene una condición sobre el tag `env`, así que los triggers `env:DEV` quedan visibles en Zabbix y no notifican.

## Recursos afectados

| Recurso | Detalle |
|---|---|
| Host Zabbix `sfcg-monitoreo` (10610) | Web scenarios `[PROD] WebServiceCG`, `Loyalty Test02`, `Loyalty PreProd` y los triggers 27069, 27070, 27071 |
| Proxy `sfcg-monitoreo` (10609) | Ejecuta los web scenarios |
| WebServiceCG PROD | `https://bot-security.smartfran.com/swagger/ui/index` |
| WebServiceCG Test02 | `https://azsl-webservicecg-test02.smartfran.com:805/swagger/ui/index` |
| WebServiceCG PreProd | `https://azsl-webservicecg-preprod.smartfran.com:8185/swagger/ui/index` |

## Acciones propuestas

| # | Responsable | Acción | Estado |
|---|---|---|---|
| 1 | SRE | Definir si el step 7 de `Loyalty Test02` debe apuntar a `azsl-webservicecg-test02.smartfran.com:805` (como en el ticket) o mantener el host `azsl-webservicev2-test02`, y corregirlo si corresponde. | Por decidir |
| 2 | SRE | Confirmar que cada trigger se activa ante una falla real (non-200 o timeout) en la primera ocurrencia, ya que hasta ahora ningún trigger se disparó. | Pendiente |
