# Zabbix: trigger "Running Task menor que Desired Task" (GITIN-2222)

Pasos manuales en el frontend (Zabbix 6.0.32). Nada de esto se aplicó todavía; se arma a partir de la lectura C9 (`data/c9-run-log-20261015T013249Z.txt`).

## Dónde va

- Los items `Running Task` / `Desired Task` los crea la regla de descubrimiento **Cluster Services discovery** (`aws.ecs.services.discovery`, macro LLD `{#AWS.ECS.SERVICE.NAME}`) de la plantilla **AWS ECS Serverless Cluster by HTTP** (id 10576). El host `smartfran-pedidos-production` es un host descubierto, por lo que el trigger se crea como **prototipo de trigger** en esa regla.
- Esa plantilla está vinculada a tres hosts: `Zabbix server`, `smartfran-pedidos-production` y `smartfran-pedidos-dev`. El prototipo se aplicará a los servicios descubiertos de los tres (en dev y en `Zabbix server` solo si descubren servicios). Sin tags de enrutamiento no notifica a nadie, pero sí aparece en Problemas.
- Es una modificación a una plantilla estándar: una reimportación de la plantilla puede pisarla. Alternativa: clonar la plantilla y revincular los hosts (más trabajo).

## Paso 1 - macro (primero, antes del trigger)

`Data collection → Templates → AWS ECS Serverless Cluster by HTTP → Macros`

| Macro | Valor | Descripción |
|---|---|---|
| `{$AWS.ECS.CLUSTER.SERVICE.RUNNING.DIP}` | `0.05` | Margen, en tareas, por debajo de Desired antes de considerarlo una caída. Running llega como promedio de 10 minutos: una tarea caída un minuto de cinco da 4.9. |

## Paso 2 - prototipo de trigger

`Data collection → Templates → AWS ECS Serverless Cluster by HTTP → Discovery → Cluster Services discovery → Trigger prototypes → Create`

```
Name: AWS ECS Cluster Service: [{#AWS.ECS.SERVICE.NAME}]: Running tasks below desired
Severity: Warning
Expression: last(/AWS ECS Serverless Cluster by HTTP/aws.ecs.services.running.task["{#AWS.ECS.SERVICE.NAME}"])<last(/AWS ECS Serverless Cluster by HTTP/aws.ecs.services.desired.task["{#AWS.ECS.SERVICE.NAME}"])-{$AWS.ECS.CLUSTER.SERVICE.RUNNING.DIP}
OK event generation: Recovery expression
Recovery expression: last(/AWS ECS Serverless Cluster by HTTP/aws.ecs.services.running.task["{#AWS.ECS.SERVICE.NAME}"])>=last(/AWS ECS Serverless Cluster by HTTP/aws.ecs.services.desired.task["{#AWS.ECS.SERVICE.NAME}"])
Operational data: Running: {ITEM.LASTVALUE1} | Desired: {ITEM.LASTVALUE2}
```

Tags (misma forma que los prototipos existentes):

| Tag | Valor |
|---|---|
| `scope` | `availability` |
| `service` | `{#AWS.ECS.SERVICE.NAME}` |

Tags de enrutamiento (solo si se quiere que notifique): hay que elegirlos contra las acciones vivas (`docs/zabbix_observability.md` → Alert routing); ninguna acción documentada usa un `service_group` de SmartPedidos. Pendiente de decisión.

## Límites conocidos

- `Running Task` es el promedio de 10 minutos de `RunningTaskCount` (`Period` 600, `Stat` Average) consultado cada 5 minutos: un solo evento puede dejar el problema abierto de 5 a 10 minutos.
- La Lambda de la cola (`IntegrationLambdaEcsTaskProd`) sube Desired a 15 y las tareas nuevas tardan cerca de un minuto en correr; ese tramo también dispara el trigger (1 a 4 veces por día según los episodios documentados). El déficit de una subida es mayor que el de una caída puntual; si hace falta, se ajusta el margen o se agrega una cota superior después de ver datos reales.
- El trigger dice que se perdieron tareas, no por qué. La causa está en Graylog (`[INFRA/FATAL] unhandled_rejection`).
