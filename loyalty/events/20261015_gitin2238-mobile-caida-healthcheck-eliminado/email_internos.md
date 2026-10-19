**Asunto:** Estado del despliegue v13.01.00 e incidente de MobileAppService con PediGrido del 15-10

Hola,

Les comparto el estado del despliegue de la versión v13.01.00:

*Tareas realizadas:*

   - Despliegue en producción, finalizado a las 09:32.
   - Validación de QA en producción, informada como correcta a las 10:18.

*Inconvenientes detectados:*

   - El archivo de healthcheck del que depende el balanceador de MobileAppService estaba incluido en el proceso de despliegue y se eliminó por error durante el mismo. Esto afectó a PediGrido: según sus registros, la falla empezó a las 09:18 y a las 10:58 seguía sin respuestas exitosas. Restauramos los archivos y el servicio volvió a responder, lo que confirma la causa. Según las métricas del balanceador, ninguno de los dos servidores de MobileAppService recibió tráfico entre las 09:18 y las 12:25 (alrededor de 3 horas y 7 minutos); el frontend volvió a estar disponible a las 12:31. Detalle en [GITIN-2238](https://smartit-ar.atlassian.net/browse/GITIN-2238).
   - No existía una alerta sobre el healthcheck de MobileAppService. Crearla era una tarea pendiente nuestra que no realizamos a tiempo, por lo que nos enteramos por PediGrido vía WhatsApp.
   - La validación de QA posterior al despliegue no detectó la falla. No verificamos si esa validación incluía MobileAppService.
   - Las alertas nuevas están creadas, pero todavía no confirmamos con una notificación real que llegan al Chat.

*Pendientes:*

   - Confirmar con las métricas del balanceador que el episodio anterior que informó PediGrido (06:14 a 06:55) corresponde a las tareas de mantenimiento que hacemos en ese horario; hoy no está medido.
   - Definir cómo evitar que el archivo se elimine por error en un despliegue (por ejemplo, verificar que el healthcheck responde al terminar cada despliegue).
   - Incluir en la validación de QA en producción la verificación de que todos los servicios estén activos: WSV2, WSV1, WSCG, Mobile, WebSite y ClubSite.
   - Confirmar la llegada de las alertas nuevas y decidir qué hacer con los dos triggers anteriores de WebServiceV2.
   - Responder a PediGrido con el estado y la causa.

*Tareas post-despliegue:*

   - Restauración del archivo de healthcheck en los servidores de MobileAppService.
   - Creación de una alerta en Zabbix (severidad High) sobre la existencia del archivo de healthcheck en los servidores de MobileAppService y WebServiceV2, para detectar su eliminación por sí sola ([GITIN-2239](https://smartit-ar.atlassian.net/browse/GITIN-2239)).
   - Creación de triggers en Zabbix para los healthchecks de MobileAppService y WebServiceV2 ([GITIN-2239](https://smartit-ar.atlassian.net/browse/GITIN-2239)): severidad High cuando la respuesta no es 200 o no hay respuesta, y Warning cuando la respuesta es lenta. Los umbrales están en macros y las alertas se dirigen al Chat de Operaciones.

Saludos.
