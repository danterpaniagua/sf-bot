# GITIN-1468 — [CLOUD] Graylog dedicado para SmartCloud: centralización de logs de App Services

**Tags:** `SmartCloud`, `Graylog`, `Azure`, `EventHubs`, `SRE`, `PROD`

## Qué pasó

- Los logs de los App Services de SmartCloud estaban repartidos en workspaces de Log Analytics, sin una vista unificada para correlacionar eventos y responder a incidentes.
- El costo mensual de Log Analytics fue de USD 679 en junio 2026 (Cost Analysis de Azure, mes cerrado), con unos 37 millones de eventos por día medidos en 7 apps; `AppServiceConsoleLogs` representó el 70,5 % del volumen.
- El stack Docker de Graylog que sirve a SmartPedidos y SmartLoyalty ya estaba al límite (OpenSearch al 81,6 % de su memoria y swap en uso al 2026-06-25), por lo que no era una base para sumar el volumen de SmartCloud.

## Resumen

Se construyó un Graylog dedicado a SmartCloud, independiente del stack Docker existente: una VM Ubuntu 24.04 en East US 2 (Graylog 7.1.3, OpenSearch, MongoDB, nginx con certificado Let's Encrypt), aprovisionada con Terraform, que recibe los logs de los App Services a través de Azure Event Hubs (un hub compartido `app-logs`) y Logstash, sin cambios de código en las aplicaciones. Según los registros del proyecto (última actualización 2026-09-15), están incorporados los 8 App Services de PRO, las 8 apps del nivel DEV y los 4 Function Apps de PRO, cada uno con su stream e índice dedicado, y las categorías de HTTP logs separadas en streams propios. En el camino se resolvieron fallas reales del pipeline (formato de los lotes de Azure, conflictos de mapeo, campo `event_original` por encima del límite de Lucene, Diagnostic Settings sobrescritos por Terraform). Este resumen se arma con la documentación del proyecto: no se volvió a consultar Azure ni Graylog para esta redacción. Quedan abiertos puntos de seguridad y operación (rotación de claves expuestas, vencimiento del certificado, reglas de red iniciales, verbosidad de logs de consola) y varias confirmaciones pendientes, listadas en las acciones propuestas.

## Tabla resumen

| Campo | Valor |
|---|---|
| Ticket Jira | [GITIN-1468](https://smartit-ar.atlassian.net/browse/GITIN-1468) |
| ID alerta | NA |
| Sistema | Graylog dedicado SmartCloud (VM `smartfran-graylog-pro`), Azure Event Hubs, Logstash, App Services y Function Apps de SmartCloud |
| Severidad | NA (proyecto de infraestructura) |
| Detectado / Iniciado | 2026-06-25 |
| Resuelto | Parcial: pipeline operativo y apps incorporadas según los registros; puntos abiertos en las acciones propuestas |
| Responsable | SRE |

## Causa raíz

NA

## Hallazgos

| # | Hallazgo | Riesgo |
|---|---|---|
| H1 | Costo real de Log Analytics: USD 679 en junio 2026 (Cost Analysis), por encima de la estimación inicial de unos USD 345 hecha con precios de lista; coincide con facturar todo el volumen medido (~289 GB en 29 días) a USD 2,30/GB sin franquicia. Estimaciones de la infraestructura de Graylog: flota completa unos USD 911/mes pay-as-you-go y unos USD 609/mes con reserva de 1 año; piloto unos USD 312 y USD 205. Con reserva queda por debajo de lo que cuesta Log Analytics hoy; con pay-as-you-go queda por encima. Los ahorros son prospectivos: Log Analytics sigue activo en paralelo y falta el desglose de costo por app. | Medio |
| H2 | Azure Monitor exige que el namespace de Event Hub esté en la misma región que el recurso monitoreado. El primer `terraform apply` con el namespace en East US 2 (región de la VM) falló con 400; se resolvió con una variable de región propia para el namespace (East US). La VM lee el hub entre regiones sin restricción. | Medio — Resuelto |
| H3 | Azure no siempre envuelve `records` en un arreglo (un lote de un solo registro llega como objeto), el filtro `split` de Logstash no promueve los campos al nivel superior y `properties` llegaba a veces como objeto y a veces como texto: conflictos de mapeo en OpenSearch con unos 14.936 mensajes fallidos en el piloto. Corregido en el pipeline; validado con datos reales de Sales. | Alto — Resuelto |
| H4 | Al incorporar Business, el campo `event_original` (el lote completo de Event Hub en cada documento) superó el máximo de Lucene de 32.766 bytes (hasta 131.479 bytes observados) y causó más de 60.000 fallas de indexación. Corregido el 2026-07-02: el campo guarda solo el JSON del registro; después del cambio el input mostró 0 errores. | Alto — Resuelto |
| H5 | Los Diagnostic Settings de Azure se reemplazan completos por nombre (no suman): al aplicar Terraform para Pos, Platform, Admin y Catalog se sobrescribieron sus Diagnostic Settings de Log Analytics preexistentes. Se corrigió consolidando ambos destinos en el mismo recurso de Terraform (GITIN-1834) y se corrigió una referencia a una suscripción de workspace inexistente. | Alto — Resuelto |
| H6 | El Input Setup Wizard de Graylog, al asociar el input GELF a un stream, crea una regla de pipeline oculta que enruta todos los mensajes a ese stream sin evaluar las reglas del stream. Con un input compartido por todas las apps habría enviado todo el tráfico al stream de Sales. Se recreó el input sin ruteo en el asistente. | Alto — Resuelto |
| H7 | El disco de datos de OpenSearch (128 GB) no quedó en `/etc/fstab` y, tras un reinicio no detectado, OpenSearch pasó a escribir en el disco raíz de 63 GB sin ninguna señal de error. Se detectó de forma indirecta durante el diagnóstico de fallas de indexación; se montó el disco y se agregó a `fstab`. | Medio — Resuelto |
| H8 | Al incorporar Business no llegó ningún mensaje a Graylog durante cerca de una hora y luego los datos empezaron a fluir sin aplicar ningún cambio de red. La hipótesis principal (`vnetRouteAllEnabled: true` en su integración de VNet) nunca se confirmó; la causa no está explicada. Mensajes de Business, incluidos HTTP logs, llegan con normalidad desde entonces. | Medio — Sin explicar |
| H9 | Tras incorporar las 8 apps de PRO (GITIN-1834), Catalog pasó a dominar el volumen: 86,7 % de una ventana de 15 minutos (62.809 de 72.485 mensajes). Se trata de la verbosidad de `AppServiceConsoleLogs` (relación de 160 a 1 contra los pedidos HTTP reales), no de tráfico. Es la palanca de costo más grande y requiere coordinación con Desarrollo. | Alto |
| H10 | La clave SAS de lectura del hub (`logstash-listen`) y la clave de la cuenta de almacenamiento de checkpoints se pegaron en texto plano varias veces durante el diagnóstico de julio. Los registros del proyecto indican que debían rotarse si no se había hecho; no se encontró confirmación de la rotación. | Alto — Sin verificar |
| H11 | Al aprovisionar la VM, los puertos SSH y web de Graylog quedaron abiertos a todo Internet en forma temporal para el acceso inicial. Los registros posteriores indican que Graylog escucha solo en loopback y que el acceso externo es por nginx en el puerto 443, pero no registran si las reglas del grupo de seguridad de red se cerraron. | Alto — Sin verificar |
| H12 | El certificado de Let's Encrypt de `sfcloud-monitoreo` figura con vencimiento el 2026-09-28 y la renovación automática de certbot figura activa. Esa fecha ya pasó y no se verificó que la renovación se haya hecho. | Medio — Sin verificar |
| H13 | Function Apps de PRO (GITIN-1946 y GITIN-2050): la categoría `FunctionAppLogs` tiene un esquema distinto al de los App Services; `properties` usa la sintaxis de diccionario de Python y no JSON, por lo que los campos no se promovían. El campo `name` queda en mayúsculas en Graylog y una búsqueda con otra capitalización devuelve 0 resultados sin error. La entrega a Graylog se confirmó para los 4 slots de producción; los slots `stg2` y el stream de TicketProcess con tráfico real no se confirmaron. | Medio |
| H14 | Hay dos versiones del pipeline de Logstash que pueden confundirse: la copia del repositorio quedó desactualizada respecto de la desplegada (le faltaba el cambio de GITIN-2034) y tiene las cadenas de conexión redactadas. Desplegarla tal cual habría revertido un cambio y roto la conexión al Event Hub. | Alto — Detectado antes de desplegar |

## Acciones Tomadas

Fechas según los registros del proyecto (UTC); no se volvieron a verificar para esta redacción.

| # | Hora (UTC) | Acción |
|---|---|---|
| 1 | 2026-06-25 | Medición de volumen por categoría (7 días, 7 apps) y estimación de dimensionamiento y costos para piloto y flota completa. |
| 2 | 2026-06-30 | Aprovisionamiento con Terraform de la VM, red, discos y namespace de Event Hub; instalación del stack Graylog (MongoDB, OpenSearch, Graylog, nginx con certificado). |
| 3 | 2026-07-01 | Despliegue de Logstash en la misma VM y validación del piloto con Sales de punta a punta, para los dos esquemas de log (aplicación y HTTP). |
| 4 | 2026-07-02 | Incorporación de Business y corrección del campo `event_original`. |
| 5 | 2026-07-03 | Revisión de facturación con el costo real de Log Analytics y separación de índices y streams por servicio. |
| 6 | 2026-08-10 | Incorporación del nivel DEV (8 apps, otra suscripción) con stream e índice propios (GITIN-1794). |
| 7 | 2026-08-12 | Incorporación de las 8 apps de PRO, con stream e índice dedicados por app y corrección de la sobrescritura de Diagnostic Settings (GITIN-1834). |
| 8 | 2026-08-25 y 2026-08-26 | Habilitación de `AppServiceHTTPLogs` en las 8 apps y separación en streams e índices dedicados con retención de 7 días (GITIN-1937, GITIN-1940). |
| 9 | 2026-08-26 y 2026-09-15 | Incorporación de los Function Apps de PRO a Graylog: tres de ellos en GITIN-1946 y los cuatro, con stream e índice por app y confirmación de entrega de los slots de producción, en GITIN-2050. |

## Recursos afectados

| Componente | Estado |
|---|---|
| Graylog dedicado (VM `smartfran-graylog-pro`, East US 2) | Operativo según los registros; certificado, red y claves sin verificar (H10 a H12) |
| Event Hub `app-logs` (namespace `smartfran-graylog-evhns-pro`, East US) | Compartido por todas las apps incorporadas; 2 unidades de rendimiento en la fase de flota completa |
| Logstash (misma VM) | Operativo según los registros; la copia del pipeline en el repositorio está desactualizada (H14) |
| 8 App Services de PRO | Incorporados (GITIN-1834) |
| 8 apps de DEV | Incorporadas (GITIN-1794), un único stream compartido |
| 4 Function Apps de PRO | Incorporados; slots `stg2` sin confirmar (GITIN-1946, GITIN-2050) |
| Log Analytics `SmartFranCloudPro` | Sigue activo en paralelo; sin dar de baja |
| Graylog Docker (SmartPedidos y SmartLoyalty) | Fuera de alcance; sin cambios |

## Acciones propuestas

| # | Responsable | Acción | Estado |
|---|---|---|---|
| 1 | SRE | Rotar la clave SAS `logstash-listen` y la clave de la cuenta de checkpoints, y actualizar Logstash con los valores nuevos (H10). | Pendiente (rotación no confirmada) |
| 2 | SRE | Verificar el certificado de `sfcloud-monitoreo` y la renovación de certbot, cuyo vencimiento anotado ya pasó (H12). | Pendiente |
| 3 | SRE | Verificar que las reglas del grupo de seguridad de red de la VM ya no exponen SSH ni el puerto web de Graylog a todo Internet (H11). | Pendiente |
| 4 | Dev | Reducir la verbosidad de `AppServiceConsoleLogs`, empezando por Catalog, la palanca de costo más grande (H9). | Por decidir |
| 5 | SRE | Aplicar Terraform sin acotar para destruir el Diagnostic Setting huérfano de TicketProcessAsync, confirmar la entrega de los slots `stg2` y del stream de TicketProcess con tráfico real, y compartir los streams nuevos con el grupo de lectura (H13). | Pendiente |
| 6 | SRE | Sincronizar la copia del pipeline de Logstash del repositorio con la versión desplegada, sin las cadenas de conexión reales, antes de volver a desplegarla (H14). | Pendiente |
| 7 | SRE | Dejar configurados la zona horaria, el relé de correo y los archivos GeoIP en la VM, que figuran pendientes. | Pendiente |
| 8 | SRE | Calcular el desglose de costo de Log Analytics por app y decidir qué apps se dan de baja de Log Analytics (H1). | Por decidir |
| 9 | SRE | Confirmar o dejar documentado como no explicado el retraso inicial de Business (H8). | Por decidir |

## Hallazgos secundarios

| # | Hallazgo | Riesgo |
|---|---|---|
| S1 | El stack Docker de Graylog de SmartPedidos y SmartLoyalty tenía el índice `graylog_299` con fecha de inicio 1970-01-01, sin rotación desde cerca del 2026-01-31, con 1.090 millones de eventos y 382 GB en un único índice (lectura del 2026-06-25). No se registra si se corrigió ni se volvió a consultar. | Alto — Sin verificar |
| S2 | Seis de los ocho servicios de PRO corren .NET 7.0, ya sin soporte; no bloquea el logging y queda para planificar la actualización. | Medio |
