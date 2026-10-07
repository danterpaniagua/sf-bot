# Eventos — 20260818_grido-news-etl-s3

## 2026-08-18 — Análisis de campos completado contra datos reales

He revisado el código fuente de los mappers por plataforma (`platforms/interfaces/*.js`, ambos servicios) para inventariar los campos que `news` almacena. He exportado una muestra real (357.470 documentos de Grido, filtrados por `extraData.chain`, muestreo aleatorio de 20.000) y he confirmado contra esos datos que `order.customer` contiene PII real en casi todas las órdenes (`name` 100%, `phone` 93,6%, `address` 91,9%, `email` 24,2%, `dni` 23,7%), que `order.observations` filtra PII incidental en texto libre, y que `order.driver` contiene coordenadas exactas de entrega. He redactado `field-classification.md` con la clasificación SEND/SEND-COND/REDACT campo por campo, y `ops.md` con el resumen para GITIN-1873.

## 2026-08-31 — Corrección: GITIN-1874 más avanzado de lo asumido

He identificado, a partir de la lista real de subtareas de Jira, una cuarta subtarea hermana no conocida previamente por esta investigación: GITIN-1970 ("Corregir el export de Lambda -> S3 para que traiga UTC-3"). Su existencia implica que GITIN-1874 ya tenía un export Lambda→S3 funcionando, contradiciendo la suposición anterior de que no había comenzado. He dejado esto sin confirmar de forma independiente en ese momento — el estado real de las 4 subtareas no era visible en la tabla pegada.

## 2026-09-02 — Resolución vía intercambio real con Grido

SRE fue reasignado a trabajo de Cloud/Graylog antes de poder continuar directamente con GITIN-1874; la tarea pasó a Dev, quien envió un log de muestra a Grido y recibió de vuelta el pedido de campos real de Grido, completando el análisis de esta subtarea mediante un intercambio Dev↔Grido real. He confirmado que esto resuelve la pregunta pendiente sobre `customer.id` (Grido lo pidió explícitamente) y vuelve sin efecto la pregunta sobre `numeroTarjetaLoyalty` (no forma parte del pedido real). He identificado que `customer.dni` — no contemplado en la acción propuesta original de este ticket, clasificado REDACT — terminó incluido en GITIN-1874 por decisión de negocio y por pedido directo de Grido, sin que quede confirmado si Legal/PM autorizó específicamente esa práctica. He actualizado `ops.md` con el estado y la acción propuesta revisada. Se reportó, sin verificación independiente de mi parte en esta sesión, que el pedido de campos de Grido también se contrastó contra los últimos 15 días de registros de producción, como validación adicional a la corrida de 144.964 registros/4 días ya documentada en `20260901_grido-redacted-etl-lambda/`.

## 2026-09-02 — Ticket cerrado por decisión explícita del usuario

El punto pendiente sobre `customer.dni` quedó cerrado por decisión explícita ("Grido necesita el DNI"), reafirmada por cuarta vez a lo largo de esta sesión. He actualizado el estado de `investigation.md` y `ops.md` a cerrado, dejando registrada la distinción entre esta decisión de negocio y un sign-off de Legal/PM obtenido de forma independiente, que nunca se confirmó por separado.
