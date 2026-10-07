Asunto: Actualización de seguridad en librerías de SmartPedidos — GITIN-2000 / GITIN-2002

Hola,

Un escaneo de seguridad automatizado sobre Concentrador y Platform detectó las mismas vulnerabilidades conocidas en ambos, en dos librerías de terceros con parches ya publicados por sus autores.

En los dos sistemas, la corrección aplicada resolvió por completo el uso que la aplicación en sí hace de la librería con la vulnerabilidad de severidad crítica. Un análisis posterior encontró que la misma vulnerabilidad también está presente en una herramienta interna del entorno de ejecución (no en el código de la aplicación ni en algo que la aplicación ejecuta en su operación normal), que la corrección aplicada no cubre. Se está evaluando cómo resolver ese punto sin introducir un cambio de mayor alcance en el entorno base de ambos sistemas.

La segunda, en la librería usada para las comunicaciones con las integraciones de plataformas externas de pedidos, quedó parcialmente resuelta en ambos casos: la corrección aplicada cubre el riesgo más urgente, pero deja un riesgo residual de menor severidad. Cerrarlo del todo requiere una actualización mayor de esa librería, que se evaluó y **se puede realizar, sujeta a una revisión de impacto de código antes de aplicarla** — esa evaluación se hizo sobre uno de los dos sistemas y no encontró incompatibilidades con ninguna integración de plataformas en uso; la misma evaluación para el segundo sistema queda pendiente. Todavía no está decidido si se avanza con esa actualización.

Adicionalmente, en Platform se identificaron otras librerías con vulnerabilidades conocidas: dos relacionadas con autenticación y manejo de tokens, cuya corrección requiere una actualización de mayor alcance con revisión de código (no solo un cambio de versión), y una tercera que ya no tiene ninguna corrección disponible por parte de sus autores, para la cual la única solución real es dejar de depender de ella. Ninguna de las tres fue abordada todavía; quedan como un trabajo aparte, sin alcance ni prioridad definidos aún.

No hay impacto identificado sobre el flujo de pedidos ni sobre la disponibilidad del servicio a partir de ninguno de estos hallazgos, en ningún caso.

Resumen del estado por sistema:

| Sistema | Vulnerabilidad | Estado |
|---|---|---|
| Concentrador | Severidad crítica (uso de la aplicación) | Corregido |
| Concentrador | Severidad crítica (herramienta interna del entorno) | En evaluación |
| Concentrador | Comunicaciones con plataformas externas | Parcialmente corregido |
| Platform | Severidad crítica (uso de la aplicación) | Corregido |
| Platform | Severidad crítica (herramienta interna del entorno) | En evaluación |
| Platform | Comunicaciones con plataformas externas | Parcialmente corregido |
| Platform | Autenticación y manejo de tokens | Pendiente, requiere revisión de código |
| Platform | Librería sin corrección disponible | Pendiente, requiere reemplazo |

Más información: https://smartit-ar.atlassian.net/browse/GITIN-2000 y https://smartit-ar.atlassian.net/browse/GITIN-2002.

Saludos,
Dante
