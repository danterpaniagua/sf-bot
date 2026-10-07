Asunto: GITIN-1964 — seguimiento antes del desescalado de concentrador-service (hoy 31/08)

Hola equipo,

Retomo GITIN-1964 (picos de CPU en concentrador-service, 29/08). El ticket quedó cerrado con una mitigación de capacidad aplicada ese mismo día (task definition `256/512` → `1024 CPU/2048 MB`), pero esa mitigación es temporal: el desescalado a la capacidad original está programado para hoy, 31/08.

La causa raíz no está corregida todavía. El proceso que sincroniza el estado de las sucursales con PedidosYa dispara, en cada horario configurado, una consulta y actualización contra la API de PedidosYa por cada sucursal activa del país (más de 1.100 actualmente) sin ningún límite de concurrencia ni agrupamiento en lotes, a través del cliente HTTP compartido del servicio, que tampoco tiene timeout configurado — mismo defecto ya señalado en GITIN-1783. Ese patrón es el que generó los picos de CPU de este ticket.

Si el desescalado se aplica hoy sin que este punto esté resuelto, concentrador-service vuelve a quedar sin ninguna mitigación vigente frente al mismo patrón, en el próximo horario en que se dispare la sincronización.

Puntos que quedaron identificados como necesarios en GITIN-1964:
- Acotar la concurrencia del proceso de sincronización con PedidosYa en lugar de procesar todas las sucursales activas en simultáneo.
- Agregar timeout al cliente HTTP compartido de concentrador-service.
- Evaluar una sincronización incremental (solo sucursales con cambios desde la última corrida) en lugar de reprocesar la totalidad de la flota en cada disparo.

Quedo atento a coordinar si conviene sostener la capacidad ampliada hasta tener estos puntos resueltos, o si ya están en curso y el desescalado de hoy puede seguir como estaba programado. Más detalle técnico en GITIN-1964.

Saludos,
Dante
