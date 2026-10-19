# GITIN-2221 — [OPE] Normalizar HTTP Paths

**Etiquetas:** `Operaciones`, `Graylog`, `Logstash`, `SmartCloud`, `PROD`

## Resumen

Subtarea de [GITIN-2218](https://smartit-ar.atlassian.net/browse/GITIN-2218). En las tablas "Endpoints" del dashboard Operations de Graylog de SmartCloud, las rutas con identificadores (por ejemplo `/api/v1/WalletCredentials/2024771231`) se agrupaban por `Path` y cada identificador generaba una fila distinta. Se agregó en el Logstash de la VM `sfcloud-monitoreo` un filtro que calcula el campo nuevo `NormalizedPath` a partir de las rutas de los Controllers de SmartFran.Cloud (`/api/v1/WalletCredentials/2024771231` pasa a `api_v1_WalletCredentials`) y las 8 tablas Endpoints agrupan ahora por ese campo (top 10). Se aplicó en tres pasadas el 13-10-2026 (19:31, 19:44 y 20:03 UTC). La tercera agrega `ElapsedMillisecondsOpe` (ver H5). Solo los mensajes indexados después de cada reinicio tienen los campos nuevos; las tablas (rango de 24 h) completan su información durante el día siguiente. El porcentaje de rutas `unmatched` después de la segunda pasada no está medido todavía.

## Tabla resumen

| Campo | Valor |
|---|---|
| Ticket Jira | [GITIN-2221](https://smartit-ar.atlassian.net/browse/GITIN-2221) |
| Tickets relacionados | [GITIN-2218](https://smartit-ar.atlassian.net/browse/GITIN-2218) (ticket padre; gráficos y tablas del dashboard), [GITIN-1940](https://smartit-ar.atlassian.net/browse/GITIN-1940) y [GITIN-2034](https://smartit-ar.atlassian.net/browse/GITIN-2034) (promoción de `Path` y `ElapsedMilliseconds` en Logstash) |
| ID alerta | NA |
| Sistema | VM `sfcloud-monitoreo`: Logstash 8.19.18, `/etc/logstash/conf.d/azure-eventhub-to-graylog.conf`; Graylog 7.1.3 de SmartCloud |
| Severidad | NA (mejora de observabilidad) |
| Detectado | 2026-10-13, al armar las tablas Endpoints de GITIN-2218 |
| Resuelto | Sí, desplegado el 2026-10-13. Verificación sobre tráfico real parcial (H3, H4); ver Acciones propuestas |
| Responsable | SRE |

## Causa raíz

NA

## Hallazgos

| # | Hallazgo | Riesgo |
|---|---|---|
| H1 | Las rutas se extrajeron de los Controllers de la rama `origin/main` de SmartFran.Cloud (commit f88d6d743, 07-10-2026): 128 archivos `*Controller.cs`, 827 rutas, 792 plantillas distintas. La extracción es una expresión regular sobre los atributos `[Route]`/`[Http*]`, no un análisis con Roslyn; las rutas definidas de otra forma no están. Se agregaron a mano las rutas de Blazor, `health`, los hubs de SignalR (6), las páginas Razor leídas de las directivas `@page` (120), `_content/{*}`, `_framework/{*}` (valor `static`) y una lista de sufijos estáticos. Tabla final: 921 plantillas. Gana la plantilla con más segmentos literales; si ninguna coincide, el valor es `unmatched`. | Bajo |
| H2 | La tabla de plantillas se lee una sola vez al iniciar el filtro; si cambian las rutas hay que regenerarla y reiniciar Logstash. Rutas nuevas en los Controllers aparecen como `unmatched` hasta entonces. | Medio |
| H3 | Primera ventana real (2 min 44 s después del primer reinicio, antes de la segunda pasada): 7.983 mensajes con `Path` y 7.983 con `NormalizedPath`; 532 (6,7 %) `unmatched`, todos rutas que no son de Controllers (archivos estáticos, páginas Blazor/Razor, hubs de SignalR). Esos casos se cubrieron en la segunda pasada, que se probó con 83 rutas de ejemplo (83 de 83 como se esperaba) pero no se midió sobre tráfico real. | Bajo |
| H4 | El filtro se aplica a todo mensaje que tenga `Path`, por lo que incluye también las líneas de `AppServiceHTTPLogs` (que no tienen `Service`). Las tablas del dashboard solo usan los logs de aplicación. No está decidido si el alcance debe limitarse. | Bajo |
| H5 | `ElapsedMilliseconds` de Sales no llegaba: la rama de Sales solo lo completa si el valor es numérico, y en `Properties` de Sales llega como texto con notación exponencial (por ejemplo `"0.453886e2"`). Por eso Max/Avg/P90 de Sales mostraban 0. Se agregó el campo `ElapsedMillisecondsOpe` (decimal) con el valor convertido, sin modificar `ElapsedMilliseconds`. Verificado en una ventana de 44 s: 30 de 30 líneas de Sales con `StatusCode` lo tienen (promedio 434,2 ms, máximo 2.045,1 ms); tipo `float` en los índices que ya lo tienen. Orders, Person y Platform no lo completan (solo se cambió la rama de Sales). El motivo del texto exponencial no está confirmado. | Medio |
| H6 | El campo `ElapsedMillisecondsOpe` también aparece en el índice `graylog_10`; no se investigó por qué. | Bajo |
| H7 | No se verificó si hubo pérdida o duplicado de mensajes durante los tres reinicios de Logstash. Tras el primero (15 minutos) y el tercero (2 minutos) no se vieron líneas `ERROR`/`FATAL` del servicio; tras el segundo solo se comprobó que el servicio quedó `active`. Durante el apagado del primero el servicio registró un aviso de apagado demorado y avisos de conexión de Event Hub. | Medio |

## Antes y después

| Aspecto | Antes | Ahora |
|---|---|---|
| Tablas Endpoints, agrupación | Por `Path`; `/api/v1/WalletCredentials/2024771231` y `/api/v1/WalletCredentials/1357013702` eran filas distintas | Por `NormalizedPath`, top 10; ambas rutas pasan a `api_v1_WalletCredentials` |
| Campo nuevo | Ninguno | `NormalizedPath` en todo mensaje con `Path`; en la primera ventana (2 min 44 s), 7.983 de 7.983 mensajes lo tenían |
| Dónde se calcula | No se calculaba | Filtro Ruby en la configuración viva de Logstash en `sfcloud-monitoreo`; lee `/etc/logstash/normalized-paths.json` una vez al iniciar |
| Origen de las rutas | Ninguno | Atributos `[Route]`/`[Http*]` de los Controllers en `origin/main` (827 rutas, 792 plantillas distintas) más extras; 921 plantillas en total |
| Rutas que no son de Controllers | No aplica | Páginas Razor/Blazor y hubs de SignalR con plantilla propia; `_content`, `_framework` y extensiones de archivos estáticos dan `static`; el resto da `unmatched` |
| Porcentaje `unmatched` | No aplica | 6,7 % (532 de 7.983) tras la primera pasada; tras la segunda no está medido (la prueba con 83 rutas dio 83 de 83 como se esperaba) |
| Columnas Max / Avg / P90 | No existían; las tablas solo mostraban la cantidad | Agregadas a las 8 tablas a partir de `ElapsedMilliseconds`; el dashboard se ejecutó sin errores |
| Tiempos de Sales | Max/Avg/P90 mostraban 0: solo 1 de 6.547 líneas por hora traía `ElapsedMilliseconds`, porque llega como texto (`"0.453886e2"`) | Campo nuevo `ElapsedMillisecondsOpe` (decimal) con el valor convertido; la tabla de Sales lo usa; en una verificación de 44 s, 30 de 30 líneas de Sales lo tenían; `ElapsedMilliseconds` no se modificó |
| Tiempos de los otros servicios | Usan `ElapsedMilliseconds` | Sin cambios; no completan `ElapsedMillisecondsOpe` (cambio solo en Sales) |
| Alcance del filtro | No aplica | También se ejecuta sobre `AppServiceHTTPLogs`, no solo sobre los logs de aplicación; no está decidido limitarlo |
| Reinicios de Logstash | Ninguno | Tres el 13-10-2026 (19:31, 19:44 y 20:03 UTC), cada uno probado antes y con reversión; la pérdida de mensajes no está verificada |
| Contenido de las tablas | Rutas de las últimas 24 h | Parcial hasta aproximadamente un día después del último reinicio, porque solo los mensajes nuevos traen los campos nuevos |

## Cambios aplicados

| # | Fecha (UTC) | Cambio | Respaldo / reversión |
|---|---|---|---|
| 1 | 13-10 19:31 | Filtro Ruby que calcula `NormalizedPath` (796 plantillas) antes del paso final de `properties`; reinicio de Logstash | `deploy.sh rollback` |
| 2 | 13-10 19:44 | Tabla ampliada a 921 plantillas y tratamiento de `static`; reinicio | `deploy.sh rollback-update` |
| 3 | 13-10 20:03 | Campo `ElapsedMillisecondsOpe` en la rama de Sales; reinicio | `deploy.sh rollback-fix` |
| 4 | 13-10 | Dashboard Operations (GITIN-2218): las 8 tablas Endpoints agrupan por `NormalizedPath` (top 10); se agregaron Max, Avg y P90 de `ElapsedMilliseconds` (Sales usa `ElapsedMillisecondsOpe`). El dashboard se ejecutó sin errores (24 de 24 widgets con resultado) | modo `rollback` de cada script de dashboard |

Cada paso de `deploy.sh` respalda la configuración (el respaldo no termina en `.conf`, porque `pipelines.yml` carga `conf.d/*.conf`), valida con `logstash -t` sobre una copia, prueba el filtro en un proceso de Logstash aparte contra resultados esperados y solo entonces aplica y reinicia; si algo falla, restaura sin reiniciar. Las credenciales de la configuración (`event_hub_connections`, `storage_connection`) se ocultaron en el origen antes de guardar cualquier copia en el evento.

## Recursos afectados

| Componente | Estado |
|---|---|
| Logstash en `sfcloud-monitoreo` | Configuración modificada y reiniciado tres veces el 13-10 (servicio `active` después de cada una) |
| `/etc/logstash/normalized-paths.json` | Archivo nuevo, 921 plantillas, lectura única al iniciar |
| Dashboard Operations de Graylog de SmartCloud | 8 tablas Endpoints modificadas |

## Comandos ejecutados

| # | Comando / Script | Propósito |
|---|---|---|
| C1 | `scripts.sh`, `scripts-c2.sh` | Traer la configuración viva de Logstash con credenciales ocultas |
| C2 | `routes_extract.py`, `routes_match.py`, `gen_table.py` | Extraer las rutas de los Controllers, probar el matcher y generar la tabla |
| C3 | `deploy.sh` (modos `stage`, `test`, `apply`, `update`, `fix`) | Instalar y probar la tabla, aplicar los parches y reiniciar Logstash |
| C4 | `scripts-c3.sh` | Estado de la VM después del primer reinicio |
| C5 | `scripts-c4.sh` | Verificar en Graylog que los mensajes traen `NormalizedPath` |
| C6 | GITIN-2218: `widgets_path.py`, `widgets_metrics.py`, `widgets_sales_ope.py`, `scripts-c8.sh`, `scripts-c11.sh` | Cambios y verificación del dashboard y de `ElapsedMillisecondsOpe` |

## Acciones propuestas

1. (SRE) Repetir `scripts-c4.sh` pasadas unas 24 horas del último reinicio para medir el porcentaje real de `unmatched` y revisar las rutas que quedan.
2. (SRE) Revisar las tablas Endpoints cuando haya pasado un día completo; hasta entonces muestran menos tráfico que el real.
3. (SRE) Comparar el volumen de mensajes de Logstash/Event Hub alrededor de los tres reinicios para descartar pérdida (H7).
4. (SRE) Decidir con el equipo si `NormalizedPath` debe limitarse a los logs de aplicación (H4) y si el resto de los servicios debe completar `ElapsedMillisecondsOpe` (H5).
5. (SRE) Regenerar la tabla de plantillas y reiniciar Logstash cuando se agreguen rutas a los Controllers (H2); evaluar con Desarrollo registrar la plantilla de la ruta en la aplicación para no depender de la tabla.
6. (SRE) Investigar por qué `ElapsedMillisecondsOpe` aparece en `graylog_10` (H6).
