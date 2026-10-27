# Propuesta: configuración de IIS del WebService ante tráfico masivo no habitual ([GITIN-2316](https://smartit-ar.atlassian.net/browse/GITIN-2316))

## Situación
El 26/10, entre las 21:14 y las 22:00 (UTC-3), una única IP externa envió 133.048 pedidos GET al WebService (`SFCG-WEBS-01`, sitio `W3SVC2`, puerto 8080), con picos de más de 300 pedidos por segundo. El 99,97 % recibió 404; no hubo respuestas 200 ni 500 de esa IP, y recibió 403 y 301 de las carpetas `config` y `service`. El tráfico legítimo máximo medido por IP es de 5 pedidos por segundo. No se determinó el origen.

Estado actual de IIS en `SFCG-WEBS-01`: Dynamic IP Restrictions en modo solo registro, aplicado a nivel de servidor (100 pedidos por 1.000 ms por IP), con respaldo `before-gitin2316-dynip`. `SFCG-WEBS-02` y `SFCG-WEBS-03` no tienen regla.

## Cambios de configuración de IIS propuestos

| # | Característica de IIS | Configuración propuesta | Qué logra | Límites |
|---|---|---|---|---|
| 1 | Dynamic IP Restrictions | Mantener 100 pedidos por 1.000 ms por IP; desactivar el modo solo registro; acción de denegación 403 (`Forbidden`) | Corta por tasa a cualquier IP que supere el umbral, unas 20 veces el máximo legítimo medido | En la prueba en modo registro solo se marcaron 108 de 800 pedidos a 925 req/s: reduce el barrido pero no detiene cada pedido. Una IP compartida por muchos clientes (como `10.1.0.4`, visto en la prueba) cuenta como un solo cliente |
| 2 | Dynamic IP Restrictions (parte opcional) | Habilitar también la denegación por pedidos concurrentes, con un valor a definir con datos | Cubre ráfagas de muchas conexiones a la vez | No se midió la concurrencia legítima; no proponer un número sin esa medición |
| 3 | IP Address and Domain Restrictions | Una entrada de denegación para `181.116.88.166` | Detiene esa IP de inmediato y se deshace quitando la entrada | Solo cubre esa IP. Verificar antes que no sea una línea propia ni una prueba autorizada |
| 4 | Request Filtering: segmentos ocultos | Agregar `config` a los segmentos ocultos si no tiene contenido que deba servirse | La carpeta responde 404 en lugar de 403, y deja de revelar que existe | No agregar `service` sin revisar: puede ser parte de la aplicación (no se verificó). No reduce la carga |
| 5 | Request Filtering: extensiones de archivo | Denegar extensiones que el sitio no debe servir (por ejemplo `.bak`, `.zip`), después de confirmar que la aplicación no las usa | Los pedidos de archivos de respaldo reciben un error sin llegar a la aplicación | El barrido pidió `.aspx`, `.asmx`, `.svc`, `.xml`, `.json` y `.txt` también; algunas son extensiones legítimas del servicio y no se pueden denegar |
| 6 | Registro (Logging) | Mantener el campo `sc-substatus` en el log del sitio | Permite ver los pedidos marcados o denegados por la regla (sub-estado 502 para tasa) | Ya aparece en el log; solo hay que no quitarlo |
| 7 | Nivel de aplicación de la configuración | Hoy la regla está a nivel de servidor; decidir si queda así o se baja al sitio | Un cambio de servidor alcanza a todos los sitios de ese host | En esos hosts hay un sitio conocido (`W3SVC2`); si hubiera otros, la regla los alcanza |

## Recomendación
1. **Aplicar 1 en `SFCG-WEBS-01` primero**, con un lote chico de prueba para verificar que se marca y se deniega, y replicarlo en `SFCG-WEBS-02` y `SFCG-WEBS-03` después de ver el resultado. Es el cambio de mayor efecto con menor riesgo.
2. **Aplicar 3 solo si la verificación del origen lo permite**, como complemento inmediato para esa IP.
3. **Aplicar 4 después de revisar el contenido de `config`**, porque el barrido ya sabe que existe.
4. **Dejar 2 y 5 para cuando haya datos**: concurrencia legítima y extensiones que usa la aplicación.

Por qué la propuesta es de IIS: hoy el tráfico llega por HTTP (puerto 8080) a través del Load Balancer, sin un WAF delante (dato informado por el responsable; el Load Balancer y el puerto figuran en la documentación de infraestructura, la ausencia de WAF no se verificó en la configuración de Azure). Fuera de la configuración de IIS, un bloqueo en el NSG y un WAF delante del Load Balancer quedan como opciones aparte, sin evaluar en esta propuesta.

## Antes de aplicar
- Confirmar que `181.116.88.166` no es una línea de la oficina ni una prueba autorizada (comparar con las IP públicas de los servicios de internet de la oficina).
- Confirmar si el barrido siguió después de las 22:00 (UTC-3).
- Revisar el contenido de `config` y `service` en `C:\SmartFran\SmartLoyalty.WebService\` y si se sirven archivos por nombre.
- Mantener el respaldo `before-gitin2316-dynip`; hacer otro respaldo antes de cada cambio nuevo.

## Verificación después de aplicar
- Para 1: el log de IIS muestra respuestas 403 con sub-estado 502 para la IP que supera el umbral, y ninguna IP legítima las tiene.
- Para 3: el log de IIS no muestra pedidos de la IP.
- Para 4: un pedido a `/config/` desde fuera devuelve 404.
- Para 5: un pedido a un archivo con extensión denegada devuelve el error esperado y los endpoints del servicio siguen respondiendo.
