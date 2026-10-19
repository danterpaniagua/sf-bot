# Borrador 3 — email de mejoras de monitoreo (SmartLoyalty)

**Asunto:** Monitoreo de SmartLoyalty: lo que mejoramos desde la caída de Mobile y lo que sigue

Hola equipo,

La caída de MobileAppService del 15-10 ([GITIN-2238](https://smartit-ar.atlassian.net/browse/GITIN-2238)) ocurrió sin que ninguna alerta avisara. Les resumo lo que hicimos en Zabbix desde entonces.

## Alertas creadas

Las alertas 1 a 8 llevan la etiqueta `env: PROD` y avisan al espacio de Operaciones en Chat y al grupo de Telegram, con aviso de problema y de recuperación. Las alertas 9 a 11 usarán las mismas etiquetas cuando se creen.

| # | Alerta | Servidor / escenario | Qué vigila | Severidad | Estado |
|---|---|---|---|---|---|
| 1 | Healthcheck [PROD] MobileApp: HTTP code not 200 | Escenario web `[PROD] MobileApp` | Que el healthcheck responda 200 (código distinto de 200 o sin respuesta) | Alta | Activa; no se probó con un fallo real |
| 2 | Healthcheck [PROD] MobileApp: slow response | Escenario web `[PROD] MobileApp` | Tiempo de respuesta del healthcheck por encima de 2 s (promedio de 5 minutos) | Advertencia | Activa y probada (aviso de problema y de recuperación) |
| 3 | Healthcheck [PROD] WebServiceV2: HTTP code not 200 | Escenario web `[PROD] WebServiceV2` | Que el healthcheck responda 200 (código distinto de 200 o sin respuesta) | Alta | Activa; no se probó con un fallo real |
| 4 | Healthcheck [PROD] WebServiceV2: slow response | Escenario web `[PROD] WebServiceV2` | Tiempo de respuesta del healthcheck por encima de 2 s (promedio de 5 minutos) | Advertencia | Activa y probada (aviso de problema y de recuperación) |
| 5 | Healthcheck file missing on SFCG-MOBI-01 | SFCG-MOBI-01 | Que exista `healthcheck.ashx` (falta durante 2 minutos) | Alta | Activa; el control lee que el archivo existe; no se probó la falta real |
| 6 | Healthcheck file missing on SFCG-MOBI-02 | SFCG-MOBI-02 | Que exista `healthcheck.ashx` (falta durante 2 minutos) | Alta | Activa; el control lee que el archivo existe; no se probó la falta real |
| 7 | Healthcheck file missing on SFCG-WSV2-01 | SFCG-WSV2-01 | Que exista `healthcheck.ashx` (falta durante 2 minutos) | Alta | Activa; el control lee que el archivo existe; no se probó la falta real |
| 8 | Healthcheck file missing on SFCG-WSV2-02 | SFCG-WSV2-02 | Que exista `healthcheck.ashx` (falta durante 2 minutos) | Alta | Activa; el control lee que el archivo existe; no se probó la falta real |
| 9 | Healthcheck file missing on SFCG-WEBS-01 | SFCG-WEBS-01 | Que exista `healthcheck.ashx` | Alta | Control creado, sin datos todavía; alerta pendiente |
| 10 | Healthcheck file missing on SFCG-WEBS-02 | SFCG-WEBS-02 | Que exista `healthcheck.ashx` | Alta | Control creado, sin datos todavía; alerta pendiente |
| 11 | Healthcheck file missing on SFCG-WEBS-03 | SFCG-WEBS-03 | Que exista `healthcheck.ashx` | Alta | Control creado, sin datos todavía; alerta pendiente |

Los umbrales están en macros del host y se ajustan sin tocar los triggers ([GITIN-2239](https://smartit-ar.atlassian.net/browse/GITIN-2239)). El archivo `healthcheck.ashx` es la sonda del balanceador: si falta, el servidor deja de recibir tráfico.

**Verificación:** forzamos las alertas de respuesta lenta (2 y 4) bajando temporalmente el umbral y comprobamos que llegan los avisos de problema y de recuperación al Chat de Operaciones. Luego se restauró el umbral. Las alertas 1, 3 y 5 a 8 no se probaron con un fallo real del healthcheck ni con la falta real del archivo.

## Cómo llegan los avisos

- Los avisos de los triggers marcados como producción (`env: PROD`) llegan al espacio de Operaciones en Chat y, además, a un grupo de Telegram (los envía un usuario dedicado de Zabbix).
- Las tarjetas muestran el nombre del servicio (por ejemplo, "Servicio Healthcheck MobileApp degradado") en lugar de un texto sin resolver.

## Escenarios web y verificación de despliegues

Los escenarios web de Zabbix fueron diseñados para validar y probar funcionalidades de las aplicaciones, por lo que también sirven para medir si un despliegue fue exitoso. QA tiene acceso a ellos y puede agregar las modificaciones que necesite.

| Escenario | Recorrido |
|---|---|
| MobileApp (PROD) | healthcheck → Login → GetAdditionalInformation |
| ClubSite AR y PY (PROD) | Landing → GetAllBenefits |
| PreProd y Test02 | ClubSite AR y PY, Mobile, Website, WebService y WebServiceV2 (Test02 también WebServiceCG) |

Revisamos los escenarios de PreProd y Test02 y corregimos tres detalles: un paso de prueba sobrante en PreProd, una URL de ClubSite AR en Test02 que apuntaba a la de PY, y un paso de ClubSite PY en Test02 que no seguía redirecciones.

## En curso

- **WebService (SFCG-WEBS-01/02/03):** alertas 9 a 11 de la tabla. Los controles están creados, pero todavía no devolvieron datos, así que los triggers no están activos; estoy revisando el motivo.
- **Consistencia de `Unity.config`:** relevé los diez servidores de aplicación. En las aplicaciones de MobileAppService, WebService, WebServiceV2, WebServiceCG, WebSite y TaskOperatorService el archivo es idéntico. Queda definir dos alertas: una cuando cambia en alguna aplicación y otra, que se cierre manualmente, cuando dejan de ser iguales. Falta confirmar si `MigrateDataBase` (TaskOperator), que tiene una versión distinta del archivo, entra en el alcance.
- **`healthcheck.ashx` de SFCG-WEBS-01:** estaba en una versión distinta de la de WEBS-02/03 (la de WEBS-01 comprobaba la base de datos y Redis y siempre respondía 200; la de WEBS-02/03 mide CPU y memoria y responde 400 por encima del 80 %). Se dejó en WEBS-01 la misma versión que en WEBS-02/03 y se comprobó que los tres archivos son idénticos. Queda por confirmar con el equipo de la aplicación que ese es el comportamiento esperado.

## Pendiente

- Decidir si se deshabilitan los dos triggers antiguos de WebServiceV2, que no notifican a ningún chat y quedan cubiertos por los nuevos.
- Verificar que el `healthcheck.ashx` de SFCG-WSV2-02 sobrevive al apagado nocturno de esa VM.
- Revisar el umbral de respuesta lenta con datos reales de las próximas semanas.
- Evitar la eliminación accidental del archivo de healthcheck (GITIN-2238).

Quedo atento a sus comentarios, en especial sobre las alertas de `Unity.config`.

Saludos,
Dante Paniagua
SRE
