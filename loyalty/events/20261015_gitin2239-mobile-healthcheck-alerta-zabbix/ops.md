# GITIN-2239 — [OPE] Creacion de trigger para healthchecks

**Tags:** `Operaciones`, `MobileAppService`, `Obserbavilidad`, `SRE`, `PROD`

## Qué pasó

- Tras la caída de MobileAppService del 2026-10-15 ([GITIN-2238](https://smartit-ar.atlassian.net/browse/GITIN-2238)), que no tenía ninguna alerta, se pidió crear triggers para todos los healthchecks: severidad High cuando la respuesta no es 200 y Warning cuando la respuesta es lenta.
- Zabbix solo tiene dos escenarios web con un paso de healthcheck, ambos de producción y en el host `sfcg-monitoreo`: `[PROD] MobileApp` (cada 30 segundos) y `[PROD] WebServiceV2` (cada minuto).
- El de MobileApp no tenía triggers. El de WebServiceV2 tenía dos (`WebServiceV2 Response Time > 100ms` y `WebServiceV2. HTTP Code not 200`), sin etiquetas de enrutamiento, por lo que no notifican a ningún chat.

## Resumen

Los healthchecks de MobileAppService y WebServiceV2 no tenían alertas que notificaran: el de Mobile no tenía ninguno y los de WebServiceV2 no tienen etiquetas. Se crearon triggers de código de respuesta (High) y de respuesta lenta (Warning) para ambos, con los umbrales en macros, y una alerta High sobre la existencia del archivo `healthcheck.ashx` en cada uno de los cuatro servidores. Se verificó que los triggers disparan y se recuperan con los valores previstos, pero no se pudo confirmar que las notificaciones lleguen al Chat de Operaciones: desde las 19:04 UTC ningún evento de Zabbix genera notificaciones, problema que se investiga en GITIN-2222. Quedan pendientes esa confirmación y la decisión sobre los dos triggers antiguos de WebServiceV2.

## Tabla resumen

| Campo | Valor |
|---|---|
| Ticket Jira | [GITIN-2239](https://smartit-ar.atlassian.net/browse/GITIN-2239) (subtarea de [GITIN-2238](https://smartit-ar.atlassian.net/browse/GITIN-2238)) |
| ID alerta | NA |
| Sistema | Zabbix: host `sfcg-monitoreo` y los servidores `SFCG-MOBI-01`, `SFCG-MOBI-02`, `SFCG-WSV2-01`, `SFCG-WSV2-02` |
| Severidad | Por definir |
| Detectado | 2026-10-15 |
| Resuelto | Parcial: triggers creados y verificados; entrega de notificaciones sin confirmar |
| Responsable | SRE |

## Causa raíz

NA

## Hallazgos

| # | Hallazgo | Riesgo |
|---|---|---|
| H1 | El escenario `[PROD] MobileApp` no tenía triggers y los dos de `[PROD] WebServiceV2` (ids 26860 y 26861) no tienen etiquetas, por lo que ninguno notifica. Un caso anterior, GITIN-2025 (código 500 en WebServiceV2 durante 8 días sin reconocer), es el mismo patrón. | Alto |
| H2 | El trigger 26861 solo dispara con un código mayor que 220 promediado en 20 minutos; una caída sin respuesta (tiempo de espera o conexión cortada) no actualiza el código y probablemente no lo dispara (no probado). | Medio |
| H3 | El trigger 26860 tiene un umbral de 100 sobre un item que mide segundos (valores de 0,02 a 12 s en 30 días): con esa unidad no puede dispararse (no se leyó la función exacta). | Bajo |
| H4 | El tiempo de respuesta normal de ambos healthchecks es de unos 0,55 s (percentil 95 de los promedios horarios 0,57 s) con picos aislados cercanos a 12 s en 30 días; se fijó el umbral de respuesta lenta en 2 s sobre el promedio de 5 minutos. | Bajo |
| H5 | El archivo de healthcheck de `SFCG-WSV2-02` está en la unidad `E:` (en los otros tres servidores está en `D:`); esa VM se apaga todas las noches y se desconoce si el archivo sobrevive a ese ciclo; si falta, el trigger de archivo lo avisa. | Medio |
| H6 | Desde las 19:04 UTC ningún evento de Zabbix genera notificaciones, incluidos los de estas alertas y el de Graylog FATAL, que notificaba hasta las 18:00 UTC. El único cambio en ese intervalo sobre el destinatario es su incorporación, a las 18:08 UTC, a un grupo de usuarios con filtros de etiquetas (GITIN-2222); no está probado que sea la causa. | Alto |

## Acciones Tomadas (hora UTC)

| # | Hora | Acción |
|---|---|---|
| 1 | 2026-10-15 16:38 | Macros de host `HC.*` (umbrales y ventanas) y cuatro triggers sobre los healthchecks, con las etiquetas de enrutamiento al Chat de Operaciones y las de título de tarjeta: "código distinto de 200 o sin respuesta" (High, 26921 y 26923) y "respuesta lenta" (Warning, 26922 y 26924, dependiente del anterior). |
| 2 | 2026-10-15 17:05 a 17:57 | Items de existencia del archivo en los cuatro servidores y cuatro triggers High "Healthcheck file missing on <servidor>" (26925 a 26928); items con valor 1 en los cuatro. |
| 3 | 2026-10-15 19:06 a 19:10 | Prueba controlada: se bajó temporalmente el umbral de respuesta lenta a 0,01 s; los dos triggers de Warning dispararon y se recuperaron al restaurarlo a 2 s. No se generaron notificaciones (ver H6). |
| 4 | 2026-10-15 19:33 | (GITIN-2222) Se retiró al usuario destinatario de las alertas del grupo de usuarios con filtros de etiquetas, para comprobar si ese grupo impedía las notificaciones. |
| 5 | 2026-10-15 19:39 a 19:51 | Segunda prueba controlada (mismo procedimiento que la 3): los dos triggers de Warning dispararon, Zabbix generó 2 notificaciones y las marcó como enviadas; la macro se restauró a 2 s y los triggers se recuperaron. La llegada al Chat no se informó en esa prueba. |
| 6 | 2026-10-15 23:52 | Se agregó la etiqueta `env=PROD` a los 8 triggers (26921 a 26928), con lectura posterior de las etiquetas, para que además notifiquen por la acción que envía las alertas `env=PROD` al espacio de Operaciones por Chat y por Telegram. |
| 7 | 2026-10-15 23:57 a 2026-10-16 00:00 | Tercera prueba controlada con la etiqueta `env=PROD` puesta: los dos triggers de Warning dispararon y se recuperaron al restaurar el umbral a 2 s. Zabbix generó las notificaciones de ambas acciones (Chat y Telegram) y las marcó como enviadas, sin errores. El usuario informó que los mensajes de alerta están llegando. |

## Recursos afectados

| Componente | Estado |
|---|---|
| Zabbix, host `sfcg-monitoreo` | Macros `HC.*` y cuatro triggers de healthcheck creados |
| Zabbix, hosts `SFCG-MOBI-01/02` y `SFCG-WSV2-01/02` | Items y triggers de existencia del archivo creados |
| Triggers 26860 y 26861 (WebServiceV2) | Sin cambios; activos y sin etiquetas |

## Acciones propuestas

| # | Responsable | Acción | Estado |
|---|---|---|---|
| 1 | SRE | Resolver la falta de notificaciones desde las 19:04 UTC (GITIN-2222) y repetir la prueba de entrega confirmando los mensajes en el Chat de Operaciones. | Pendiente |
| 2 | SRE | Decidir si se deshabilitan los triggers 26860 y 26861 de WebServiceV2, que no notifican y quedan cubiertos por los nuevos (se deshabilitan, no se borran, para conservar el historial). | Por decidir |
| 3 | SRE | Verificar que el archivo de `SFCG-WSV2-02` sobrevive al apagado nocturno de la VM (unidad `E:`). | Pendiente |
| 4 | SRE | Revisar el umbral de respuesta lenta (2 s) y la ventana de fallas (3 en 3 minutos) con datos reales de las próximas semanas. | Pendiente |
