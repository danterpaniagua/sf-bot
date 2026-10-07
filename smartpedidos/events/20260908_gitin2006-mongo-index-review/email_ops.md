Asunto: Revisión de índices MongoDB (PedidosSmartfran) — GITIN-2006

Hola equipo,

Les cuento el estado de la revisión de índices del cluster `PedidosSmartfran` (GITIN-2006, https://smartit-ar.atlassian.net/browse/GITIN-2006, dentro de GITIN-1857). Es el seguimiento que habíamos dejado planteado en GITIN-1741 (downsize a M20) para volver a mirar índices con más margen, ahora retomado formalmente como ticket propio.

**Contexto rápido:** ya habíamos arrancado este análisis en agosto (GITIN-1744), pero lo pausamos a propósito para que los datos de uso de Atlas se levantaran ya estabilizados en M20, sin mezclar el período de transición. Retomamos ahora, con más de un mes de datos limpios.

**Lo que encontramos:**
- `logerrors` quedó en cero documentos — consistente con la migración de logging a Graylog que ya sabíamos que estaba en curso, no es una sorpresa ni algo a investigar. Esto también resuelve un pendiente: ya no hace falta reponer el índice que se había eliminado ahí en agosto, porque la colección no tiene tráfico de consultas real.
- Encontramos patrones de consulta con volumen de escaneo alto y creciente en `branches` (relacionado a chequeos de estado por plataforma) y en `ordertimes` (relacionado a métricas de latencia), confirmados de forma consistente en tres relevamientos sucesivos a lo largo de más de un mes, no como algo puntual. Ya aplicamos los tres índices de mayor impacto para cubrir esos patrones.
- Quedan dos índices adicionales identificados con el mismo criterio, de menor volumen — los vamos a aplicar como parte del mantenimiento en curso.
- Encontramos una consulta sobre `ordertimesavgcrons` que escanea la colección completa en cada ejecución pero nunca devuelve resultados, de forma consistente en los tres relevamientos. Antes de indexarla a ciegas, preferimos confirmar con Dev si es una consulta obsoleta que convendría directamente sacar de uso.
- La lista de índices no utilizados que habíamos armado en agosto (unos 145 MB entre 16 índices) ya no se sostiene con los datos actuales de Atlas — hoy no hay ningún índice marcado como candidato a eliminar. No queda claro todavía si es porque genuinamente se empezaron a usar o porque la ventana de medición se reinició en algún momento; no vamos a tocar nada de esa lista sin volver a confirmarlo.

**Un pedido de seguimiento, relacionado con el downsize de GITIN-1741:** el tamaño total de índices en `ordertimes` creció bastante desde agosto (independientemente de los tres que acabamos de sumar), y vamos a seguir sumando algunos más como mantenimiento. Los tres índices ya creados son un cambio de estructura sobre `branches` y `ordertimes` (>370K documentos cada una) del que solo confirmamos que quedaron creados (vía `getIndexes()`), sin chequear CPU/caché/lecturas a disco durante o después del build. Dado que seguimos en M20, propongo que mantengamos monitoreado el comportamiento de tamaño y uso de caché del cluster en las próximas semanas — las mismas señales que ya veníamos mirando en GITIN-1741 (CPU, presión de eviction / lecturas a disco) — para confirmar que el tier actual sigue siendo adecuado tanto por este cambio puntual como por el crecimiento general del volumen de índices.

Saludos,
Dante
