Asunto: Estado — Revisión de índices MongoDB, SmartPedidos (GITIN-1744 / GITIN-2006)

Hola,

Detectado: patrones de consulta con volumen de escaneo alto y creciente, sostenidos durante más de un mes de relevamiento, en el módulo de estado de sucursales por plataforma (Concentrador y Platform) y en el de métricas de tiempos de pedido (Concentrador y Platform).

Corregido: se aplicaron las tres optimizaciones de mayor impacto identificadas para esos patrones.

Pendiente: dos optimizaciones adicionales de menor impacto por aplicar; una consulta de métricas que nunca devuelve resultados, en revisión con Desarrollo antes de decidir si se optimiza o se retira; y monitoreo del uso de recursos de la base de datos (CPU, memoria, lecturas a disco) en los próximos días, dado que la creación de estos índices es un cambio de estructura considerable sobre colecciones de alto volumen bajo el ajuste de capacidad hecho meses atrás por optimización de costos, y su efecto sobre el consumo de recursos todavía no fue relevado. Los datos actuales no identifican componentes sin uso que puedan liberarse.

| Proyecto | Componente | Índice creado | Antes | Después |
|---|---|---|---|---|
| Concentrador / Platform | Estado de sucursales por plataforma | `alreadyClosedPediGrido:1, lastGetNews:1` | Sin optimizar, escaneo completo por consulta | Optimizado |
| Concentrador / Platform | Estado de sucursales por plataforma | `address.country:1, alreadyClosedPeya:1, platforms.StateAPI:1, platforms.platform:1` | Sin optimizar, escaneo completo por consulta | Optimizado |
| Concentrador / Platform | Métricas de tiempos de pedido | `latencyTimestamp.finalResponseDate:1, platformDate:1, receiveSqsDate:1, responseDate:1, sendSqsDate:1, entryDate:1` | Sin optimizar, escaneo completo por consulta | Optimizado |

Más información: https://smartit-ar.atlassian.net/browse/GITIN-1744, https://smartit-ar.atlassian.net/browse/GITIN-2006.

Saludos,
Dante
