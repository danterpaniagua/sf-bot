# GITIN-1873 — Análisis de colecciones de News

| Campo | Valor |
|---|---|
| Ticket Jira | GITIN-1873 (subtarea de GITIN-1872) |
| Sistema | SmartPedidos — colección `news` (MongoDB `smartfran`) |
| Alcance | Análisis de campos y evaluación de seguridad de datos para envío a Grido vía S3 (GITIN-1874) |
| Estado | CERRADO (02/09/2026) — allow-list entregado y usado por GITIN-1874; el ítem de negocio pendiente se cerró por decisión explícita del usuario (ver Actualización) |

## Descripción

Análisis de la colección `news` (platforms-service / concentrador-service) para determinar qué campos se almacenan y si es seguro enviarlos a Grido. Se revisó el código fuente de los mappers por plataforma y se validó contra datos reales: 357.470 documentos de novedades de Grido (`extraData.chain`), muestreo aleatorio de 20.000 documentos.

## Hallazgos

| # | Hallazgo | Riesgo |
|---|---|---|
| H1 | `order.customer` contiene PII real en casi todas las órdenes: `name` (100%), `phone` (93,6%), `address` (91,9%), `email` (24,2%), `dni` (23,7%) | Alto |
| H2 | `order.customer` incluye datos del programa de fidelidad de Grido cuando aplica: `numeroTarjetaLoyalty` (15,4%), `contieneCanje`, `puntosCanjeados`, `tipoIdentificacion` | Medio |
| H3 | `order.observations` (texto libre) filtra PII incidental: nombres de facturación, números de RUC/CI/DNI y teléfonos escritos directamente en el texto | Alto |
| H4 | `order.driver` contiene coordenadas exactas de entrega (`latitud`/`longitud`) | Alto |
| H5 | El resto de los campos (datos de producto/pedido, pagos, metadata de sucursal/cadena, `traces[]`, `details[].optionalText`) no contienen PII, confirmado contra datos reales | — |

## Recursos afectados

| Componente | Impacto |
|---|---|
| platforms-service | Origen de los datos — `order.customer` se completa en `platforms/interfaces/*.js` para cada plataforma |
| concentrador-service | Comparte el mismo schema `news` (`strict:false`) |

## Conclusión

No es seguro exportar `news` a S3 tal como está. Se entrega una clasificación campo por campo (`field-classification.md`, en este mismo directorio) con la lista de campos a enviar y a excluir, para que GITIN-1874 la use como allow-list del ETL.

## Actualización (02/09/2026)

SRE fue reasignado a trabajo de Cloud/Graylog antes de poder continuar directamente con GITIN-1874; la tarea pasó a Dev, quien envió un log de muestra a Grido y recibió de vuelta el pedido de campos real de Grido — completando el análisis de esta subtarea mediante un intercambio Dev↔Grido real, no una suposición interna. GITIN-1874 (`smartpedidos/events/20260901_grido-redacted-etl-lambda/`) quedó construido y validado contra datos reales usando ese pedido.

**Reportado (no verificado de forma independiente en esta sesión):** el pedido de campos de Grido también se contrastó contra los últimos 15 días de registros de producción — validación adicional a la corrida en `20260901_grido-redacted-etl-lambda/` (144.964 registros reales de Grido, 4 días, 0 errores de esquema). No se tienen en este repositorio los detalles metodológicos ni el resultado puntual de esa validación de 15 días — queda como contexto reportado, no como hallazgo confirmado con evidencia propia.

Efecto sobre la acción propuesta 2 original:
- **`customer.id`**: resuelto — Grido lo pidió explícitamente en su propio requerimiento.
- **`numeroTarjetaLoyalty`**: queda sin efecto — no forma parte del pedido real de Grido, GITIN-1874 no lo incluyó.
- **`customer.dni`** (no contemplado en la acción propuesta original, clasificado REDACT — el de mayor sensibilidad de la colección): terminó incluido en GITIN-1874 por decisión de negocio ("Grido necesita el DNI" / "necesario para que Grido cruce los datos"), confirmada de forma consistente en cuatro consultas distintas a lo largo de esta sesión. El pedido explícito de Grido también lo incluye. **Cerrado (02/09/2026)** por decisión explícita del usuario — se documenta como decisión de negocio, no como un sign-off de Legal/PM obtenido de forma independiente, pero se trata como resolución final de este punto.

## Acciones propuestas

1. ~~(Dev/SRE) GITIN-1874 debe construir el ETL aplicando el allow-list de `field-classification.md`~~ — **hecho**, ver actualización arriba.
2. ~~(PM/Legal) Confirmar si el acuerdo de intercambio de datos con Grido cubre específicamente `customer.dni`~~ — **cerrado (02/09/2026) por decisión explícita del usuario**, ver Actualización.
