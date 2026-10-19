# Eventos — 20261009_gitin2209-graylog-poco-espacio-disco

## 2026-10-09 17:29 — Estado de disco, cluster e index sets de la VM de Graylog de SmartCloud

**Comando:** C1 — Estado de disco y OpenSearch (`scripts.sh`)
**Resultado:**
`/var/lib/opensearch`: 512 GB, 456 GB usados, 57 GB libres (89%). Cluster en amarillo con 9 índices que piden réplica (18 shards sin asignar). Cero índices con `read_only_allow_delete`; 80 con `index.blocks.write=true`. 25 index sets: 16 con rotación P30D/P40D y 9 `http_*` con P7D/P9D, todos con retención por borrado de 20 índices. Salidas en `data/df.txt`, `data/cluster-health.json`, `data/cat-allocation.txt`, `data/cat-indices.txt`, `data/index-blocks.json` y `data/index-sets.json`.

He confirmado que no hay bloqueo de escritura por falta de espacio y que el cluster amarillo se debe a réplicas pedidas en un nodo único, no al disco. Los index sets más grandes son Business (98 GB), Orders (90 GB) y Sales (56 GB). No he podido leer los umbrales de disco efectivos porque el filtro de la consulta devolvió un objeto vacío; he asumido los valores por defecto (85/90/95%) hasta leerlos.

## 2026-10-09 17:33 — Dry run de la ampliación de la partición

**Comando:** C2 — Ampliar partición y XFS (`scripts-grow.sh`, `DRYRUN=1`)
**Resultado:**
Primer intento: las guardas pasaron (disco 768 GB, partición 511 GB, XFS, una sola partición) y `growpart --dryrun` falló con `unknown option --dryrun`. Segundo intento con `growpart -N`: `CHANGE: partition=1 start=65536 old: size=1073676255 end=1073741790 new: size=1610547167 end=1610612702`, sin modificar nada. Salidas en `data/grow-dryrun.txt` y `data/grow-dryrun-2.txt`.

He corregido la opción del script (`-N`) y he confirmado en el segundo dry run que la partición crece sin cambiar el sector de inicio, el tipo ni el UUID.

## 2026-10-09 17:37 — Ampliación de la partición y del filesystem de /var/lib/opensearch

**Comando:** C2 — Ampliar partición y XFS (`scripts-grow.sh`, `DRYRUN=0`)
**Resultado:**
`growpart` aplicó el cambio (`CHANGED: partition=1 ... new: size=1610547167`) y `xfs_growfs` pasó de 134.209.531 a 201.318.395 bloques de datos, en línea y sin detener OpenSearch. Después: `/var/lib/opensearch` 768 GB, 460 GB usados, 309 GB libres (60%). Salida en `data/grow-apply.txt`; las capturas de `df` posteriores están en `data/df-user-paste-2.txt` y `data/df-user-paste-3.txt`.

He ampliado el espacio utilizable de 512 GB a 768 GB, el tamaño que ya tenía el disco de Azure. El uso pasó del 89% al 60%.

## 2026-10-09 17:41 — Volumen del stream de Business por día, nivel, logger y ruta

**Comando:** C3 — Volumen del stream de Business (`scripts-business.sh`)
**Resultado:**
Mensajes por día en `PROD-Business-AppServicePlan`: 112 mil a 334 mil hasta el 10-06; 474 mil el 10-07; 3.541.852 el 10-08; 4.342.494 el 10-09 hasta las 17:41. Error pasó de 350–760 por día a 380.725 (10-08) y 559.599 (10-09); Warning casi idéntico. Loggers nuevos desde el 10-07: `Microsoft.AspNetCore.Hosting.Diagnostics`, `VirtualWallet.MercadoPag...`, `MercadoPago.Clients...`, `VirtualWallet.Abstractio...` y los handlers de `IWalletOAuthClient`. Rutas nuevas: `/api/v1/WalletCredentials/<id>` con 5 ids. Salidas en `data/business/`.

He identificado que el crecimiento del índice de Business viene de un flujo nuevo de logs de billetera de MercadoPago, que pasó de unos 172 mil a unos 4,5 millones de mensajes por día.

## 2026-10-09 17:49 — Inicio, ritmo y texto de los errores de Business

**Comando:** C4 — Errores por hora y mensajes recientes (`scripts-business-detail.sh`)
**Resultado:**
Errores por hora: ~144 hasta las 21:59 del 10-07; 12.497 en la hora de las 22:00; ~26.000 por hora hasta la mañana del 10-08; ~78 por hora entre las 10:00 y las 14:59; vuelve en escalones (15:00, 16:00, 20:00, 21:00, 23:00) hasta ~31.700 por hora constantes. Los 30 mensajes de muestra son `MP API error: endpoint=/oauth/token statusCode=400 mainErrorCode=invalid_grant` del logger `MpOAuthClient`, con `Environment: Production`. Salidas en `data/business/detail-*` (excluidas del control de versiones).

He ubicado el inicio cerca de las 22:30 del 10-07 y he confirmado que los errores son rechazos `invalid_grant` de MercadoPago al refrescar tokens en producción.

## 2026-10-09 18:05 — Warnings de Business: qué credenciales fallan

**Comando:** C5 — Warnings recientes de Business (`scripts-business-warnings.sh`)
**Resultado:**
200 Warnings de una muestra de 44 segundos (5.301 en los 10 minutos previos): todos `WalletCredentials: refresh failed`, `applicationType=QR`, `mpStatusCode=400`, `mpErrorCode=invalid_grant`, para 2 `userId` de billetera (credenciales 31 y 66), con el request pidiendo `applications=Delivery,QR`. La propiedad `UserId` de las líneas es un sujeto de máquina a máquina de Auth0. Salidas en `data/business/detail-warn-*` (excluidas del control de versiones).

He acotado de 5 a 2 las cuentas que fallan y he verificado, comparando solo coincidencias, que ese cliente de Auth0 figura como literal en la configuración de producción del Concentrador y de Platform y que los dos `userId` aparecen en los errores de token del Concentrador (GITIN-2208).

## 2026-10-09 18:03 — Consultas de solo lectura preparadas para identificar a los titulares

He preparado la consulta SQL sobre las credenciales en ventana de renovación (`scripts-wallet-credentials.sql`) y dos consultas para nombrar las cuentas (`data/business/detail-wallet-accounts.sql` en la base de Business y `data/business/detail-branches-by-mp-user.js` en MongoDB de SmartPedidos). Todavía no las he ejecutado. Las dos últimas están excluidas del control de versiones porque contienen identificadores de cuenta.

## 2026-10-09 18:21 — Documentos del ticket y comunicaciones

He redactado `ops.md` (18:08, reescrito una vez con el resultado de C5), `reporte-devs.md` (18:06), `email_ops.md` (18:21) y `email_pm.md` (18:23). Tienen la misma versión de los hechos: 2 cuentas confirmadas de 5 que consultan el endpoint, llamador probable en SmartPedidos (el mismo cliente de Auth0 está configurado en Concentrador y Platform), y una estimación de llenado del disco entre el 15 y el 21 de octubre. El lunes 12 es feriado.
