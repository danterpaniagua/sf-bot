**Para:** PM
**Asunto:** Resumen de tareas de mantenimiento — noche del 21 al 22/09

Hola,

Resumen de lo trabajado anoche:

**Completado:**

- Rediseño completo del ciclo nocturno de mantenimiento de SmartLoyalty (índices, backup y sincronización de datos de puntos): eliminó por completo el bloqueo recurrente contra la app móvil y el sitio del club, que ya había afectado el servicio en tres oportunidades anteriores. Durante el trabajo se detectó y corrigió además una causa adicional que nadie había identificado hasta ahora — un proceso de sincronización de datos que agravaba la lentitud, especialmente los lunes — confirmada con datos reales de las últimas semanas, no solo con una corrección puntual. Como beneficio adicional, el nuevo horario libera por completo la ventana que el equipo de desarrollo usa para deploys y migraciones (8am hora local), que antes podía solaparse con estas tareas. Aplicado y verificado. [GITIN-2060](https://smartit-ar.atlassian.net/browse/GITIN-2060)
- Optimización del rebuild de índice sobre la tabla de puntos de clientes, acotándolo a la partición del año en curso en vez de la tabla completa. Aplicado y verificado. [GITIN-2061](https://smartit-ar.atlassian.net/browse/GITIN-2061)
- Confirmación de que dos índices nuevos (agregados días atrás para un fix de performance) quedan cubiertos automáticamente por el mantenimiento existente, sin acción adicional necesaria. [GITIN-2078](https://smartit-ar.atlassian.net/browse/GITIN-2078)
- Automatización completa de renovación de certificado SSL para el sitio WebSite (`gestion.clubgrido.com.ar`), ambos tramos (público y backend). Verificado en vivo. [GITIN-1771](https://smartit-ar.atlassian.net/browse/GITIN-1771)

**Evaluado y descartado:**

- Particionado de una tabla de información adicional de clientes — el diseño se completó, pero se decidió no ejecutarlo: el costo de mantenimiento real hoy es bajo y el riesgo de la migración (sobre una tabla del flujo de checkout) no se justificaba frente a un beneficio a futuro sin fecha concreta. Queda documentado para retomar si la situación cambia. [GITIN-2077](https://smartit-ar.atlassian.net/browse/GITIN-2077)

**Pendiente, no resuelto:**

- Las caídas por falta de memoria en Sales (SmartFran Cloud) siguen sin resolverse — la corrección aplicada días atrás se revirtió sola y las caídas continúan. En seguimiento activo. [GITIN-2075](https://smartit-ar.atlassian.net/browse/GITIN-2075)
- Nuevo pico de CPU en SmartLoyalty detectado anoche, en investigación — parece ser una recurrencia de un patrón ya visto meses atrás, ahora con mayor alcance. [GITIN-2087](https://smartit-ar.atlassian.net/browse/GITIN-2087)

Cualquier consulta, avisen.
