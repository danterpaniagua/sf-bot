# GITIN-2299 — [CLOUD] Fallo integración CLOUD - SP

**Tags:** `SmartCloud`, `Azure`, `SRE`, `PROD`

## Qué pasó

- Al agregar un POS nuevo con la integración de SmartPedidos en la sucursal 5435, el alta falla con el mensaje: "La cola ya se encuentra asignada a otra franquicia, no es posible asignar la misma ya que una cola no puede ser compartida."
- Se reportó el mismo error en la sucursal 3717.

## Resumen

Cloud no deja guardar un POS con la integración de SmartPedidos si la cola de la sucursal figura asignada a otra franquicia. CaC no podía agregar un POS nuevo en la sucursal 5435 (2026-10-24). La cola de esa sucursal tenía guardado, en el contenedor `Queues` de Cosmos, un `FranchiseId` que no existe en las bases de negocio de GRIDO ni de WEISS, y la franquicia actual tiene otro id, por eso la validación bloqueaba el alta. Se creó un registro nuevo con el `FranchiseId` actual y se eliminó el anterior; según lo reportado, el alta del POS ya se guarda. El relevamiento de los 216 registros del contenedor muestra el mismo patrón en otras colas activas (38 con un `FranchiseId` inexistente, 51 con el campo vacío); no se modificó ninguna de ellas. La causa de fondo no está confirmada.

## Tabla resumen

| Campo | Valor |
|---|---|
| Ticket Jira | [GITIN-2299](https://smartit-ar.atlassian.net/browse/GITIN-2299) |
| ID alerta | NA |
| Sistema | SmartCloud (servicio Orders) y SmartPedidos |
| Severidad | NA |
| Detectado | 2026-10-24 |
| Resuelto | 2026-10-24 para la sucursal 5435 (alta del POS reportada como exitosa); el resto de las colas alcanzadas sigue sin corregir |
| Responsable | SRE |

## Causa raíz

NA

## Hallazgos

| # | Hallazgo | Riesgo |
|---|---|---|
| H1 | La cola de la sucursal 5435 tenía guardado el `FranchiseId` `914ef6053ea441b38ce756d7de7d17ff`, que no existe en las bases de negocio de GRIDO ni de WEISS. La franquicia 5435 tiene hoy el id `040fdf5d61c646cb9b39465291971e5d`. Con la cola activa y los ids distintos, la validación al guardar el POS bloquea el alta. | Alto |
| H2 | De los 216 registros del contenedor `Queues`, 38 colas activas tienen un `FranchiseId` que no está en ninguna de las dos bases (incluida la de 5435); 33 de esos 38 tienen fecha de revisión 2025-12-17 y los 5 restantes otras fechas. El registro de 3717 presenta el mismo patrón; el de 3293 se revisó solo para validar la hipótesis y lo presenta igual. No se identificó qué ocurrió el 2025-12-17. | Medio |
| H3 | 51 colas activas tienen el `FranchiseId` vacío. Por lo que se lee en el código, la validación las trataría como pertenecientes a otra franquicia y bloquearía el alta de un POS; no se probó en ninguna. | Medio |
| H4 | El campo `FranchiseId` no se puede editar en el mismo registro: el intento de modificarlo desde Data Explorer devolvió "Entity with the specified id does not exist" (404, operación Replace). Por lo que se ve en el código, `FranchiseId` y `BranchId` forman la clave de partición del contenedor; no se verificó en la configuración del contenedor. Para corregir una cola hay que crear un registro nuevo y dar de baja el anterior. | Bajo |
| H5 | Al actualizar una cola existente, `AddUpdateQueue` conserva el `FranchiseId` guardado, de modo que reintentar el alta no corrige un id desactualizado. | Medio |

**Código de H3 y H5** (`Source/Services/Orders/SmartFran.Cloud.Orders.Application/Services/QueueServices.cs`, rama `main`):

- Línea 185, método `CheckStatusQueue`: un valor guardado vacío difiere de cualquier `FranchiseId` enviado, y con la cola activa devuelve el error.

```csharp
if (queue?.FranchiseId?.ToLower() != queueMap.FranchiseId?.ToLower() && queue?.Active == true)
```

- Línea 151, método `AddUpdateQueue`: al actualizar, el `FranchiseId` del registro existente reemplaza al recibido.

```csharp
queueMap.FranchiseId = queue!.FranchiseId;
```

- Corrección sugerida, a evaluar con Dev: definir cómo debe tratar la validación una cola con `FranchiseId` vacío o que apunta a una franquicia que ya no existe, y si la actualización debe poder corregir ese campo. El control de que una cola no se comparta entre franquicias debe mantenerse.

## Acciones Tomadas

| # | Hora (UTC) | Acción |
|---|---|---|
| 1 | 19:10 – 19:50 (aprox.) | Lectura de los 216 registros del contenedor `Queues` y cruce con las franquicias de las bases de negocio de GRIDO y WEISS. Solo lectura. |
| 2 | 20:06 (aprox.) | Un intento de modificar `FranchiseId` en el registro de la cola de la sucursal 5435 falló con el error 404 descrito en H4; no cambió nada. |
| 3 | 20:06 – 20:14 (aprox.) | En la sucursal 5435 se creó un registro nuevo con el `FranchiseId` actual de la franquicia y un `id` nuevo, y se eliminó el registro anterior. El original quedó respaldado. |
| 4 | 20:14 | El campo `Checked` del registro nuevo pasó de 2025-12-17 a 2026-10-24T20:14:40Z, lo que sugiere que el proceso que lee las colas lo tomó. No se confirmó con logs. |
| 5 | Sin hora registrada | Según lo reportado, el alta del POS en 5435 ya se guarda con la integración de SmartPedidos. |

## Recursos afectados

| Recurso | Detalle |
|---|---|
| Cosmos DB `smartfran-cloud-cosmos-platform-pro`, contenedor `Queues` | Registro de la cola de la sucursal 5435 (reemplazado). 88 colas activas más con el mismo patrón o con `FranchiseId` vacío, sin modificar. |
| Cola SQS `5435PRD_PlatformMessages.fifo` | Sin cambios; es la cola asociada al registro. |
| Servicio Orders de SmartCloud | Valida la cola al guardar un POS con la integración de SmartPedidos. |

## Acciones propuestas

| # | Responsable | Acción | Estado |
|---|---|---|---|
| 1 | SRE | Confirmar con quien tenga el historial de las franquicias qué ocurrió con sus ids (y qué pasó el 2025-12-17) antes de corregir en lote. | Pendiente |
| 2 | SRE | Corregir de a una, con respaldo previo, las demás colas activas con `FranchiseId` inexistente, usando el mismo procedimiento (registro nuevo y baja del anterior), empezando por las que bloqueen un alta. El alcance está por definir; el detalle de las 89 colas alcanzadas está en el CSV adjunto al ticket. | Por decidir |
| 3 | SRE | Probar en una sucursal con `FranchiseId` vacío si el alta del POS queda bloqueada, antes de incluir esas 51 colas en una corrección. | Pendiente |
| 4 | SRE | Verificar en la configuración del contenedor `Queues` la clave de partición (H4). | Pendiente |
| 5 | Dev | Evaluar cómo debe tratar la validación y la actualización de colas un `FranchiseId` vacío o desactualizado (H3 y H5). | Por decidir |
