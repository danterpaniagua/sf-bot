# [SP] Agregar Lambda a esquema de monitoreo

**Tags:** `SmartPedidos`, `Graylog`, `Obserbavilidad`, `SRE`

## Resumen

La Lambda `IntegrationLambdaEcsTaskProd` (producción, región us-east-1), que ajusta la cantidad de tareas del servicio de Platform cuando se dispara la alarma de edad de la cola de mensajes de sucursales, no formaba parte del esquema de monitoreo en Graylog: sus logs existían únicamente en CloudWatch Logs, sin ningún mecanismo que los reenviara, y no había mensajes suyos en Graylog. Se incorporaron esos logs al Graylog de SmartPedidos reutilizando el patrón que ya usan los servicios de producción (filtro de suscripción de CloudWatch Logs, Kinesis y entrada de tipo AWS en Graylog), **sin modificar la función**. Una línea de prueba escrita en su grupo de logs llegó a Graylog y quedó ruteada al stream propio. Queda pendiente confirmar con la próxima ejecución real de la función (próximo ciclo de la alarma) que sus propias líneas llegan.

## Tabla resumen

| Campo | Valor |
|---|---|
| Ticket Jira | [GITIN-2171](https://smartit-ar.atlassian.net/browse/GITIN-2171) (padre: [GITIN-2170](https://smartit-ar.atlassian.net/browse/GITIN-2170)) |
| ID alerta | N/A (mejora de observabilidad) |
| Sistema | Lambda `IntegrationLambdaEcsTaskProd` (us-east-1) / Graylog de SmartPedidos |
| Severidad | N/A |
| Detectado | 2026-10-05 |
| Resuelto | Parcial: implementado y verificado con una línea de prueba el 2026-10-05; pendiente la verificación con una ejecución real |
| Responsable | SRE |

## Alcance

**Incluye:**
- Enviar al Graylog de SmartPedidos los logs que la Lambda ya escribe en su grupo de logs de CloudWatch (líneas `START`, `END` y `REPORT` de la plataforma Lambda, incluido el estado de timeout, y los mensajes que imprime la propia función).
- Ruteo de esos mensajes al stream `SP_Lambdas` y al índice `SP_Lambda`, sin que ingresen al stream por defecto.
- Hacerlo **sin modificar la Lambda** (código, configuración, timeout, memoria ni rol).
- Dejar el camino reutilizable: un único stream de Kinesis, un único rol y una única entrada de Graylog, de modo que otras Lambdas se sumen agregando solo un filtro de suscripción en su grupo de logs.

**No incluye:**
- Cambios en la lógica, el timeout, la memoria o el rol de la función; corresponden al ticket padre GITIN-2170.
- Alertas (Zabbix, alarmas de CloudWatch o alertas de Graylog).
- Parseo de los mensajes (duración, estado de timeout) en campos de Graylog; los mensajes llegan como texto crudo.
- Reemplazo de la credencial de las entradas AWS existentes (ver H7).

**Limitación:** al no modificar la función, solo puede enviarse lo que ya escribe. La función no registra nada posterior a la llamada que modifica el servicio ni el estado de la alarma que la dispara; en Graylog se verán los timeouts y las cantidades de tareas leídas al inicio de cada ejecución, pero no si el aumento de tareas se ejecutó.

## Causa raíz

No aplica: no se trata de un incidente. La función nunca había sido incorporada al esquema de monitoreo.

## Hallazgos

| # | Hallazgo | Riesgo |
|---|---|---|
| H1 | Antes del cambio, los logs de la función existían solo en su grupo de logs de CloudWatch: sin filtros de suscripción y sin resultados en una búsqueda en Graylog por el texto de sus mensajes (7 días, campo `message`, streams visibles para el token usado). | Medio |
| H2 | La función escribe texto plano sin estructura (líneas de plataforma y conteos de tareas); no registra el resultado de la actualización ni el estado de la alarma. | Bajo |
| H3 | Entre el 2026-10-02 y el 2026-10-05, 7 de 23 ejecuciones terminaron en timeout (límite de 3 s); no existe alarma sobre errores de esta función. Su atención corresponde a GITIN-2170; aquí es contexto: con los logs en Graylog serán visibles. | Medio |
| H4 | Los logs de los servicios de producción (Platform, Concentrador, WAF) llegan a Graylog mediante filtros de suscripción de CloudWatch Logs hacia streams de Kinesis (aprovisionados, 1 shard, 24 h de retención) y entradas de tipo AWS en Graylog; ese es el patrón que se replicó. | Informativo |
| H5 | El stream y el índice por defecto de Graylog estaban en el límite de 1000 campos de mapeo (estado al 2026-08-12, no revalidado), por lo que los logs nuevos requieren stream e índice propios. | Medio |
| H6 | La entrada de Graylog para este stream entrega el texto de cada línea e incorpora el grupo de logs de origen, el stream de Kinesis y el stream de logs como campos, lo que permite distinguir varias Lambdas que compartan la entrada. | Informativo |
| H7 | Las tres entradas AWS existentes de Graylog usan la misma credencial estática (clave de acceso) con permisos de administración amplios. La nueva entrada reutiliza esa credencial por decisión del equipo, por lo que la exposición se extiende a una entrada más. No se evaluó cómo Graylog almacena el secreto. | Alto |
| H8 | El nuevo stream de Kinesis (1 shard aprovisionado) agrega un costo recurrente por hora-shard; el monto no se verificó contra la facturación. | Bajo |

## Recursos afectados

| Recurso | Impacto |
|---|---|
| Lambda `IntegrationLambdaEcsTaskProd` (us-east-1) | Sin cambios. Solo lectura (copia de respaldo de código y configuración tomada). |
| Grupo de logs de CloudWatch de la Lambda | Filtro de suscripción nuevo (`sp-lambda-logs`) hacia el stream de Kinesis. Se escribió además una línea de prueba en un stream de logs propio (`gitin2171-pipeline-test`). |
| Kinesis `sp-lambda-logs` (us-east-1) | Nuevo: aprovisionado, 1 shard, 24 h de retención. |
| Rol IAM `graylog-cloudwatch-role-sp-lambda-logs` | Nuevo: confianza con CloudWatch Logs; solo permite escribir registros en el stream nuevo. |
| Tabla DynamoDB `graylog-aws-plugin-sp-lambda-logs` | Creada automáticamente por la entrada de Graylog (estado del consumidor). |
| Graylog de SmartPedidos | Entrada AWS `sp-lambda-logs` (en ejecución), índice `SP_Lambda` (1 shard, rotación semanal, retención de 52 índices) y stream `SP_Lambdas` (reglas: coincide con la entrada nueva o con `ServiceType = Lambda`; quita las coincidencias del stream por defecto). |

## Comandos ejecutados

Detalle y salidas reales en `scripts.sh` y en `data/`. Los comandos que modifican estado se marcan con ⚠️.

| # | Comando / Script | Propósito |
|---|---|---|
| C1 | Reconocimiento de Graylog (entradas, streams, conjuntos de índices, DNS) y de la función existente de envío de logs de WAF | Identificar rutas y convenciones de ingesta existentes |
| C2 | Reconocimiento del lado AWS (Kinesis, Firehose, filtros de suscripción, grupos de seguridad del host de Graylog) | Confirmar el camino actual de logs |
| C3 | Respaldo de código y configuración de la Lambda (solo lectura) | Respaldo previo ante cualquier cambio futuro |
| C4 | Listado de títulos de streams e índices | Verificar que los objetos no existieran |
| C5 | Armado del cuerpo del índice a partir de la configuración de otro índice existente | Definir el índice nuevo |
| C6 ⚠️ | Creación del índice `SP_Lambda` | Prerrequisito de Graylog |
| C7 ⚠️ | Creación del stream `SP_Lambdas` | Prerrequisito de Graylog |
| C8 | Verificación del stream creado | Confirmar regla, índice y estado |
| C9 ⚠️ | Inicio del stream `SP_Lambdas` | Dejar el ruteo activo |
| C10 | Prueba local de un candidato de logging dentro de la función (descartado) | Validación de lógica, sin acceso a AWS |
| C11 | Lectura del patrón existente de Kinesis a Graylog (filtros, roles, resúmenes de streams, tablas DynamoDB, atributos de entradas AWS) | Replicar el patrón |
| C12 | Lectura de la identidad IAM que usan las entradas AWS existentes (identificadores enmascarados) | Definir credenciales de la entrada nueva |
| C13 ⚠️ | Creación y posterior eliminación de objetos con nombre específico de esta Lambda, reemplazados por nombres genéricos | Corrección de nombres antes de uso |
| C14 ⚠️ | Creación del stream de Kinesis y el rol genéricos, filtro de suscripción sobre el grupo de logs de la Lambda y verificación | Camino de logs hacia Kinesis |
| C15 ⚠️ | Creación de la entrada AWS `sp-lambda-logs` en Graylog | Consumir el stream de Kinesis |
| C16 ⚠️ | Regla de coincidencia por entrada en el stream `SP_Lambdas` y cambio a coincidencia de cualquier regla | Rutear los mensajes al stream propio |
| C17 ⚠️ | Línea de prueba en un stream de logs propio del grupo de logs de la Lambda (sin invocar la función) | Probar el camino completo |
| C18 | Búsqueda en Graylog por la entrada nueva | Confirmar llegada y ruteo |

## Acciones propuestas

1. (SRE) Crear el índice `SP_Lambda` y el stream `SP_Lambdas` en Graylog. **Completado** el 2026-10-05.
2. (SRE) Crear el stream de Kinesis `sp-lambda-logs`, su rol y el filtro de suscripción sobre el grupo de logs de la Lambda, sin modificar la función. **Completado** el 2026-10-05.
3. (SRE) Crear la entrada AWS `sp-lambda-logs` en Graylog y la regla que rutea sus mensajes a `SP_Lambdas`. **Completado** el 2026-10-05; la entrada está en ejecución.
4. (SRE) Validar el camino completo con una línea de prueba. **Completado**: la línea llegó a Graylog ruteada solo a `SP_Lambdas` (no al stream por defecto), con el grupo de logs de origen informado.
5. (SRE) Validar con la próxima ejecución real de la Lambda (próximo ciclo de la alarma) que sus líneas `START`, `END` y `REPORT` llegan a `SP_Lambdas`. **Pendiente.**
6. (SRE) Documentar la ruta de ingesta de Lambdas (stream de Kinesis, rol, entrada y stream de Graylog) en la documentación de Graylog de SmartPedidos. **Pendiente.**
7. (SRE) Evaluar reemplazar por una credencial de alcance mínimo la que usan las entradas AWS de Graylog (incluida la nueva) y rotarla. **Fuera de este ticket; pendiente definir si se abre uno aparte.**
8. (SRE) Para incorporar otras Lambdas: agregar un filtro de suscripción en su grupo de logs hacia el mismo stream de Kinesis; el stream `SP_Lambdas` ya rutea todo lo que entra por la entrada nueva. **Disponible**, sin trabajo previsto en este ticket.

## Hallazgos secundarios

- La línea de prueba permanece en Graylog (índice `SP_Lambda`) y en el stream de logs `gitin2171-pipeline-test` del grupo de logs de la Lambda.
- Los mensajes llegan como texto crudo; mostrar la duración o el estado de timeout como campos requeriría un extractor o pipeline en Graylog.
