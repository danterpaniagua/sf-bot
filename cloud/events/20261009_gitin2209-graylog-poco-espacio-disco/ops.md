# GITIN-2209 — [OPE] Graylog: poco espacio en disco

**Etiquetas:** `SmartCloud`, `Graylog`, `Obserbavilidad`, `PROD`

## Resumen

El disco de datos de la VM de Graylog de SmartCloud, donde OpenSearch guarda los índices, estaba al 89% de uso (456 GB de 512 GB, 57 GB libres) el 2026-10-09, con un ingreso de logs por encima del promedio en los últimos dos días (21 y 24 GB por día según los datos informados). Al ritmo de ese ingreso y con los umbrales por defecto de OpenSearch (no verificados en el cluster), el disco llegaría al umbral de bloqueo de escritura en alrededor de un día y medio. El aumento proviene del servicio Business de producción: desde alrededor de las 22:30 del 2026-10-07, el endpoint de credenciales de billetera reintenta sin pausa el refresco de tokens de MercadoPago que MercadoPago rechaza con `invalid_grant`, y escribe unos 4,5 millones de mensajes por día, contra unos 170 mil antes. El disco de Azure se había ampliado a 768 GB, pero la partición y el filesystem seguían en 512 GB; se extendieron el 2026-10-09 y quedaron 309 GB libres (60% de uso). El bucle sigue activo. Las horas son locales (UTC-3).

## Tabla resumen

| Campo | Valor |
|---|---|
| Ticket Jira | [GITIN-2209](https://smartit-ar.atlassian.net/browse/GITIN-2209) |
| ID alerta | NA |
| Sistema | Graylog de SmartCloud (OpenSearch), servicio Business (producción) |
| Severidad | Por definir con Operaciones |
| Detectado | 2026-10-09 (disco al 89%) |
| Resuelto | Parcial: espacio ampliado a 768 GB (60% de uso); la fuente del volumen, el bucle de reintentos del refresco de MercadoPago, sigue activa |
| Responsable | SRE (infraestructura de logs); Dev (Business, Concentrador y Platform) |

## Causa raíz

El volumen de logs lo genera un bucle de reintentos. `GET /api/v1/WalletCredentials/{userId}` (servicio Business) renueva una credencial cuando le quedan 7 días o menos de vigencia; si MercadoPago rechaza el refresco, el servicio registra un Warning, devuelve la credencial como no disponible y no cambia su estado, por lo que la credencial sigue activa y dentro de la ventana de renovación y cada llamada repite el mismo refresco con el mismo refresh token rechazado. Un llamador que consulta el endpoint de forma continua (unos 8,8 fallos por segundo) produce así unas seis líneas de log por intento. El motivo por el que MercadoPago rechaza esos tokens (`invalid_grant`) no está determinado.

## Hallazgos

| # | Hallazgo | Riesgo |
|---|---|---|
| H1 | `/var/lib/opensearch` estaba al 89% (512 GB, 456 GB usados). El disco de Azure ya medía 768 GB pero la partición y el filesystem XFS medían 512 GB. No hay bloqueos de solo lectura por falta de espacio (cero índices con `read_only_allow_delete`). | Alto |
| H2 | El índice de Business pasó de ~1,8 GB por día a ~17,5 GB por día (índice creado el 10-07) y a ~38 GB por día (índice creado el 10-09, con 13 horas de datos). En el stream `PROD-Business-AppServicePlan` los mensajes por día fueron 112 mil a 334 mil hasta el 10-06, 474 mil el 10-07, 3.541.852 el 10-08 y 4.342.494 el 10-09 hasta las 17:41. | Alto |
| H3 | El aumento corresponde a `MP API error: endpoint=/oauth/token statusCode=400 mainErrorCode=invalid_grant` (logger `MpOAuthClient`) y a `WalletCredentials: refresh failed` (Warning). Empezó cerca de las 22:30 del 10-07 (12.497 errores en la hora de las 22:00, 25.573 a las 23:00), se mantuvo en ~26.000 por hora, casi se detuvo entre las 10:00 y las 15:00 del 10-08 y volvió en escalones hasta ~31.700 por hora (8,8 por segundo, constante de día y de noche). Los mensajes de muestra traen `Environment: Production` y `Service: SmartFran.Cloud.Business.API`. | Alto |
| H4 | Cinco `userId` de billetera de MercadoPago consultan el endpoint (unos 528 mil, 331 mil, 150 mil, 60 mil y 21 mil requests por día). En una muestra de 44 segundos (200 Warnings de las 5.301 de los 10 minutos previos) fallaron 2 de ellos, con las credenciales 31 y 66, ambas de la aplicación QR (`applicationType=QR`, `mpStatusCode=400`, `mpErrorCode=invalid_grant`), con el request pidiendo `applications=Delivery,QR`. Son los dos con más requests (~860 mil por día contra ~760 mil errores por día); no se verificó en una ventana más larga que los otros tres no fallen. | Alto |
| H5 | En el código (rama `main`, `WalletCredentialsService.ProcessCredentialAsync`), ante una `MpApiException` el servicio registra el Warning y devuelve `null` sin transicionar el estado de la credencial (el comentario del código lo indica), y `RequiresRenewal()` es `ExpiresAt <= ahora + 7 días`. El inicio escalonado (22:30 del 10-07 y escalones hasta las 23:00 del 10-08) coincidiría con el momento en que cada credencial entró en esa ventana; es una hipótesis que se puede verificar con una consulta de solo lectura a la tabla de credenciales. | Medio |
| H6 | El llamador es un cliente máquina a máquina de Auth0 (sujeto `<client_id>@clients`). Ese `client_id` figura como literal en la configuración de producción tanto del Concentrador como de Platform (SmartPedidos), por lo que cualquiera de los dos puede ser el llamador; el token no los distingue. Los dos `userId` que fallan también aparecen en los errores `mercadopago_token_fetch failed` y `mercadopago_token_invalid_response` del Concentrador (GITIN-2208). El Concentrador registra muchas menos líneas que las ~8,8 por segundo que ve Cloud. | Medio |
| H7 | Cada llamada fallida genera unas seis líneas: logs de request de ASP.NET (~1,3 M por día), servicio de billetera (~1,08 M), cliente de MercadoPago (~1,08 M), abstracción de billetera (~541 mil) y handlers HTTP de `IWalletOAuthClient` (~221 mil cada uno), más un Warning y un Error por el mismo fallo (380 mil y 560 mil por día, casi idénticos). | Medio |
| H8 | Business conserva 30 a 40 días (P30D/P40D) y su volumen actual por sí solo supera lo que cabe en el disco. Con 309 GB libres y 21 a 25 GB por día, el 95% de 768 GB (730 GB) quedaría a unos 11 días y el 100% a unos 13 días (alrededor del 2026-10-20 al 22), si no cambia nada. Es una estimación. | Medio |
| H9 | El índice de Orders también crece (2,1 GB por día, luego 3,1 y 5,6 GB por día en sus últimos tres índices) y no se examinó la causa. | Bajo |

## Recursos afectados

| Componente | Estado observado |
|---|---|
| Graylog de SmartCloud (VM `sfcloud-monitoreo`, disco de OpenSearch) | Espacio pasó del 89% al 60% de uso tras la ampliación; el volumen de Business lo vuelve a consumir. |
| SmartFran.Cloud.Business.API (producción) | Fuente de ~4,5 millones de mensajes por día por reintentos del refresco de tokens de MercadoPago. |
| Concentrador y Platform (SmartPedidos) | Comparten el cliente de Auth0 que consulta el endpoint `WalletCredentials`; el Concentrador registra errores de token con los mismos `userId`. |
| Cuentas de billetera de MercadoPago | 2 credenciales (31 y 66, aplicación QR) con refresh token rechazado por MercadoPago con `invalid_grant`; 3 `userId` más consultan el endpoint sin fallos observados. No se conoce el motivo del rechazo (cuenta desvinculada, autorización revocada o token ya usado). |

## Comandos ejecutados

| # | Comando / Script | Propósito |
|---|---|---|
| C1 | `scripts.sh` | Estado de disco, salud del cluster, asignación, índices e index sets de la VM de Graylog de SmartCloud (solo lectura). Salidas en `data/` |
| C2 | `scripts-grow.sh` ⚠️ | Extender la partición y el filesystem XFS de `/var/lib/opensearch` de 512 a 768 GB (dry run y aplicación; sin detener OpenSearch). Salidas en `data/grow-dryrun.txt`, `data/grow-dryrun-2.txt` y `data/grow-apply.txt` |
| C3 | `scripts-business.sh` | Mensajes por día, nivel, logger, categoría y ruta del stream de Business, antes y después del 2026-10-07 (solo lectura). Salidas en `data/business/` |
| C4 | `scripts-business-detail.sh` | Errores por hora desde el 2026-10-07 y texto de los errores recientes (solo lectura). Salidas en `data/business/detail-*` (excluidas del control de versiones por contener mensajes crudos) |
| C5 | `scripts-business-warnings.sh` | 200 Warnings recientes para identificar qué credenciales y `userId` fallan (solo lectura). Salidas en `data/business/detail-warn-*` (excluidas del control de versiones) |
| C6 | `scripts-wallet-credentials.sql` | Consulta de solo lectura a la base de Business para ver `ExpiresAt`, `LinkedAt` y estado de las credenciales en ventana de renovación y cuántas se acercan a ella. Pendiente de ejecución |

## Acciones propuestas

1. (SRE) Extender la partición y el filesystem de `/var/lib/opensearch` a 768 GB. Hecho el 2026-10-09: `df` pasó de 512 GB con 89% de uso a 768 GB con 460 GB usados, 309 GB libres y 60% de uso.
2. (Dev, Business) Cambiar el endpoint `WalletCredentials` para que, tras un `invalid_grant`, no repita el refresco en cada llamada: responder rápido con un error claro, recordar el resultado negativo por un tiempo y marcar la credencial como que requiere volver a vincularse.
3. (Dev, Business) Registrar un solo mensaje por fallo (hoy un Warning y un Error por el mismo hecho) y limitar la frecuencia del log por credencial.
4. (Dev, Concentrador y Platform) Confirmar cuál de los dos consulta el endpoint y agregar espera creciente entre reintentos cuando falla la obtención del token de MercadoPago.
5. (SRE) Ejecutar la consulta de C6 para verificar si el vencimiento de las credenciales 31 y 66 explica el inicio escalonado y cuántas credenciales entrarán en la ventana de 7 días.
6. (Dev / Operaciones) Identificar a los titulares de las 2 cuentas que fallan (credenciales 31 y 66) para que vuelvan a autorizar la vinculación con MercadoPago, y verificar el estado de las otras 3.
7. (SRE) Decidir, con Dev, una medida provisoria para frenar el volumen mientras se corrige: subir a Warning el nivel mínimo de `Microsoft.AspNetCore.Hosting.Diagnostics` y `System.Net.Http.HttpClient.*` en Business (~1,5 millones de mensajes por día entre ambos) y/o acortar la retención del index set de Business. No está decidido.
8. (SRE) Crear una alerta de Graylog o de Zabbix sobre el espacio libre de `/var/lib/opensearch` (por ejemplo al 80%, antes del umbral del 85% de OpenSearch) y sobre el crecimiento por index set.
9. (SRE) Leer los umbrales de disco efectivos de OpenSearch del cluster (se asumen los valores por defecto 85/90/95%).
10. (SRE) Revisar el crecimiento del index set de Orders.

## Hallazgos secundarios

- El Terraform de la infraestructura de Graylog de SmartCloud registra el disco de OpenSearch en 512 GB, pero el disco real es de 768 GB (diferencia entre la configuración y el recurso); queda por alinearlo y por revisar cómo factura Azure ese tamaño.
- El cluster de OpenSearch está en estado amarillo porque 9 índices de los sets de Business y Sales piden 1 réplica en un cluster de un solo nodo (18 shards sin asignar); no afecta el espacio en disco.
