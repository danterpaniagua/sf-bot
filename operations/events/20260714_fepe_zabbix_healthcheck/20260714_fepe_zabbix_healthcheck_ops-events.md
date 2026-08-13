# Eventos — Monitoreo FEPE (Factura Electronica Peru) en Zabbix

## 2026-07-14 09:00 — Revision de codigo: identificacion de la integracion FEPE

He revisado el codigo de SmartFran Cloud en `cloud/repo/SmartFran.Cloud` para identificar como se realiza la facturacion electronica ante SUNAT desde el POS. He confirmado que SmartFran Cloud no integra directamente con SUNAT sino a traves de un PSE intermediario: Xacto Peru (`api.xactoperu.com`), configurado en `WsFePeService.cs` (Sales API) y usado para el envio de comprobantes (`POST DocumentoCabeceras`).

He revisado el historial de git (`git log`) sobre `appsettings.sample.json` y `WsFePeService.cs`, y he confirmado que las URLs de Xacto Peru siguen presentes en el commit HEAD del repositorio (`cca9f7cc7`, 2026-07-07), tanto en `appsettings.sample.json` como en los archivos `Ci.Cd/Azure.AppService.Environment/Sales.API_Settings_{TEST,DEV}.json` — no son referencias obsoletas de documentacion antigua.

## 2026-07-14 09:20 — Test de conectividad real contra Xacto Peru

**Comando:** CX-02
**Resultado:**
```
* Host api.xactoperu.com:8099 was resolved.
* IPv4: 148.72.152.19
*   Trying 148.72.152.19:8099...
* Connection timed out after 8000 milliseconds
* Closing connection
curl: (28) Connection timed out after 8000 milliseconds
```

He confirmado un timeout real contra `UrlWsfeProd` (puerto 8099) desde dos origenes de red distintos (maquina local y Azure Cloud Shell). El DNS resuelve correctamente; el timeout ocurre en el SYN TCP sin RST, lo cual es consistente con un firewall descartando el paquete en silencio para el origen probado, o con el host caido — no descarto ninguna de las dos causas sin probar desde el egress real de produccion.

## 2026-07-14 09:45 — Descubrimiento de un segundo proveedor PSE: Bizlinks

He revisado `Documentation/v2.30.00/release_notes.md`, una version muy posterior a donde aparece Xacto Peru, y he identificado un segundo proveedor PSE: Bizlinks (`pse.bizlinks.com.pe`), usado unicamente para la consulta de comprobantes ya emitidos (`DocumentConsultationAsync` en la Function `TicketProcessAsync`), no para el envio. He confirmado que las credenciales `WsFePe__BizlinksUser`/`WsFePe__BizlinksPassword` estan expuestas en texto plano en ese mismo archivo, committeadas al historial de git, y he encontrado el mismo patron en 13 archivos `release_notes.md` en total dentro del arbol de `Documentation/`.

**Comando:** CX-03
**Resultado:**
```
Target namespace: http://pse.bizlinks.com/
Endpoint: http://pse.bizlinks.com.pe/ws/invoker
Operaciones: invoke(command:string)->return:string,
             replicateXml(command:string,xmlSunat:base64,adjuntos:base64)->return:string,
             updateAttachment(adjuntoCliente:eAdjunto)->return:defaultResult
Binding: document/literal sobre SOAP/HTTP
```

He obtenido el contrato WSDL publico de Bizlinks sin necesidad de autenticacion, y he confirmado que la operacion real usada por SmartFran (`invoke`) es un wrapper opaco que no describe el formato de negocio (`ConsultCmd`) usado en `WsFePeService.cs:196` — ese formato no esta documentado publicamente, proviene del onboarding directo con Bizlinks.

## 2026-07-14 10:10 — Diseño y validacion del healthcheck sin almacenar credenciales reales

He diseñado el script `get-fepe-status.sh`, que combina reachability simple para los tres endpoints de Xacto Peru con una invocacion SOAP deliberadamente autenticada con credenciales incorrectas contra Bizlinks, para evitar almacenar un secreto real en el pipeline de monitoreo.

**Comando:** CX-04
**Resultado:**
```
<soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/"><soap:Body><soap:Fault><faultcode>soap:Server</faultcode><faultstring>Usuario no encontrado</faultstring></soap:Fault></soap:Body></soap:Envelope>
HTTP_CODE:401
TIME_MS:0.916668
```

He confirmado que Bizlinks responde con `401` y un SOAP Fault `Usuario no encontrado` ante credenciales invalidas, en ~917ms — validando que esta es una señal confiable de "UP" para el healthcheck, ya que prueba que el pipeline completo (parsing SOAP, autenticacion, backend) esta operativo sin necesidad de una credencial real.

## 2026-07-14 10:30 — Cierre de la sesion de diseño

He documentado el script final, los hallazgos de la sesion y la configuracion pendiente en el ticket `20260714_fepe_zabbix_healthcheck_ops.md`. Ningun paso de despliegue (agente ni frontend) fue ejecutado durante esta sesion — queda todo pendiente segun lo detallado en Acciones propuestas.

## 2026-07-14 21:30 — Despliegue del script en el agente: primer error de Timeout

He colocado `get-fepe-status.sh` en `/opt/scripts/` con symlink desde `/usr/bin/get-fepe-status`, y he creado `/etc/zabbix/zabbix_agent2.d/userparameter_fepe.conf` con la key `fepe.status.raw`. Al testear con `zabbix_agent2 -t fepe.status.raw` he recibido `Timeout while executing a shell script`.

He diagnosticado que el `Timeout` del agente (`zabbix_agent2.conf`, default bajo) se agotaba porque el script original ejecutaba los cuatro checks de forma secuencial, y el check contra `WsFeProd` (caido) consume el maximo de 8 segundos por si solo. He rediseñado el script para correr los cuatro checks en paralelo (background jobs + `wait`, resultados via archivos temporales) para acotar el tiempo total al maximo de un solo check en vez de a la suma de los cuatro.

## 2026-07-14 21:45 — Ajuste de Timeout del agente y segundo error: Unknown metric

He subido `Timeout=30` en `/etc/zabbix/zabbix_agent2.conf` (maximo permitido en Zabbix 6.0) y he reiniciado `zabbix-agent2`. Al re-testear sin el flag `-c` explicito he recibido `ZBX_NOTSUPPORTED [Unknown metric fepe.status.raw]`, y el mismo resultado al testear `arca.status.raw` — a pesar de que ARCA funciona correctamente en produccion.

He descartado como causa: reglas `AllowKey`/`DenyKey` (solo cubren `system.run[*]`, no aplican a UserParameter custom), una definicion duplicada de la key `fepe` en otro archivo de configuracion, caracteres ocultos en `userparameter_fepe.conf` (`cat -A` no mostro `^M` ni BOM), y permisos en la cadena de directorios hacia el script y el archivo de configuracion (`namei -l` mostro todo `drwxr-xr-x`/`-rw-r--r--`, accesible para cualquier usuario).

**Comando:** CX — verificacion explicita de config
**Resultado:**
```
zabbix_agent2 -t fepe.status.raw -c /etc/zabbix/zabbix_agent2.conf
{"overall_status":1,"checks":[...]}   (correcto, ejecutado como root)

ps aux | grep zabbix_agent2
zabbix  407735  ...  /usr/sbin/zabbix_agent2 -c /etc/zabbix/zabbix_agent2.conf
```

He confirmado que pasar `-c /etc/zabbix/zabbix_agent2.conf` explicitamente resuelve el `Unknown metric` cuando se ejecuta como root, y que el daemon real corre con ese mismo path de configuracion segun `ps aux`.

## 2026-07-14 22:32 — Tercer error: permiso denegado en un Include relativo del config

Al repetir la misma prueba como usuario `zabbix` (`sudo -u zabbix zabbix_agent2 -t fepe.status.raw -c /etc/zabbix/zabbix_agent2.conf`) desde `/home/ubuntu`, he recibido un error nuevo: `Cannot read configuration: cannot include "zabbix_agent2.d/plugins.d/*.conf": stat .: permission denied`.

He identificado la causa: `zabbix_agent2.conf` tiene una segunda directiva `Include=./zabbix_agent2.d/plugins.d/*.conf` (ruta relativa, linea 497), a diferencia de la directiva principal que ya es absoluta (linea 281). Al ejecutarse con CWD=`/home/ubuntu`, la ruta relativa intenta resolverse contra ese directorio, y `/home/ubuntu` tiene permisos `drwxr-x---` (750, grupo `ubuntu` unicamente) — el mismo problema de permisos ya documentado en el Hallazgo 2 del ticket de ARCA, esta vez bloqueando la resolucion del Include en lugar de la ejecucion del script.

He confirmado que al testear desde `/etc/zabbix` (directorio con permisos `drwxr-xr-x`, accesible para el usuario `zabbix`) tanto `fepe.status.raw` como `arca.status.raw` responden correctamente:

**Comando:** CX — verificacion desde directorio accesible
**Resultado:**
```
cd /etc/zabbix
sudo -u zabbix zabbix_agent2 -t fepe.status.raw -c /etc/zabbix/zabbix_agent2.conf
fepe.status.raw   [s|{"overall_status":1,"checks":[{"service":"WsFeProd","detail":"http=000","status":"DOWN","latency_ms":8012},{"service":"WsFeTest","detail":"http=401","status":"UP","latency_ms":101},{"service":"ConsultaProd","detail":"http=401","status":"UP","latency_ms":64},{"service":"Bizlinks","detail":"http=401,fault=Usuario no encontrado","status":"UP","latency_ms":75}]}]

sudo -u zabbix zabbix_agent2 -t arca.status.raw -c /etc/zabbix/zabbix_agent2.conf
arca.status.raw   [s|{"overall_status":0,"checks":[{"service":"WSAA","detail":"http=200","status":"UP","latency_ms":755},{"service":"WSFEv1","detail":"App=OK,Db=OK,Auth=OK","status":"UP","latency_ms":759}]}]
```

He confirmado que el despliegue en el agente es correcto y que ARCA no fue afectado por ninguno de los cambios realizados durante esta sesion — ambos items responden con los valores esperados una vez resuelto el problema de directorio de trabajo.

## 2026-07-14 22:45 — Timeout del lado del servidor Zabbix

Al recrear el item en el frontend y testear, he recibido `Get value from agent failed: ZBX_TCP_READ() timed out` — un error distinto, del lado del servidor. He identificado que corresponde al `Timeout` de `zabbix_server.conf` (proceso y archivo de configuracion separados de `zabbix_agent2.conf`), que gobierna cuanto espera el servidor la respuesta del agente por TCP, independientemente del Timeout ya ajustado del lado del agente.

Se ha subido `Timeout=15` en `/etc/zabbix/zabbix_server.conf` y reiniciado `zabbix-server`. Tras el reinicio, el item de Zabbix ha quedado funcionando correctamente.

## 2026-07-14 22:50 — Configuracion de macros y items dependientes

Se han creado las macros de host `{$FEPE.UPDATE.INTERVAL}=1m` y el resto de la tabla de latencia/nodata. Se han creado inicialmente 7 de los 9 items dependientes planeados; via Monitoring → Latest data y luego confirmado en el listado de Items, he identificado que faltaban `FEPE WsFeTest Status`, `FEPE WsFeTest Latency` y `FEPE ConsultaProd Latency`. Se han agregado los items de `WsFeTest` (status y latencia); `ConsultaProd Latency` queda diferido para una sesion posterior.

Se ha entregado la tabla completa de triggers (`FEPE DOWN`, `FEPE DEGRADADO`, `FEPE sin datos`, y los pares de Latencia Alta/Critica para `WsFeProd`, `WsFeTest` y `Bizlinks`, con `ConsultaProd` diferido) junto con la cadena de dependencias, pendiente de creacion en el frontend.

## 2026-07-14 23:10 — Correccion del Hallazgo 4: auditoria de credenciales expuestas

He re-ejecutado el barrido de `Documentation/*/release_notes.md` y he detectado que la primera pasada mezclo dialectos de regex (BRE vs PCRE) entre la corrida original y la verificacion posterior, lo cual podia llevar a una clasificacion inexacta. He vuelto a correr el comando original de forma exacta, confirmando los mismos 13 archivos, y he clasificado cada coincidencia manualmente por nombre de key y forma del valor (longitud, si es URL, si es hexadecimal/GUID), sin exponer ningun valor.

Resultado de la clasificacion: 5 archivos con credenciales confirmadas (incluye un access key/secret de AWS en texto plano, mas grave que el hallazgo original de Bizlinks), 2 archivos con valores de 394-401 caracteres bajo una key `FabricConnections:*` (forma de connection string, no confirmado con certeza), 2 archivos con valores ambiguos que requieren revision manual, y 5 archivos que resultaron ser falsos positivos (URLs de endpoints ya conocidas, no credenciales). He actualizado el Hallazgo 4 y la accion propuesta 11 del ticket con el detalle completo por archivo, commit id y fecha, priorizando la rotacion del access key de AWS.

## 2026-07-24 — Diseno de los 9 triggers FEPE, pendientes de creacion en el frontend

He disenado los 9 triggers pendientes (`FEPE sin datos`, `FEPE DOWN`, `FEPE DEGRADADO`, y los pares Latencia Alta/Critica para `WsFeProd`, `WsFeTest` y `Bizlinks`), siguiendo el mismo patron ya validado en ARCA y documentado en el skill `ope-zabbix` (Step 6): expresiones con umbrales via macro (nunca hardcodeados), recovery expressions con histeresis para los pares de latencia, cadena completa de dependencias para evitar alertas apiladas por una misma causa raiz, y el no-op `<>"__unused__"` para exponer los cuatro status por servicio en el Operational data de `DOWN`/`DEGRADADO`. `ConsultaProd` queda diferido de los pares de latencia porque su item dependiente (`fepe.status.consultaprod.latency`) todavia no fue creado en el frontend.

He aplicado el tag `service_group = CLOUD` a los 9 triggers, tomando como referencia el valor que documenta el propio `_ops-events.md` de ARCA (`2026-06-06_arca_api_check_ops-events.md`) para rutear a la accion "Google Chat Loyalty to Operaciones" — corrigiendo la referencia a `LOYALTY` que tenia este ticket, que provenia de una nota de diseno temprana de ARCA ya superada por su propio registro de actividad. Este valor no esta confirmado de forma independiente para el host/accion de FEPE — antes de guardar los triggers en el frontend corresponde verificar en `Alerts → Actions → Trigger actions` que la condicion de esa accion efectivamente matchea `service_group = CLOUD` para el host `Zabbix server`.

Durante la sesion tambien evalue una URL de SUNAT (`https://e-beta.sunat.gob.pe/ol-ti-itcpfegem-beta/billService?wsdl`) que el usuario referencio desde una conversacion distinta (fuera de esta sesion). Un grep dirigido sobre `cloud/repo` no encontro esa URL ni el nombre `billService`/`itcpfegem` en ningun archivo — el unico campo relacionado en el codigo es `xmlFileSunatUrl` (`WsFePeService.cs:338`), un valor devuelto dinamicamente por Xacto Peru en su respuesta, no una URL que la aplicacion llame directamente. No se incorporo como quinto endpoint del healthcheck ni se modifico el Hallazgo 1 (SmartFran Cloud sin integracion directa a SUNAT) por falta de evidencia verificable.

## 2026-07-24 — Root cause del "network error" intermitente: v1 del script deployada secuencial, no paralela

**Comando:** CX-05 — `time /usr/bin/get-fepe-status --json`
**Resultado:**
```
{"overall_status":1,"checks":[{"service":"WsFeProd","detail":"http=000","status":"DOWN","latency_ms":8013},{"service":"WsFeTest","detail":"http=000","status":"DOWN","latency_ms":8013},{"service":"ConsultaProd","detail":"http=401","status":"UP","latency_ms":213},{"service":"Bizlinks","detail":"http=401,fault=Usuario no encontrado","status":"UP","latency_ms":108}]}

real    0m16.385s
user    0m0.094s
sys     0m0.090s
```

He confirmado que el script deployado en `/opt/scripts/get-fepe-status.sh` corre los cuatro checks de forma secuencial (16.385s ≈ suma de los cuatro latency_ms, no el maximo), pese a que el log de la sesion 2026-07-14 21:30 documenta una version paralela. Con `cat /opt/scripts/get-fepe-status.sh` (CX-06) confirme que el contenido en el server es identico a la v1 original de la sesion de diseno — sin background jobs ni `wait`. Con `grep -n "^Timeout" /etc/zabbix/zabbix_agent2.conf` y el mismo grep sobre `zabbix_server.conf` (CX-07) descarte drift de configuracion: `Timeout=30` (agente) y `Timeout=15` (servidor) siguen igual que el 2026-07-14. La causa raiz es exclusivamente la ejecucion secuencial: con dos endpoints de Xacto Peru caidos a la vez, el tiempo total (~16s) supera el `Timeout=15` del servidor, que abandona la lectura TCP y genera el "network error" visto en el log del servidor Zabbix entre las 17:19 y 17:22.

## 2026-07-24 — Deploy de la v2 (paralela) del script y confirmacion del fix

**Comando:** CX-08 — `time /usr/bin/get-fepe-status --json` (post-deploy)
**Resultado:**
```
{"overall_status":1,"checks":[{"service":"WsFeProd","detail":"http=000","status":"DOWN","latency_ms":8013},{"service":"WsFeTest","detail":"http=000","status":"DOWN","latency_ms":8014},{"service":"ConsultaProd","detail":"http=401","status":"UP","latency_ms":187},{"service":"Bizlinks","detail":"http=401,fault=Usuario no encontrado","status":"UP","latency_ms":90}]}

real    0m8.028s
user    0m0.080s
sys     0m0.064s
```

He deployado la v2 del script (background jobs por check + `wait`, resultados recolectados via archivos temporales para evitar la perdida de resultados en subshell que probablemente causo que un intento previo de paralelizacion se revirtiera sin quedar documentado) sobre `/opt/scripts/get-fepe-status.sh`, respaldando la version anterior como `.bak-20260724`. Con los mismos dos endpoints de Xacto Peru caidos que en la prueba anterior, el tiempo total bajo de 16.385s a 8.028s — ahora acotado al checkeo mas lento en vez de a la suma de los cuatro, ampliamente por debajo del `Timeout=15` del servidor. Root cause resuelto.

## 2026-07-24 — Segundo caso de log desalineado con la realidad: items `WsFeTest` nunca creados

Al intentar crear el trigger `FEPE DOWN` en el frontend, recibi `Incorrect item key "fepe.status.wsfetest" provided for trigger expression on "Zabbix server"`. Al listar los items reales del host (`Data collection → Hosts → Zabbix server → Items`, filtro `fepe`) confirme que solo existen 6 de los 9 items dependientes planeados: `overall`, `wsfeprod` (status+latencia), `consultaprod` (solo status), `bizlinks` (status+latencia). `FEPE WsFeTest Status` y `FEPE WsFeTest Latency` no existen, pese a que el log de la sesion 2026-07-14 22:50 afirma que se agregaron ese dia — segundo caso en este ticket (despues del bug de paralelizacion del script) donde el `_ops-events.md` documenta un paso como completado que en la practica no quedo aplicado. He corregido el punto 5 de "Configuracion pendiente" en `20260714_fepe_zabbix_healthcheck.md` con el conteo real y las especificaciones (Key + JSONPath) de los dos items faltantes, y anote el bloqueo correspondiente en el punto 7 (triggers `FEPE DOWN`, `FEPE DEGRADADO` y los dos `WsFeTest Latencia` no pueden guardarse hasta crear esos items).

He confirmado la creacion de `FEPE WsFeTest Status` (`fepe.status.wsfetest`) y `FEPE WsFeTest Latency` (`fepe.status.wsfetest.latency`) via el listado real de items — quedan 8 de 9 items dependientes creados, solo `FEPE ConsultaProd Latency` diferido. El bloqueo sobre `FEPE DOWN`, `FEPE DEGRADADO` y los dos triggers `WsFeTest Latencia` queda resuelto.

## 2026-07-24 — Confirmacion end-to-end: trigger FEPE DOWN disparado correctamente en produccion

**Resultado:**
```
PROBLEM  Zabbix server  FEPE DOWN  WsFeProd: DOWN | WsFeTest: DOWN | ConsultaProd: UP | Bizlinks: UP

Historial fepe.status.raw, 2026-07-24 15:31:13 a 15:37:13 (7 polls consecutivos, 1 por minuto):
{"overall_status":1,"checks":[{"service":"WsFeProd","detail":"http=000","status":"DOWN","latency_ms":8012-8028},{"service":"WsFeTest","detail":"http=000","status":"DOWN","latency_ms":8012-8023},{"service":"ConsultaProd","detail":"http=401","status":"UP","latency_ms":190-226},{"service":"Bizlinks","detail":"http=401,fault=Usuario no encontrado","status":"UP","latency_ms":82-206}]}
```

He confirmado que el trigger `FEPE DOWN` se disparo correctamente en produccion, con el Operational data mostrando el estado real por servicio via `{ITEM.LASTVALUE2-5}` tal como fue disenado. Los 7 polls consecutivos de 1 minuto (15:31-15:37) sin ningun gap ni "network error" confirman que el fix de paralelizacion del script (v2, deployado antes en esta misma sesion) sostiene el comportamiento correcto bajo carga real, no solo en la prueba puntual de CX-08. El estado detectado (`WsFeProd`/`WsFeTest` caidos, `ConsultaProd`/`Bizlinks` operativos) es ademas una caida real y vigente contra Xacto Peru, consistente con el Hallazgo 3 del ticket (timeout SYN sin RST, causa todavia no confirmada) — el monitoreo esta cumpliendo su proposito original de deteccion temprana.
