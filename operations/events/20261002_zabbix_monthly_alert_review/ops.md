# [OPE] Revisión de alertas de Zabbix — septiembre 2026

**Tags:** `Operaciones`, `Obserbavilidad`, `SRE`, `PROD`

## Resumen

El Zabbix de producción (sf-monitoreo) registró 1.801 problemas en septiembre de 2026, pero solo 25 llegaron a intentar una notificación (1 de los 198 de severidad High) y los 50 intentos por email fallaron por conexión SMTP: la mayor parte de las alertas de MobileAppService, ARCA y los avisos de "sin datos" de SSL no coincidían con ninguna acción de notificación y nadie las recibía. Además, los niveles Warning/Average/High del trío legacy de MobileAppService y de los 24 triggers de vencimiento SSL tenían las dependencias invertidas (solo el nivel más bajo podía notificar), la detección de caída brusca abría y cerraba en un minuto (230 eventos en el mes), el aviso SSL de 45 días saltaba en cada ciclo sano de renovación automática y las alertas de cola de peticiones de IIS no se evaluaban en ningún host por una macro vacía de la plantilla. Se revisaron los datos del mes (eventos, notificaciones, configuración vigente y series de tráfico, CPU y RAM de MOBI-01/02) y se rehízo la configuración de alertas de MobileAppService, SSL, ARCA y de la plantilla de IIS: ruteo a Operaciones por Google Chat, niveles y ventanas calibrados con datos reales, dependencias corregidas, un detector de caída de tráfico a nivel de servicio pensado para bloqueos del WAF de Grido, y limpieza de configuración sin uso. Todos los cambios se aplicaron con instantánea previa, verificación posterior y bloque de reversión; quedan pendientes el diagnóstico del email, la primera alerta real por Chat y la verificación de las alertas de cola de IIS tras el próximo descubrimiento.

## Tabla resumen

| Campo | Valor |
|---|---|
| Ticket Jira | [GITIN-2156](https://smartit-ar.atlassian.net/browse/GITIN-2156) |
| ID alerta | N/A — revisión mensual de alertas |
| Sistema | Zabbix 6.0.32 (sf-monitoreo.smartfran.com): alertas IIS de MobileAppService (SFCG-MOBI-01/02), vencimiento de certificados SSL, healthcheck ARCA, plantilla IIS by Zabbix agent active (12 hosts) |
| Severidad | Media |
| Detectado | 2026-10-02 (revisión del período 2026-09-01 a 2026-09-30) |
| Resuelto | Parcial — cambios aplicados y verificados por configuración; ver pendientes en Acciones propuestas |
| Responsable | Operaciones (SRE) |

## Causa raíz

La configuración de alertas no coincidía con la de notificaciones y escalamiento: las etiquetas de los triggers no satisfacían las condiciones de ninguna acción habilitada (la acción de email exige la etiqueta EMAIL, que MobileAppService y ARCA no tenían; la acción de Google Chat de Operaciones exigía a la vez los grupos LOYALTY y CLOUD, por lo que nunca coincidía), las dependencias entre niveles estaban en sentido inverso, las ventanas y umbrales eran demasiado cortos o bajos para el tráfico real, y la plantilla de IIS trae `{$IIS.QUEUE.MAX.WARN}` vacía. El envío por email falla de forma independiente por un problema de conectividad SMTP hacia aspmx.l.google.com:25 que aún no se diagnosticó.

## Hallazgos

| # | Hallazgo | Riesgo |
|---|---|---|
| H1 | De 1.801 problemas de septiembre solo 25 tuvieron un intento de notificación; las alertas de MobileAppService (IIS Spike, caída brusca, trío legacy), ARCA (DOWN, DEGRADADO, sin datos, latencia) y las de "No data" de SSL no coincidían con ninguna acción | Alto |
| H2 | Las 50 notificaciones por email de septiembre fallaron (`cannot connect to SMTP server "aspmx.l.google.com"`); las 18 de Google Chat (9 problemas más sus recuperaciones, todas de vencimiento SSL) se enviaron a un único destinatario | Alto |
| H3 | Los 8 triggers "IIS: Request queue … is too large" (WEBS-01/02/03, WSV2-01/02, WSCG-01, MOBI-01/02) estaban no soportados porque la plantilla define `{$IIS.QUEUE.MAX.WARN}` vacía; la plantilla la enlazan 12 hosts. La cola fue 0 en todos los pools monitoreados durante los últimos 7 días | Alto |
| H4 | Dependencias invertidas (Average depende de Warning, High de Average) en el trío legacy de MOBI y en los 24 triggers de vencimiento SSL: el nivel superior queda suprimido mientras el inferior está abierto. En el trío legacy solo notificó el nivel Warning (40 eventos en MOBI-02, unas 97 h abiertas en el mes, 0 eventos de Average/High aunque el promedio llegó a 123 req/s); en SSL el efecto se infiere por la semántica de dependencias, no se observó | Medio |
| H5 | MOBI IIS Spike con ventana de 3 min y umbrales por host (20/30/60 y 1,5/2,5/4 req/s): 145 eventos; el Warning de 9 req/s del trío legacy equivale al nivel normal de MOBI-02 (promedio de 5,6 req/s y percentil 90 de 9,7 req/s en septiembre). Único evento real de saturación del mes: 2026-09-04 09:23–09:58, CPU de MOBI-02 al ~100 % con ~120 req/s, detectado tarde por los umbrales anteriores y solo por la alerta nativa de CPU | Medio |
| H6 | Detección "Caída brusca" (181 eventos MOBI-02 y 49 MOBI-01, mediana 1 min): se dispara con una caída de un solo minuto y la recuperación se cumple en el minuto siguiente | Medio |
| H7 | SSL: el aviso de 45 días se dispara en cada ciclo sano de renovación automática (win-acme renueva en los últimos ~30 días de un certificado de 90); "No data … 1 day" se disparó unas 35 veces en septiembre (Website/WebServiceV2) y se abría y cerraba en el mismo minuto; el trigger High de Clubsite AR dependía del Average de FacturaSend; solo 4 de 32 triggers SSL tenían `SVC_FRIENDLYNAME` | Medio |
| H8 | ARCA DOWN (21 problemas), ARCA DEGRADADO (21) y latencia (3) de septiembre no notificaron a nadie | Alto |
| H9 | Desde el 2026-05-12 (~23:00) el tráfico de MobileAppService lo atiende SFCG-MOBI-02 (~97 % de las peticiones, medias semanales 2,4–6,7 req/s) y SFCG-MOBI-01 queda en un piso fijo de ~0,07 req/s; hasta esa fecha ocurría al revés. MOBI-02 permanece apagada ~7–10 h cada noche. La causa del cambio no está determinada | Medio |
| H10 | Dos tramos de caída del tráfico posteriores a un pico encajan con el patrón descrito para bloqueos del WAF de Grido: 2026-06-19 ~22:09 (picos de 1.221 y 1.230 req/s durante 2 minutos y luego 0,0 req/s unos 8 minutos y casi 0 unos 20, frente a ~5,5 típico) y 2026-06-21 ~15:42 (un minuto de 723 req/s y luego ~0,1 req/s por más de una hora, frente a ~7,8 típico). No está confirmado que hayan sido bloqueos del WAF | Medio |
| H11 | 31 triggers monitoreados de 10 hosts llevan `metric: POST Requests` aunque leen el contador de total de métodos (Total Method Requests/Sec); en MOBI, CLUB, WSIT y WSV2 además `service: webservice` no corresponde al servicio. Solo afecta la visualización: ninguna acción lee esas etiquetas | Bajo |
| H12 | La convención del campo `action.status` de las acciones es contradictoria entre la documentación previa y los datos de septiembre (los datos son coherentes con 0 = habilitada); no se confirmó en la interfaz | Bajo |
| H13 | El tipo de medio Telegram no tiene token configurado y ninguna acción lo usa; no hubo alertas por Telegram en septiembre | Bajo |
| H14 | El usuario de Google Chat del grupo GIT-SML pertenece solo a un grupo deshabilitado y no recibió ninguna de las 18 notificaciones; la causa no se verificó | Bajo |

## Recursos afectados

| Recurso | Tipo | Observación |
|---|---|---|
| Zabbix (sf-monitoreo.smartfran.com) | Servidor de monitoreo | Acciones 7, 8 y 10, macros globales, triggers de vencimiento SSL y ARCA |
| SFCG-MOBI-01 / SFCG-MOBI-02 | VMs MobileAppService | Triggers IIS Spike, trío legacy, caída brusca, ítem de total del servicio |
| Plantilla IIS by Zabbix agent active | Plantilla Zabbix | Prototipos de trigger de cola de IIS; 12 hosts enlazados |
| WEBS-01/02/03, WSV2-01/02, WSCG-01, CLUB-01/02, WSIT-01 | Hosts IIS | Mismos triggers de cola de IIS (heredados de la plantilla) |
| Certificados SSL de MobileAppService, ClubSite AR, ClubSite PY, Website, WebServiceV2, WebServiceCG, smartfran, FacturaSend | Triggers de vencimiento | Umbrales, dependencias, ventana "No data" y etiquetas |
| ARCA (host Zabbix server) | Healthcheck | 5 triggers sin ruteo |

## Comandos ejecutados

Las secciones de `scripts.sh` agrupan las consultas y los cambios; cada cambio tiene su bloque de reversión en el mismo archivo y su salida (instantáneas previa y posterior) se guardó en el directorio `data/` del evento.

| # | Comando / Script | Propósito |
|---|---|---|
| C1 | Extracción de eventos y notificaciones de septiembre | Solo lectura: problemas y registros de notificación del mes |
| C2 | Extracción de macros, triggers, acciones, tipos de medio y destinatarios | Solo lectura; los destinos y parámetros de los medios se enmascararon al guardarlos |
| C3 | Series de tráfico, CPU y RAM de MOBI-01/02 | Solo lectura: septiembre y abril–agosto de 2026 |
| C4 | Pasos 5 y 7 de scripts.sh ⚠️ | Macros y expresiones de los 6 triggers IIS Spike de MOBI; deshabilitación del trío legacy |
| C5 | Pasos 8, 9, 10, 11 y 17 de scripts.sh ⚠️ | Etiquetas de ruteo de los Spike y filtro de la acción 7 (Google Chat de Operaciones) |
| C6 | Paso 12 de scripts.sh ⚠️ | Contexto `:LE` (15/10/7 días) para los certificados automatizados |
| C7 | Pasos 13, 14 y 15 de scripts.sh ⚠️ | Dependencias de los 24 triggers SSL, ventana de "No data" y etiqueta `SVC_FRIENDLYNAME` |
| C8 | Paso 16 de scripts.sh ⚠️ | Eliminación de 13 macros globales sin uso, con escaneo previo de uso |
| C9 | Paso 18 de scripts.sh ⚠️ | Etiquetas de ruteo de los 5 triggers ARCA |
| C10 | Paso 19 de scripts.sh ⚠️ | Plantilla IIS: macros de cola, dos prototipos nuevos, dependencias, etiquetas y retención del ítem |
| C11 | Pasos 20, 20b y 21 de scripts.sh ⚠️ | Detector de caída de tráfico a nivel de servicio (ítem calculado y trigger nuevo) |
| C12 | Pasos 22, 23 y 24 de scripts.sh ⚠️ | Etiquetas de tarjeta (`SVC_FRIENDLYNAME`/`friendlyname`) del detector y de los Spike, y corrección de `metric`/`service` en los 7 triggers MOBI |
| C13 | Verificaciones posteriores | Solo lectura: estado de triggers no soportados y confirmación de cada cambio contra su instantánea |

## Acciones propuestas

1. **IIS Spike de MobileAppService recalibrado con datos reales** — aplicado y verificado. Mismos niveles para ambas VMs: Warning/Average/High 45/75/100 req/s, recuperación en 40, ventanas de disparo 10m/5m/3m (los niveles altos reaccionan más rápido) y de recuperación 20m, todo por macros. Resultado: en septiembre los triggers anteriores generaron 145 eventos; una simulación sobre los datos del mes (aproximada, con GET+POST como sustituto del total) da unos 5 episodios en MOBI-02 (3 de Warning, 1 de Average y 1 de High) y ninguno en MOBI-01 con los niveles nuevos. En el único evento real de saturación (2026-09-04, CPU al ~100 %) los tres niveles con las ventanas definidas (10m/5m/3m) habrían cruzado a las 09:26, 16 minutos antes de la alerta nativa de CPU de las 09:42. Se deshabilitó el trío legacy de 9/13/15 req/s en MOBI-01/02 (40 eventos y unas 97 h abiertas en MOBI-02 en septiembre, sin nivel superior alcanzable).
2. **Ruteo de alertas a Operaciones por Google Chat** — aplicado y verificado por configuración. La acción 7 pasó de exigir LOYALTY y CLOUD a la vez (nunca coincidía) a `scope = GIT-SML-OPE` y `action` contiene GCHAT y (`service_group` = LOYALTY o CLOUD), de modo que solo reciben las alertas etiquetadas explícitamente; los triggers IIS Spike de MOBI, el detector de caída de servicio, los 5 triggers ARCA y los 3 niveles de cola de IIS llevan esa etiqueta, sin email. Resultado: los grupos de alertas que en septiembre no notificaron a nadie (MobileAppService, ARCA) pasan a coincidir con una acción. La entrega real al espacio de Operaciones queda por comprobar con la primera alerta (la última entrega previa a ese espacio fue el 2026-07-27).
3. **Detector de caída de tráfico a nivel de servicio** — aplicado. Ítem calculado que suma MOBI-01 más MOBI-02 solo mientras esta última reporta (evita usar el valor viejo de una VM apagada) y trigger High que dispara con un máximo de 5 minutos ≤ 0,2 req/s si en la media hora previa hubo al menos 15 minutos por encima de 1 req/s; silencioso a propósito en horas de bajo tráfico. Etiquetas de tarjeta iguales para problema y recuperación. Resultado: reemplaza a los tres triggers anteriores de caída brusca (230 eventos en septiembre, 15 más de severidad High), que quedaron deshabilitados; en una simulación sobre abril–septiembre con datos reales el detector produjo 7 episodios en seis meses (ninguno en septiembre), entre ellos los dos tramos posteriores a un pico descritos en H10, y detectó bloques sintéticos de ceros de 10 a 90 minutos en 1-2 minutos. Aún no se observó un disparo real.
4. **Certificados SSL automatizados (MobileAppService, ClubSite AR, Website)** — aplicado. Niveles de 15/10/7 días con recuperación en 30, para que un aviso signifique que la renovación automática falló y no que el ciclo normal está en curso; los demás certificados conservan 45/30/15 hasta que su renovación esté automatizada. Dependencias corregidas en los 24 triggers de vencimiento (High sin dependencias, Average depende de High, Warning de ambos, y el High de Clubsite AR ya no depende de FacturaSend), ventana de "No data" ampliada a 2 días por macro (se esperan menos disparos espurios; no se midió todavía) y `SVC_FRIENDLYNAME` en los 32 triggers SSL.
5. **Alertas de cola de IIS reparadas en la plantilla** — aplicado; verificación posterior pendiente. La plantilla ahora define umbrales Warning/Average/High de 10/50/200 sobre una ventana de 5 minutos (antes la macro estaba vacía y ningún host evaluaba la alerta), con dependencias correctas, etiquetas de ruteo y retención del ítem a 365 días (este último cambio confirmado solo por la respuesta de la API). Confirmar, tras la próxima ejecución del descubrimiento de pools (intervalo de 1 hora), que los 8 triggers dejaron de estar no soportados y que cada pool tiene los tres niveles.
6. **Limpieza de configuración** — aplicado. Se eliminaron 13 macros globales sin uso tras comprobar que ningún trigger (incluidos los parámetros de funciones) ni ítem las referencia, y la verificación posterior no encontró triggers no soportados relacionados con ese cambio; se corrigieron además `metric` y `service` en los 7 triggers MOBI en alcance (los otros 24 con `metric` equivocado quedan como hallazgo secundario).
7. **Email de las acciones** — pendiente: diagnosticar la conectividad SMTP desde el servidor Zabbix hacia aspmx.l.google.com:25 (o definir un relay autenticado) y decidir si las alertas de vencimiento SSL siguen avisando por email a Operaciones.
8. **Confirmar con Operaciones** si 2026-06-19 ~22:09 y 2026-06-21 ~15:42 fueron bloqueos del WAF de Grido; ajustar el detector si se aportan otros momentos.
9. **Aclarar el cambio de tráfico a MOBI-02 del 2026-05-12** (cambio en balanceador, WAF, DNS, despliegue o problema en MOBI-01) y revisar el detector si el tráfico vuelve a MOBI-01.
10. **Confirmar en la interfaz la convención de `action.status`** (lista Alerts → Actions) y actualizar la documentación interna según corresponda.
11. **Origen de las alertas por Telegram:** determinar de dónde provienen, ya que el medio de Zabbix no está configurado.
12. **WebServiceV2 y WebServiceCG:** cuando su renovación esté automatizada y haya corrido una vez (GITIN-1772, GITIN-1773), pasarlos al contexto `:LE`.

### Antes / después

| Aspecto | Antes (septiembre 2026) | Después (configuración verificada) |
|---|---|---|
| Problemas con intento de notificación | 25 de 1.801 (1 de 198 High) | MobileAppService, ARCA y cola de IIS coinciden con la acción de Operaciones; entrega real por comprobar con la primera alerta |
| Alertas de ARCA | 45 problemas sin notificar | 5 triggers ruteados a Operaciones |
| Caída brusca MobileAppService | 230 eventos de ~1 minuto | 1 detector de servicio; 7 episodios en seis meses en la simulación |
| IIS Spike MobileAppService | 145 eventos, niveles distintos por VM, ventana de 3 min | Niveles 45/75/100 para ambas VMs; simulación: unos 5 episodios en septiembre en MOBI-02, ninguno en MOBI-01 |
| Trío legacy MOBI | 40 eventos y unas 97 h abiertas, niveles superiores inalcanzables | Deshabilitado |
| Vencimiento SSL (certificados automatizados) | Aviso a 45 días en cada ciclo sano; dependencias invertidas | Niveles 15/10/7 días; dependencias corregidas en 24 triggers |
| Cola de IIS | 8 triggers no soportados en 8 hosts | Macros definidas y 3 niveles en la plantilla (12 hosts); verificación tras el descubrimiento pendiente |
| Macros globales sin uso | 13 | 0 (eliminadas) |

## Hallazgos secundarios

- 24 triggers de otros 9 hosts (CLUB-01/02, WEBS-01/02/03, WSIT-01, WSV2-01/02), además del trío legacy deshabilitado de MOBI, siguen con `metric: POST Requests` aunque leen el contador de total de métodos; en CLUB, WSIT y WSV2 `service: webservice` tampoco corresponde. WSCG-01 está bien etiquetado (`metric: Total Requests`).
- 11 triggers no soportados ajenos a esta revisión: 7 de `sfcg-monitoreo` (procesos internos del proxy y el agente Linux por `{$AGENT.TIMEOUT}`), 2 de velocidad de eth0 en el servidor Zabbix y 2 de ECS en `smartfran-pedidos-dev`.
- Unos 30 reinicios de host cada uno en MOBI-02, WSIT-01, WEBS-02 y WEBS-03 (16 en CLUB-02) con problemas asociados de agente, puerto y WAS en la franja 00:00–03:00; MOBI-02 tiene apagado nocturno conocido, la causa en los demás hosts no está verificada.
- 48 problemas de HTTP 4XX y 31 de 5XX del ALB en el servidor Zabbix, sin identificar a qué ALB corresponden.
- Problemas abiertos por mucho tiempo: Port 443 down y agente no disponible en CLUB-02 (~152 h), "WebServiceV2. HTTP Code not 200" (~199 h) e "items having missing data" (hasta ~153 h).
- Ningún problema de septiembre fue reconocido (0 de 1.801).
