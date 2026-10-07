Asunto: Estado — Seguridad de librerías, Concentrador y Platform (GITIN-2000 / GITIN-2002)

Hola,

Detectado: vulnerabilidades en dos librerías de terceros, en Concentrador y Platform.

Corregido: la vulnerabilidad crítica del lado de la aplicación, en ambos.

Pendiente: actualización completa de una de las librerías (ambos, viable pero sujeta a revisión de impacto de código, no decidida aún); la misma vulnerabilidad crítica en una herramienta del entorno de ejecución (ambos); dos librerías adicionales que requieren revisión de código y una sin corrección disponible (solo Platform).

| Proyecto | Paquete | Versión anterior | Versión actual |
|---|---|---|---|
| Concentrador | tar | 6.2.1 | latest (se actualiza automáticamente) |
| Concentrador | axios | 0.26.1 | 1.13.6 |
| Platform | tar | 6.2.1 | latest (se actualiza automáticamente) |
| Platform | axios | 0.26.1 | 1.13.6 |

Sin impacto en el flujo de pedidos ni en la disponibilidad del servicio.

Más información: https://smartit-ar.atlassian.net/browse/GITIN-2000, https://smartit-ar.atlassian.net/browse/GITIN-2002.

Saludos,
Dante
