Asunto: Mejora de observabilidad — MobileAppService y WebServiceV2

Hola equipo,

Les cuento sobre una mejora de observabilidad que ya está aplicada en producción: los Load Balancers de MobileAppService (GITIN-1228) y WebServiceV2 (GITIN-2058) ahora tienen visibilidad real sobre el estado de la aplicación en cada servidor, no solo si el puerto está abierto.

**Qué agregamos**

Hasta ahora, el health check de ambos Load Balancers era un simple chequeo de puerto TCP — no había forma de saber si un servidor estaba realmente saludable (CPU, memoria, conexión a base de datos) o simplemente tenía el puerto escuchando. Reemplazamos eso por un endpoint HTTP (`healthcheck.ashx`) que reporta CPU, RAM, cola de requests, y conectividad real a base de datos (y a Redis en el caso de WebServiceV2) en cada servidor.

Esto conecta directamente con el monitoreo que ya tenemos en Zabbix:

- **Mobile**: http://sf-monitoreo.smartfran.com:8080/httpdetails.php?httptestid=2
- **WebServiceV2**: http://sf-monitoreo.smartfran.com:8080/httpdetails.php?httptestid=17

- **MobileAppService** (`SFCG-MOBI-LB`): probe migrado de TCP puerto 8043 a HTTP puerto 8080.
- **WebServiceV2** (`SFCG-WSV2-LB`): probe migrado de TCP puerto 8080 a HTTP puerto 80 (un probe ya existente en el Load Balancer, antes sin usar).

Ambos cambios están confirmados funcionando — los dos servidores de cada pool muestran estado saludable bajo el nuevo probe. Esta mejora surgió directamente de los hallazgos de GITIN-2053/GITIN-1909, donde un desbalance de tráfico entre servidores pasó desapercibido porque el probe TCP no tenía forma de detectarlo — con esta visibilidad adicional, un problema similar se vería reflejado en el estado de salud reportado, no solo inferido después del hecho.

Vale la pena mencionar que este cambio solo es seguro de implementar gracias a que WebServiceV2 ya cuenta con redundancia real entre sus dos servidores (GITIN-1238, resuelto 2026-08-27) — un health check que puede sacar un servidor de rotación solo tiene sentido si hay otro disponible para absorber el tráfico.

**Algo a tener en cuenta**

Durante las pruebas encontramos que un solo servidor bajo carga completa puede superar el umbral de CPU/RAM del propio handler y reportarse como no saludable — comportamiento seguro solo si el otro servidor está disponible para absorber el tráfico. Si ven algún servidor saliendo de rotación inesperadamente en los próximos días, este es el primer lugar a revisar antes de asumir un problema de infraestructura distinto.

**Importante para el próximo deploy de cualquiera de las dos aplicaciones**

El archivo `healthcheck.ashx` se colocó manualmente en el filesystem de los cuatro servidores (no requiere compilación, IIS lo compila al primer request) — pero **no está agregado al código fuente de ninguna de las dos aplicaciones**. Un deploy estándar probablemente lo elimine al hacer un publish/xcopy limpio, lo que rompería el health check en ambos servidores del pool al mismo tiempo. Si tienen un deploy planeado para MobileAppService o WebServiceV2, avisen antes para coordinar — la solución de fondo es agregar el archivo al proyecto fuente, todavía no hecho.

**Plan de reversión**

Si necesitan volver al comportamiento anterior por cualquier motivo, esto revierte cada Load Balancer a su probe original (TCP, sin verificación de aplicación):

```
+------------------------------------------------------------+
|  STATE-CHANGING COMMAND -- VERIFY TARGET BEFORE RUNNING    |
|  This command modifies, deletes, or writes state.          |
|  Confirm: environment / database / host is the intended one|
|  This action may be IRREVERSIBLE                           |
+------------------------------------------------------------+
```

```bash
# Revertir MobileAppService a su probe TCP original
az network lb rule update \
  --subscription 0190fa7d-4ccf-4e3d-beb1-323b5780bfc8 \
  --resource-group DefaultGroup01 \
  --lb-name SFCG-MOBI-LB \
  --name SFCG-MOBI-LB-lbrule02 \
  --probe-name SFCG-MOBI-LB-probe02

# Revertir WebServiceV2 a su probe TCP original
az network lb rule update \
  --subscription 0190fa7d-4ccf-4e3d-beb1-323b5780bfc8 \
  --resource-group DefaultGroup01 \
  --lb-name SFCG-WSV2-LB \
  --name SFCG-WSV2-LB-lbrule01 \
  --probe-name sfcg-sondeo02
```

Cualquier duda o si ven algo raro en el comportamiento de alguno de los dos pools, avisen y lo revisamos juntos.

Saludos,
Dante
