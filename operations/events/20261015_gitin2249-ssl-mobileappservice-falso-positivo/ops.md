# [OPE] Zabbix: MobileAppService falso positivo

**Tags:** `Operaciones`, `Obserbavilidad`, `SRE`, `PROD`

## Resumen

El 2026-10-15 a las 10:04:52 Zabbix abrió el problema "SSL MobileAppService a menos de 7 dias de vencer" con el detalle `Triggered: 0 | Actual: 17`. Ese día el verificador de certificados registró una lectura de 0 días (el certificado tenía 20 días la noche anterior y 20 tres horas después), y el nivel High quedó abierto aunque el valor real era de 17 a 20 días. El script que alimenta el ítem imprime 0 cuando no logra leer el certificado, y el nivel High solo se recupera con 30 días o más, así que el problema seguirá abierto hasta que el certificado se renueve. Se decidió no aplicar cambios y dejar la configuración como está.

## Tabla resumen

| Campo | Valor |
|---|---|
| Ticket Jira | [GITIN-2249](https://smartit-ar.atlassian.net/browse/GITIN-2249) |
| ID alerta | Evento 716831 (trigger 26284, nivel High) |
| Sistema | Zabbix 6.0.32 (sf-monitoreo.smartfran.com), ítem `get_ssl_enddate_mobileappservice` del host Zabbix server |
| Severidad | Baja |
| Detectado | 2026-10-15 10:04:52 (UTC-3) |
| Resuelto | No — se dejó sin cambios por decisión del usuario; el problema sigue abierto |
| Responsable | Operaciones (SRE) |

## Causa raíz

El script `get_enddate.sh`, que corre cada hora desde el crontab del usuario `ubuntu` del servidor Zabbix, imprime 0 cuando `openssl` no obtiene el certificado (sin salida de error ni código de retorno), y ese 0 se escribe en el log que lee Zabbix como si fuera una lectura real. El comportamiento del script con una respuesta vacía se reprodujo en una máquina local (con GNU date 9.4, no en el servidor). Con esa lectura, el nivel High (menos de 7 días) se abrió; como su recuperación exige 30 días o más y el certificado tiene 17, el problema queda abierto hasta la renovación. Qué hizo fallar la conexión a `mobileservice.clubgrido.com.ar:8043` entre las 10:00 y las 12:00 (UTC-3) del 2026-10-15 no se determinó.

## Hallazgos

- Las lecturas del ítem bajan un día por día, de 34 el 2026-09-30 a 17 el 2026-10-17, sin renovación en ese período. El 2026-10-15 hay dos lecturas fuera del horario diario (21:04:52): 0 a las 10:04:52 y 20 a las 13:04:52.
- Solo el nivel High (trigger 26284) está abierto, desde las 10:04:52 del 2026-10-15, con un único evento y sin evento de recuperación. Warning (25914) y Average (26282) no se abrieron; es coherente con las dependencias definidas en [GITIN-2156](https://smartit-ar.atlassian.net/browse/GITIN-2156) (Warning depende de Average y High; Average, de High), pero esa relación no se probó.
- Las macros vigentes son `{$SSL_CERT_WARN:LE}`=15, `{$SSL_CERT_AVERAGE:LE}`=10, `{$SSL_CERT_HIGH:LE}`=7 y `{$SSL_CERT_OK:LE}`=30; el umbral de 7 días de la alerta es el configurado.
- El log `/var/log/zabbix/ssl_mobileappservice.log` se sobrescribe cada hora (`tee`) y contiene solo el último valor, por lo que no conserva el historial de lo que escribió el script.
- Los otros siete ítems de vencimiento SSL (ClubSite AR y PY, fs-api, smartfran, webservicecg, webservicev2, website) tuvieron una sola lectura el 2026-10-15 y ninguna fue 0. Los ocho comparten el mismo cron y Zabbix solo guarda un valor cuando el archivo cambia, de modo que el servidor de monitoreo pudo leer los otros siete certificados en esa ventana; el fallo fue específico de MobileAppService o de la ruta hacia él.
- Es un caso del mismo tipo que [GITIN-2028](https://smartit-ar.atlassian.net/browse/GITIN-2028) (trigger que queda abierto porque su recuperación exige un valor alto), con otra causa: allí fue un contexto de macro equivocado; aquí las macros son las correctas.

## Recursos afectados

| Recurso | Detalle |
|---|---|
| Trigger | 26284 «SSL MobileAppService a menos de {$SSL_CERT_HIGH:LE} dias de vencer» (nivel High), abierto desde 2026-10-15 10:04:52 |
| Ítem | 53392 `get_ssl_enddate_mobileappservice` (host Zabbix server), intervalo de 15 minutos |
| Script y cron | `get_enddate.sh`, crontab del usuario `ubuntu` del servidor Zabbix, una ejecución por hora; el mismo script alimenta los otros siete ítems de vencimiento SSL |

## Comandos ejecutados

Solo lecturas sobre el Zabbix y el servidor de monitoreo; no se modificó ninguna configuración.

| # | Qué se leyó |
|---|---|
| 1 | Historial del ítem 53392 (2026-10-14 al 2026-10-15) y últimos 20 valores en los cinco tipos de historial |
| 2 | Estado y eventos de los triggers 25914, 26282 y 26284; macros globales de SSL |
| 3 | En el servidor: log del ítem, crontabs, directorios de scripts y el contenido de `get_enddate.sh` |
| 4 | Reproducción local del script con una respuesta vacía de `openssl` |
| 5 | Historial del 2026-10-15 de los ocho ítems de vencimiento SSL |

## Acciones propuestas

1. **Sin cambios (decidido):** se deja la configuración como está; el problema del nivel High seguirá abierto hasta que el certificado tenga 30 días o más.
2. Opciones evaluadas y no aplicadas, para si el caso se repite:
   - Que el script no escriba 0 cuando no obtiene el certificado, de modo que Zabbix quede en «sin datos» (los triggers de «No data» tienen una ventana de 2 días). Cubriría también los otros siete servicios, que usan el mismo script.
   - Que el trigger ignore las lecturas de 0 (por ejemplo, exigir también un valor mayor que 0); a cambio, un certificado que realmente venza ese día dejaría de avisar en el nivel High.
   - Bajar el umbral de recuperación del nivel High (por ejemplo, 15 en lugar de 30), lo que cambia el criterio definido en GITIN-2156.
3. Pendiente sin fecha: determinar por qué falló la conexión a MobileAppService entre las 10:00 y las 12:00 del 2026-10-15.
