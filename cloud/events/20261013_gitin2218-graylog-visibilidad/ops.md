# GITIN-2218 — [CLOUD] Visibilidad Graylog

**Etiquetas:** `Cloud`, `Graylog`, `Observabilidad`, `PROD`

## Resumen

Se construyó en el dashboard "Operations" (pestaña "HTTP") del Graylog de SmartCloud un conjunto de tres widgets por servicio, 24 en total, todos con rango de 24 h y limitados a los logs de aplicación (se excluye `category:AppServiceHTTPLogs`): un gráfico de líneas con los verbos HTTP (`Method`), un gráfico de líneas con los códigos de respuesta (`StatusCode`) y una tabla "Endpoints" con las 10 rutas más consultadas, con cantidad, máximo, promedio y percentil 90 de `ElapsedMilliseconds`. Los 8 servicios son Sales, Business, Catalog, Orders, Person, Platform, Client y POS WASM; cada widget usa el stream `PROD-<servicio>-AppServicePlan` correspondiente. Para que las tablas agrupen rutas con identificadores se creó la clave `NormalizedPath` ([GITIN-2221](https://smartit-ar.atlassian.net/browse/GITIN-2221), subtarea). Al armar las tablas se encontró que `ElapsedMilliseconds` casi no llegaba para Sales; se agregó el campo `ElapsedMillisecondsOpe` con el valor convertido y la tabla de Sales lo usa. El dashboard se ejecutó sin errores el 13-10-2026 (24 de 24 widgets con resultado). `NormalizedPath` y `ElapsedMillisecondsOpe` existen solo en los mensajes indexados después de los reinicios de Logstash del 13-10 (19:31 y 20:03 UTC), por lo que las tablas se completan durante las 24 h siguientes; los valores de las columnas de tiempo no se revisaron todavía.

## Tabla resumen

| Campo | Valor |
|---|---|
| Ticket Jira | [GITIN-2218](https://smartit-ar.atlassian.net/browse/GITIN-2218) |
| Tickets relacionados | [GITIN-2221](https://smartit-ar.atlassian.net/browse/GITIN-2221) (normalizar rutas HTTP), [GITIN-2209](https://smartit-ar.atlassian.net/browse/GITIN-2209) (disco de Graylog), [GITIN-2220](https://smartit-ar.atlassian.net/browse/GITIN-2220) (consultas a `WalletCredentials`), [GITIN-1940](https://smartit-ar.atlassian.net/browse/GITIN-1940) y [GITIN-2034](https://smartit-ar.atlassian.net/browse/GITIN-2034) (campos promovidos en Logstash) |
| ID alerta | NA |
| Sistema | Graylog 7.1.3 de SmartCloud (dashboard Operations), Logstash 8.19.18 en la VM `sfcloud-monitoreo` |
| Severidad | NA (mejora de observabilidad) |
| Detectado | 2026-10-13 |
| Resuelto | Sí, dashboard aplicado el 2026-10-13; la verificación de las tablas con datos completos queda pendiente (ver Acciones propuestas) |
| Responsable | SRE |

## Causa raíz

NA

## Hallazgos

| # | Hallazgo | Riesgo |
|---|---|---|
| H1 | La consulta pedida (`NOT Method: (...) AND Service: X`) también coincide con todo mensaje sin campo `Method`; se usó `_exists_:Method AND NOT Method:(PUT OR OPTIONS OR PATCH)` y se excluyó `AppServiceHTTPLogs`, que además evita contar dos veces una misma petición (`CsMethod`). La forma agrupada `_exists_:("Method" AND "StatusCode")` es válida en este servidor y equivale a dos `_exists_` separados; `EndPoint` no es un campo (0 resultados), el campo es `Path`. | Bajo |
| H2 | Valores de `Service` en logs de aplicación: `SmartFran.Cloud.{Orders,Catalog,Business,Platform,Person}.API`, `SmartFran.Cloud.Client.Web`, `Sales` y `smartfran-pos-wasm`. `SmartFran.Cloud.Security.API` devolvió 0 (el nombre fue una suposición; no se distinguió si no existe o no tuvo líneas con `Method`). Las líneas de `AppServiceHTTPLogs` no tienen `Service`. | Bajo |
| H3 | Los widgets existentes tenían rangos distintos (48 h y 5 minutos) y solo excluían `OPTIONS`; se unificaron a 24 h con la consulta definida. `StatusCode` está en aproximadamente la mitad de las líneas con `Method` de cada servicio, lo que es coherente con dos líneas por petición (una con `StatusCode`); no se verificó cuáles son, por lo que los gráficos de verbos podrían contar cerca del doble de las peticiones. | Medio |
| H4 | La API de vistas de Graylog 7.1.3 exige el cuerpo `{"entity": <vista>}`, `state` se indexa por id de pestaña, los títulos de widget están en `state.<pestaña>.titles.widget` y un widget nuevo requiere una búsqueda guardada nueva (`POST /views/search`) cuyo id va en `search_id`. Documentado en la referencia de campos de Graylog. | Bajo |
| H5 | En Business, los GET de aplicación pasan de unos 2.200 a 4.300 por día (05 al 07-10) a 675.435 el 08-10 y 2.078.674 el 09-10, y se mantienen entre 1,4 y 1,7 millones por día del 10 al 12-10. `GET /api/v1/WalletCredentials/{id}` explica entre el 75 % y el 91 % (cota inferior: se conservaron las 15 rutas principales por día). Otras tres rutas (`Franchise/GetSaleMovementSetup`, `Stock/ExistStockAddForSale`, `DiscountSurchargeRule/Effective`) pasaron de decenas a decenas de miles por día. No se miró quién llama; ver GITIN-2209 y GITIN-2220. | Alto |
| H6 | `ElapsedMilliseconds` de Sales llegaba en 1 de 6.547 líneas con `StatusCode` en una hora: el valor viene en `Properties` como texto en notación exponencial (`"0.453886e2"`) y el filtro de Logstash solo lo completa si es numérico. Los otros servicios lo tienen en casi tantas líneas como `StatusCode`. El motivo por el que llega como texto no está confirmado. | Medio |
| H7 | Se agregó `ElapsedMillisecondsOpe` (decimal) solo en la rama de Sales, sin modificar `ElapsedMilliseconds`. En 44 s después del reinicio, 30 de 30 líneas de Sales con `StatusCode` lo tienen (promedio 434,2 ms, máximo 2.045,1 ms; ventana corta). Aparece también en el índice `graylog_10`; no se investigó por qué. | Bajo |
| H8 | El promedio de `ElapsedMilliseconds` de Client (63.524,5 ms en una hora) probablemente está sesgado por conexiones largas de Blazor; no se verificó. | Bajo |
| H9 | En una ventana de 2 min 44 s después del primer reinicio, Business mostró unas 0,2 líneas por segundo de `WalletCredentials`, frente a unas 17 por segundo entre el 09 y el 12-10. La ventana es corta y no se sabe si el volumen bajó. | Medio |
| H10 | No se verificó si hubo pérdida o duplicado de mensajes durante los tres reinicios de Logstash. | Medio |

## Cambios aplicados

| # | Cambio | Reversión |
|---|---|---|
| 1 | 24 widgets (8 servicios × Method, Status Code, Endpoints), rango de 24 h, consulta con `_exists_:("Method" AND "StatusCode")` en los de códigos de respuesta, respaldo del dashboard anterior (7 widgets) | `widgets_apply.py rollback` (no probado) |
| 2 | Tablas Endpoints agrupan por `NormalizedPath`, top 10 | `widgets_path.py rollback` |
| 3 | Columnas máximo, promedio y percentil 90 de `ElapsedMilliseconds` en las 8 tablas | `widgets_metrics.py rollback` |
| 4 | La tabla de Sales usa `ElapsedMillisecondsOpe` | `widgets_sales_ope.py rollback` |
| 5 | Logstash: `NormalizedPath` y `ElapsedMillisecondsOpe` (detalle en GITIN-2221) | `deploy.sh rollback*` |

Cada script de dashboard es una simulación por defecto y solo escribe con `APPLY=1`; la reversión de cada uno restaura su propio respaldo.

## Recursos afectados

| Componente | Estado |
|---|---|
| Dashboard Operations (Graylog de SmartCloud), pestaña HTTP | 24 widgets; ejecución sin errores el 13-10 |
| Logstash en `sfcloud-monitoreo` | Tres reinicios el 13-10 (GITIN-2221) |

## Comandos ejecutados

| # | Comando / Script | Propósito |
|---|---|---|
| C1 | `scripts.sh`, `scripts-c2.sh` | Valores de `Service` y `category` con `Method`; variantes de la consulta |
| C2 | `scripts-c3.sh` | GET de Business por día y por ruta (origen de H5) |
| C3 | `scripts-c4.sh`, `scripts-c5.sh` | Dashboards existentes y consultas de sus widgets |
| C4 | `scripts-c6.sh` | Verificación de la sintaxis de las consultas |
| C5 | `widgets_apply.py` | Creación de los 24 widgets |
| C6 | `scripts-c9.sh`, `scripts-c10.sh`, `scripts-c11.sh` | Tipo y presencia de `ElapsedMilliseconds`, causa en Sales y verificación de `ElapsedMillisecondsOpe` |
| C7 | `widgets_path.py`, `widgets_metrics.py`, `widgets_sales_ope.py` | Cambios en las tablas Endpoints |
| C8 | `scripts-c8.sh` | Ejecución del dashboard y conteo de resultados y errores por widget |

## Acciones propuestas

1. (SRE) Revisar las tablas Endpoints cuando haya pasado un día completo desde el último reinicio de Logstash y validar los valores de máximo, promedio y percentil 90, en particular los de Sales.
2. (SRE) Repetir la verificación de `NormalizedPath` (`unmatched`) pasadas unas 24 horas (GITIN-2221).
3. (SRE) Verificar si las dos líneas con `Method` por petición son la causa de la mitad de `StatusCode` (H3) y, de ser así, decidir si los gráficos de verbos deben contar solo las líneas con `StatusCode`.
4. (SRE) Comparar el volumen de Logstash/Event Hub alrededor de los tres reinicios (H10).
5. (SRE) Decidir si el resto de los servicios debe completar `ElapsedMillisecondsOpe` y confirmar con Desarrollo por qué `ElapsedMilliseconds` de Sales llega como texto (H6).
6. (SRE) Seguir el volumen de `WalletCredentials` de Business (H5, H9) en GITIN-2220 y GITIN-2209.
7. (SRE) Confirmar si existe un servicio `Security` con logs de aplicación y, de existir, agregar su juego de widgets.
