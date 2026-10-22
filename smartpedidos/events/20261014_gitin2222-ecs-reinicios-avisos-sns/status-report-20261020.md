Asunto: GITIN-2222 y GITIN-2248: estado tras el despliegue del 20-10

Hola,

Les comparto el estado de [GITIN-2222](https://smartit-ar.atlassian.net/browse/GITIN-2222) y [GITIN-2248](https://smartit-ar.atlassian.net/browse/GITIN-2248) después del despliegue de hoy.

*Detectado:* los contenedores de Platform se detenían por errores del propio código de Platform, uno de ellos dentro del sistema de registro de errores, que fallaba al procesar ciertos errores.

*Corregido:* se aplicaron dos cambios en Platform: ayer (19-10) el del manejo de errores críticos, y hoy (20-10) el del registro de errores. Según lo observado después de los despliegues, las correcciones aplicadas funcionaron y la cantidad de tareas en ejecución volvió a la normalidad.

*Pendiente:* seguir observando los contenedores y las alertas durante los próximos días para confirmar que no vuelven las caídas; definir con Desarrollo qué debe hacer Platform ante un error no capturado (hoy, en el código, el proceso ya no se detiene después de registrar el error crítico).

*Tabla de cambios:*

| Proyecto | Componente | Antes | Después | Ticket |
|---|---|---|---|---|
| Platform | Registro de errores (hoy, 20-10) | Un error con una estructura que se referencia a sí misma hacía fallar al propio registro | El registro ya no falla por ese motivo | [GITIN-2222](https://smartit-ar.atlassian.net/browse/GITIN-2222), [GITIN-2248](https://smartit-ar.atlassian.net/browse/GITIN-2248) |
| Platform | Manejo de errores críticos (ayer, 19-10) | El proceso se detenía después de registrar el error crítico | El proceso sigue en ejecución después de registrarlo | [GITIN-2222](https://smartit-ar.atlassian.net/browse/GITIN-2222), [GITIN-2248](https://smartit-ar.atlassian.net/browse/GITIN-2248) |

*Inconvenientes detectados:* NA

*Mejoras propuestas:*

   - Ejecutar la verificación previa de calidad en SonarQube y Jenkins y revisar su reporte antes de cada despliegue: el de hoy se hizo sin ejecutarla ni mirar el reporte, y el pull request se creó en ese momento, lo que resultó en un despliegue largo.
   - Que las ramas y los pull requests lleven el id del ticket: los nombres actuales no permiten rastrear a qué ticket pertenece cada cambio (la rama de hoy se llamó «logs22»; el cambio de ayer y el de hoy solo se distinguen por la causa que corrigen).

*Impacto:* la cantidad de tareas en ejecución de Platform se normalizó después del despliegue. No se midió el efecto sobre el flujo de pedidos.

Saludos.
