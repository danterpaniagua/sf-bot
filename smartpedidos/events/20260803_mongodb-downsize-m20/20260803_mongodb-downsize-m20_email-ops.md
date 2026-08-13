Asunto: MongoDB Atlas (PedidosSmartfran) — propuesta de reintentar M20, esta vez con monitoreo activo

Hola equipo,

Les escribo para seguir con el tema del downsize M30 → M20 en `PedidosSmartfran` (el cluster de producción de SmartPedidos). El detalle completo está en GITIN-1741 (https://smartit-ar.atlassian.net/browse/GITIN-1741), pero acá va el resumen.

**Contexto:** esto ya se había probado una vez, el 19 de enero, y se revirtió dos días después — la CPU subió a ~35% (contra un 15-25% normal) y la RAM quedó limitada muy por debajo de lo que ofrece M20, que es la señal real de que la caché estaba bajo presión. Esa prueba fue el motivo por el que se mantuvo M30.

**Qué cambió desde entonces:** el tamaño de índices de `ordertimes` bajó cerca de un 76% respecto a enero, y desde hace dos semanas (20/7) ambos servicios dejaron de escribir por completo a la colección `logerrors`. Sacando métricas frescas de Cache Usage y Disk IOPS hoy, la caché real de WiredTiger topea en ~1.2-1.5 GB por réplica con páginas dirty prácticamente insignificantes, y los read IOPS a disco están cerca de cero — es decir, casi nada está cayendo a disco en este momento. Es un panorama bastante distinto al que sugerían los números de RAM del sistema operativo por sí solos, y no parece que la caché esté bajo presión real hoy.

**Propuesta:** creo que vale la pena reintentar M20, pero esta vez con monitoreo activo desde el arranque en vez de evaluar después del hecho. Como hay una falla real previa registrada, prefiero que lo sigamos de cerca en vez de asumir que los números de hoy se sostienen una vez que estemos efectivamente en el tier más chico.

Lo que propongo monitorear, usando las mismas señales que marcaron el problema en enero:
- CPU sostenida por encima de ~30-35% (fue lo que gatilló la reversión de enero)
- Read IOPS a disco subiendo desde el baseline casi nulo que vemos hoy — es la señal más clara de presión de eviction en la caché
- Cualquier degradación de latencia perceptible en platforms-service o concentrador-service

Si aparece alguna de esas señales, lo trataría como indicio claro para volver a M30, igual que la vez anterior — la idea es que sea un cambio reversible y bien vigilado, no un compromiso de una sola vía.

Avisen si les parece razonable este enfoque, o si prefieren armar algo más formal (por ejemplo una ventana canary) antes de comprometernos del todo.

Aparte, y como algo separado de este cambio puntual: durante esta investigación encontramos sobre-indexación bastante marcada en `branches` (índices ~10x el tamaño de los datos) y el mismo patrón existía en `logerrors` antes de limpiar sus índices hoy. Propongo que hagamos un re-análisis de queries e índices en las colecciones principales antes de la próxima temporada de pico, para llegar con margen de caché real y no solo con lo que alcanza hoy. Lo dejo planteado, no hace falta resolverlo en este ticket.

Saludos,
Dante
