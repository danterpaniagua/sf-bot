# GITIN-2238 — [SML] Mobile: Alerta Healthcheck

**Tags:** `SmartLoyalty`, `MobileAppService`, `SRE`, `PROD`

## Qué pasó

- El 2026-10-15, PediGrido informó por WhatsApp (12:14, hora de Argentina) que las llamadas a MobileAppService fallaban desde las 09:18 y que a las 10:58 seguían sin respuestas exitosas. Fue el único servicio afectado, según Operaciones.
- Las métricas del balanceador `SFCG-MOBI-LB` muestran los dos servidores (`SFCG-MOBI-01` y `SFCG-MOBI-02`) con disponibilidad 0 % entre las 09:18 y las 12:25 (alrededor de 3 horas y 7 minutos); el frontend volvió a estar disponible a las 12:31.
- Operaciones dio por terminado el despliegue en producción a las 09:32. QA informó a las 10:18 que todo estaba correcto en producción; no se verificó si esa validación incluía MobileAppService.
- No existía ninguna alerta sobre el healthcheck de MobileAppService: crearla era una tarea pendiente de Operaciones que no se realizó a tiempo, por lo que el incidente se conoció por el aviso del cliente.

## Resumen

El 15 de octubre MobileAppService estuvo indisponible alrededor de 3 horas y afectó a PediGrido. Según Operaciones, la causa fue la eliminación por error del archivo de healthcheck del que depende el balanceador durante el despliegue en producción; al restaurar los archivos el servicio volvió a responder. No había una alerta para este caso. Se restauró el archivo, se midió la caída en el balanceador, se crearon alertas en Zabbix (GITIN-2239) y, según Operaciones, se envió el correo de estado al cliente y a los interesados internos. Queda pendiente definir cómo evitar que el archivo se elimine en un despliegue, ampliar la validación de QA, medir el episodio previo que informó el cliente y confirmar que las alertas nuevas notifican.

## Tabla resumen

| Campo | Valor |
|---|---|
| Ticket Jira | [GITIN-2238](https://smartit-ar.atlassian.net/browse/GITIN-2238) |
| ID alerta | NA |
| Sistema | MobileAppService (`SFCG-MOBI-01`, `SFCG-MOBI-02`) y su balanceador `SFCG-MOBI-LB` |
| Severidad | Por definir |
| Detectado | 2026-10-15 12:14 (hora de Argentina), por aviso del cliente |
| Resuelto | Servicio restaurado; los servidores volvieron al balanceador a las 12:25. Prevención y alertas pendientes de confirmar (ver Acciones propuestas) |
| Responsable | SRE |

## Causa raíz

El archivo `healthcheck.ashx`, que la sonda del balanceador usa para saber si cada servidor está disponible, se eliminó por error durante el despliegue en producción, aunque estaba incluido en el proceso de despliegue (según Operaciones). Sin ese archivo los dos servidores salieron del balanceador al mismo tiempo. La causa la confirmó Operaciones al restaurar los archivos y ver que el servicio volvía a responder; las métricas del balanceador (disponibilidad en 0 % en ambos servidores) son consistentes con ese mecanismo pero no indican por sí mismas por qué falló la sonda.

Ocurrencias anteriores: PediGrido informó un episodio más corto el mismo día (06:14 a 06:55) que se recuperó solo; coincide con una ventana en la que Operaciones realiza tareas de mantenimiento y no se midió. En las métricas del balanceador hay además caídas breves de `SFCG-MOBI-02` antes de la caída (08:47 a 09:08, hora de Argentina) cuya causa no se investigó. No se identificó otro incidente anterior con la misma causa.

## Hallazgos

| # | Hallazgo | Riesgo |
|---|---|---|
| H1 | Ambos servidores quedaron con disponibilidad 0 % en la sonda del balanceador: `SFCG-MOBI-01` de 09:19 a 12:25 (187 minutos) y `SFCG-MOBI-02` de 09:18 a 12:25 (188 minutos); el frontend, de 09:20 a 12:31. El inicio coincide con lo informado por PediGrido (09:18). | Alto |
| H2 | No existía una alerta sobre el healthcheck de MobileAppService: el escenario web de Zabbix `[PROD] MobileApp` tenía un paso `healthcheck` pero ningún trigger asociado. | Alto |
| H3 | La validación de QA posterior al despliegue (10:18) informó que todo estaba correcto mientras el servicio estaba indisponible; no se verificó si incluía MobileAppService. | Medio |
| H4 | El balanceador tiene definidas tres sondas (`SFCG-MOBI-LB-probe02` TCP 8043, `SFCG-MOBI-LB-probe01` HTTP 8043 y `healthcheck.ashx` HTTP 8080); no se leyó cuál usa la regla de balanceo. | Bajo |
| H5 | Caídas breves de `SFCG-MOBI-02` antes de la caída (11:47 a 12:08 UTC) y de un minuto después (15:28 a 15:49 UTC) sin causa investigada. | Bajo |
| H6 | Las alertas nuevas (GITIN-2239) están creadas, pero desde las 19:04 UTC ningún evento de Zabbix genera notificaciones; la causa se investiga en GITIN-2222 y la hipótesis principal es un filtro de etiquetas en un grupo de usuarios del destinatario (no probada). | Alto |

## Acciones Tomadas (hora UTC)

| # | Hora | Acción |
|---|---|---|
| 1 | 2026-10-15 15:25 (aprox.) | Restauración del archivo de healthcheck en los servidores de MobileAppService por Operaciones; los dos servidores volvieron a estar disponibles en el balanceador a las 15:25. La hora exacta de la restauración no se registró. |
| 2 | 2026-10-15 18:50 | Lectura de las métricas del balanceador (disponibilidad por servidor y del frontend, 11:30 a 16:30 UTC) para medir la caída. |
| 3 | 2026-10-15 16:38 a 17:57 | Creación de alertas en Zabbix para los healthchecks de MobileAppService y WebServiceV2 y para la existencia del archivo en cada servidor ([GITIN-2239](https://smartit-ar.atlassian.net/browse/GITIN-2239)). |
| 4 | 2026-10-15 | Correo de estado preparado para los interesados internos y correo breve para PediGrido; Operaciones indicó que el correo fue enviado (no se registra el texto final ni los destinatarios). |
| 5 | 2026-10-15 | Apertura de la investigación del episodio previo de 06:14 a 06:55, aún sin mediciones. |

## Recursos afectados

| Componente | Estado |
|---|---|
| MobileAppService (`SFCG-MOBI-01`, `SFCG-MOBI-02`) | Indisponible de 09:18 a 12:25 (hora de Argentina); restaurado |
| Balanceador `SFCG-MOBI-LB` | Sin servidores sanos durante la caída; sin cambios de configuración en este ticket |
| Zabbix (host `sfcg-monitoreo` y los cuatro servidores) | Alertas nuevas creadas (GITIN-2239); entrega de notificaciones sin confirmar |

## Acciones propuestas

| # | Responsable | Acción | Estado |
|---|---|---|---|
| 1 | SRE | Definir cómo evitar que el archivo de healthcheck se elimine por error en un despliegue (por ejemplo, verificar que el healthcheck responde al terminar cada despliegue). | Pendiente |
| 2 | SRE / QA | Incluir en la validación de QA en producción la verificación de que todos los servicios estén activos: WSV2, WSV1, WSCG, Mobile, WebSite y ClubSite. | Pendiente |
| 3 | SRE | Medir el episodio previo de 06:14 a 06:55 y las caídas breves de `SFCG-MOBI-02` en las métricas del balanceador y en Zabbix. | Pendiente |
| 4 | SRE | Confirmar con una notificación real que las alertas nuevas llegan al Chat de Operaciones (depende de la causa investigada en GITIN-2222). | Pendiente |
| 5 | SRE | Leer cuál sonda usa la regla de balanceo y decidir si conviene mantener las tres. | Pendiente |
