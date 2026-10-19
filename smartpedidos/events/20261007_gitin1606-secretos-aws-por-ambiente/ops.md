# [SP] Ocultar el ID de las colas de SQS y credenciales de SmartPedidos (ticket padre)

**Tags:** `SmartPedidos`, `AWS`, `SEGURIDAD`, `SRE`

## Resumen

Los agentes POS reciben las URL de las colas de SQS, que incluyen el ID de la cuenta de AWS, y claves de AWS estáticas que son las mismas para todas las sucursales; además, las credenciales de los servicios están escritas en su configuración y se repiten entre ambientes. Este ticket padre agrupa el trabajo para ocultar ese ID y gestionar las credenciales de forma segura. La investigación (GITIN-1607), la infraestructura de prueba (GITIN-1701) y el nuevo análisis de costos (GITIN-1703) están finalizados; la bóveda de secretos de Platform está en curso (GITIN-1715), y la de Concentrador (GITIN-2198) y las credenciales por desarrollador (GITIN-2169) están pendientes. El avance del padre es del 50 %. Está relacionado con la historia [GITSFP-1664](https://smartit-ar.atlassian.net/browse/GITSFP-1664), del tablero de SmartPedidos (en estado Inicio), cuyo contenido no se verificó.

## Tabla resumen

| Campo | Valor |
|---|---|
| Ticket Jira | [GITIN-1606](https://smartit-ar.atlassian.net/browse/GITIN-1606) |
| ID alerta | N/A |
| Sistema | SmartPedidos (Platform, Concentrador, agente POS), AWS (API Gateway, SQS, Lambda, Secrets Manager, KMS, IAM) |
| Severidad | Por definir |
| Detectado | 2026-07-20 |
| Resuelto | Parcial: 3 de 6 subtareas finalizadas |
| Responsable | SRE — Operaciones |

## Causa raíz

NA

## Hallazgos

| # | Hallazgo | Riesgo |
|---|---|---|
| H1 | Las URL de las colas que reciben los agentes POS contienen el ID de la cuenta de AWS, y la respuesta de inicio de sesión entrega además claves de AWS estáticas iguales para todas las sucursales. | Alto |
| H2 | El diseño elegido es un punto de entrada propio (API Gateway con integración nativa a SQS, dominio dedicado, recurso `/{branchId}`) que valida el token de sucursal y exige que coincida con la sucursal del pedido. Se validó de punta a punta en una prueba de concepto en una región aislada. | Bajo |
| H3 | Ninguna variante de costo es más barata que usar SQS directamente (hoy unos US$73 por mes): API Gateway solo ronda US$517 por mes, API HTTP más una Lambda liviana unos US$180, con CloudFront unos US$665. Es una medida de seguridad, no un ahorro. | Medio |
| H4 | El token de sucursal vale hasta 2000 horas, no tiene revocación y se firma con una clave que es la misma en Platform y Concentrador; en staging y producción esa clave y otros secretos de Platform coinciden. | Alto |
| H5 | El validador de tokens necesita leer la clave de firma desde un almacén de secretos, por lo que depende de las bóvedas de Platform y Concentrador y de rotar la clave de forma coordinada. | Medio |
| H6 | Ninguna subtarea cubre hoy la construcción del punto de entrada real; las decisiones y tareas de diseño pendientes (documentar el diseño, elegir entre API REST y API HTTP con Lambda, estrategia de DNS, dominio propio y el cambio en el agente POS) figuran solo en las notas de la investigación. | Medio |

## Recursos afectados

| Recurso | Detalle |
|---|---|
| Concentrador | Respuesta de `POST /branches/login` (región, claves y cola entregadas al agente) |
| Agente POS | Cambiaría su destino de SQS directo al nuevo dominio; su repositorio no forma parte del repositorio de notas. Posible relación con GITSFP-1664 (sin confirmar) |
| Platform y Concentrador | Credenciales en archivos de configuración por ambiente |
| AWS, cuenta única | API Gateway, SQS, Lambda, Secrets Manager, KMS, IAM, Route 53 |
| Recursos de la prueba de concepto | Región `us-west-2`; pendiente su eliminación |

## Comandos ejecutados

El detalle está en los tickets de cada subtarea.

| # | Comando / Script | Propósito |
|---|---|---|
| C1 | Prueba de concepto con API Gateway, SQS y Lambda | Validar el diseño de punta a punta (GITIN-1607, GITIN-1701) |
| C2 | Estimación de costos con Cost Explorer y Pricing API | Comparar variantes (GITIN-1703) |

## Acciones propuestas

Subtareas y qué cubre cada una:

1. (SRE) [GITIN-1607](https://smartit-ar.atlassian.net/browse/GITIN-1607) — Investigar cómo ocultar el ID de las colas: finalizada. Resultado: el diseño con API Gateway descrito arriba.
2. (SRE) [GITIN-1701](https://smartit-ar.atlassian.net/browse/GITIN-1701) — Infraestructura de prueba: finalizada.
3. (SRE) [GITIN-1703](https://smartit-ar.atlassian.net/browse/GITIN-1703) — Nuevo análisis de costos: finalizado.
4. (SRE) [GITIN-1715](https://smartit-ar.atlassian.net/browse/GITIN-1715) — Bóveda de secretos de Platform en staging (Ohio): en curso. Cubre la clave KMS, los secretos con credenciales propias de staging y el acceso por rol.
5. (SRE) [GITIN-2198](https://smartit-ar.atlassian.net/browse/GITIN-2198) — Bóveda de secretos de Concentrador: pendiente, con el mismo esquema que Platform.
6. (SRE) [GITIN-2169](https://smartit-ar.atlassian.net/browse/GITIN-2169) — Credenciales por desarrollador: los desarrolladores no deben tener acceso a producción; incluye reemplazar el perfil de AWS genérico por roles por ambiente.

A definir:

7. (SRE) Confirmar si GITSFP-1664 es el trabajo del lado del agente POS y, en ese caso, coordinarlo con el cambio de destino de las colas. Decidir además si se crea una subtarea para construir el punto de entrada real (documentar el diseño, elegir entre API REST y API HTTP con Lambda, estrategia de DNS, dominio propio, cambio del agente POS y retiro de las claves de la respuesta de inicio de sesión) y para rotar la clave de firma de forma coordinada entre Platform y Concentrador.
8. (SRE) Eliminar los recursos de la prueba de concepto, incluido un secreto de prueba que conserva el valor real de la clave de firma.

## Hallazgos secundarios

- Varios documentos internos del repositorio de notas contienen en texto plano el valor de la clave de firma de tokens; rotarla es la corrección de fondo, ya que editar los documentos no limpia el historial.
