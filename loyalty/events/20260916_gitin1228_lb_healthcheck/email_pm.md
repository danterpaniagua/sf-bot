Asunto: Mejora de confiabilidad — Mobile y WebServiceV2

Hola,

Les cuento sobre una mejora que implementamos en la infraestructura que da soporte a la app Mobile de Club Grido y a WebServiceV2 (SmartCloud): reforzamos la forma en que el sistema detecta si un servidor está funcionando correctamente.

Hasta ahora, el mecanismo de control solo verificaba que el servidor estuviera "encendido" — no tenía forma de saber si realmente estaba respondiendo bien o si tenía algún problema de rendimiento. Con esta mejora, el sistema ahora monitorea el estado real de cada servidor de forma continua, y puede redirigir el tráfico automáticamente si detecta que uno de ellos no está funcionando como debería.

**¿Por qué esto importa?** Esta mejora reduce el riesgo de que un problema puntual en un servidor pase desapercibido y afecte la experiencia de los usuarios finales — tanto en la app Mobile como en las operaciones que corren sobre WebServiceV2.

El cambio ya está aplicado y validado en producción, sin impacto en el servicio durante la implementación.

Más información: [GITIN-1228](https://smartit-ar.atlassian.net/browse/GITIN-1228) (Mobile), [GITIN-2058](https://smartit-ar.atlassian.net/browse/GITIN-2058) (WebServiceV2).

Saludos,
Dante
