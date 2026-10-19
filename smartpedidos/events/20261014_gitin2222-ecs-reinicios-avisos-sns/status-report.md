Asunto: GITIN-2222 y subtareas: estado

Hola,

Les compartimos el estado de [GITIN-2222](https://smartit-ar.atlassian.net/browse/GITIN-2222) y de sus subtareas. El estado de cada punto es el que figura en su ticket.

*Realizado:*

   - [GITIN-2222](https://smartit-ar.atlassian.net/browse/GITIN-2222) — Paradas de tareas de Platform y exceso de avisos. Estado: parcial.
      - Análisis de la causa: las paradas pasaron de 5 a 17 por día a 97 el 13-10 y 101 el 14-10.
      - Los avisos de las paradas (más de 6.500 correos en 10 días) ahora incluyen el motivo.
      - Alerta en Zabbix cuando hay menos tareas en ejecución que las deseadas, verificada con eventos reales.

   - [GITIN-2229](https://smartit-ar.atlassian.net/browse/GITIN-2229) — Alerta de errores críticos (FATAL) de Platform en Zabbix, verificada con eventos reales. Estado: parcial.

   - [GITIN-2240](https://smartit-ar.atlassian.net/browse/GITIN-2240) — La misma alerta para Concentrador, creada; se activará cuando Desarrollo agregue el registro de errores críticos. Estado: parcial.

   - Los avisos de producción llegan al espacio de Operaciones en Chat y a un grupo de Telegram.

*Reportado a Desarrollo:*

   - Reportamos el defecto en el código de Platform (tres puntos). Desarrollo desarrolló la corrección, incorporada a la rama de desarrollo el 16-10, y según nos informaron el despliegue fue realizado.
   - La corrección cubre uno de los tres puntos (40 de los 63 eventos de error). Los otros dos siguen abiertos (23 de los 63 eventos corresponden a uno de ellos) y con ellos las paradas pueden continuar.
   - [GITIN-2240](https://smartit-ar.atlassian.net/browse/GITIN-2240): el registro de errores críticos en Concentrador queda a cargo de Desarrollo ([GITIN-1477](https://smartit-ar.atlassian.net/browse/GITIN-1477)).

*Inconvenientes detectados:*

   - El 15-10, durante unos 30 minutos, Zabbix no generó avisos. La causa no está probada.

*Pendientes:*

   - Comprobar el efecto de la corrección con las alertas.
   - Analizar con Desarrollo el impacto de los dos puntos del código de Platform que siguen sin corregir: está comprobado que pueden provocar la caída de contenedores.
   - Registro de errores críticos en Concentrador (Desarrollo) y comprobación de la alerta de [GITIN-2240](https://smartit-ar.atlassian.net/browse/GITIN-2240).
   - Determinar la causa del intervalo sin avisos del 15-10.

*Tareas post-despliegue:*

Monitoreamos los contenedores y las alertas desde el despliegue; hasta ahora no se detectó ninguna caída nueva de contenedores.

Continuaremos con el monitoreo durante el día para comparar los errores críticos y las paradas, antes y después de la corrección.

Saludos.
