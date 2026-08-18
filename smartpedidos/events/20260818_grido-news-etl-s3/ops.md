# GITIN-1873 — Análisis de colecciones de News

| Campo | Valor |
|---|---|
| Ticket Jira | GITIN-1873 (subtarea de GITIN-1872) |
| Sistema | SmartPedidos — colección `news` (MongoDB `smartfran`) |
| Alcance | Análisis de campos y evaluación de seguridad de datos para envío a Grido vía S3 (GITIN-1874) |

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

## Acciones propuestas

1. (Dev/SRE) GITIN-1874 debe construir el ETL aplicando el allow-list de `field-classification.md`, excluyendo los campos marcados REDACT.
2. (PM/Legal) Confirmar si el acuerdo de intercambio de datos con Grido cubre `customer.id` y `numeroTarjetaLoyalty` antes de incluirlos en el export — quedan marcados como pendientes de confirmación, no como aprobados.
