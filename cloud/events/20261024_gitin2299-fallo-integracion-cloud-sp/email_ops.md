**Asunto:** GITIN-2299 – Cola de SmartPedidos en Cloud con FranchiseId desactualizado: alta de POS bloqueada en la sucursal 5435

Hola equipo,

CaC reporta que tiene problemas al agregar un POS nuevo con la integración de SmartPedidos en la sucursal 5435. Les resumo lo encontrado en [GITIN-2299](https://smartit-ar.atlassian.net/browse/GITIN-2299).

**Qué pasó**
El alta falla con el mensaje "La cola ya se encuentra asignada a otra franquicia, no es posible asignar la misma ya que una cola no puede ser compartida". Se reportó el mismo error en la sucursal 3717.

**Qué encontré**
- Al guardar el POS, Cloud compara el `FranchiseId` guardado en el registro de la cola (contenedor `Queues` de Cosmos) con el de la franquicia que se está editando. Si difieren y la cola está activa, bloquea el alta.
- En 5435 el `FranchiseId` guardado en la cola no existe en las bases de negocio de GRIDO ni de WEISS, y la franquicia actual tiene otro id. El registro de 3717 muestra el mismo patrón. Para validar la hipótesis también se revisó el registro de 3293, que lo presenta igual; esa sucursal no está en el alcance del ticket y no se modificó.
- Revisé los 216 registros del contenedor: 38 colas activas tienen un `FranchiseId` inexistente (entre ellas las anteriores) y 51 colas activas tienen el campo vacío. En esos 51 casos el bloqueo surge de leer el código; no lo probé.
- La causa de fondo no está confirmada. 33 de los 38 registros con id inexistente tienen fecha de revisión 2025-12-17, pero los demás tienen otras fechas, así que esa fecha no alcanza para explicarlo.

**Qué se hizo**
En 5435 se creó un registro nuevo con el `FranchiseId` actual de la franquicia y se eliminó el anterior (con respaldo del original). No se puede editar el campo en el mismo registro: por lo que se ve en el código, forma parte de la clave de partición del contenedor. El campo `Checked` del registro nuevo se actualizó, lo que sugiere que el proceso que lee las colas lo tomó. Se confirmó que el alta del POS en 5435 ya se guarda con la integración de SmartPedidos.

**Recomendación**
1. Confirmar con quien tenga el historial de las franquicias qué pasó con los ids, antes de corregir en lote.
2. Corregir las demás colas de a una, con respaldo previo y el mismo procedimiento (registro nuevo, luego baja del anterior), empezando por las que hoy bloquean un alta.
3. Para los 51 registros con `FranchiseId` vacío, probar el caso en una sucursal antes de incluirlos en el lote.

Adjunto el detalle de las 89 colas activas alcanzadas (id guardado, franquicia candidata por código de sucursal y estado). Las franquicias candidatas salen de cruzar el número de sucursal con el código de la franquicia y solo están verificadas para 5435, 3717 y 3293. La corrección se aplicó únicamente en 5435.

Saludos.
