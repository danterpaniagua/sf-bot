**Asunto:** FWD: Espacio de logs de SmartCloud: SmartPedidos reintenta en exceso cuando MercadoPago rechaza un acceso

Hola team,

Reenvío este mensaje para responder la consulta sobre la política de retención de Graylog.

Los índices de logs de SmartCloud se conservan entre 30 y 40 días, y la retención no es la causa del problema de espacio: lo que consume el disco es el volumen que ingresa, no el tiempo que se guarda. Según el tamaño de los índices (estimación sobre el tamaño almacenado), la aplicación generó unos 10 GB de logs por día hasta el 6 de octubre y entre 37 y 52 GB por día del 8 al 12 de octubre (Business, unos 30 GB por día en el pico), por lo que achicar la retención solo postergaría el problema sin corregirlo. El almacenamiento se dimensionó en junio para unos 37 millones de registros por día con 30 días de retención (del orden de 13 a 16 GB por día, según el cálculo del proyecto); hasta el 6 de octubre el volumen estaba dentro de ese margen y el exceso comenzó el 7 de octubre. Hoy los índices ocupan unos 571 GB; el servicio Business concentra 217 GB (38 %) y Orders 111 GB (19 %).

Los datos medidos apuntan a un bucle de reintentos: cuando MercadoPago rechaza un acceso, SmartPedidos vuelve a consultar el token de forma repetida y cada intento deja varias líneas en SmartCloud. Los GET del servicio Business pasaron de unos 4.000 por día (5 al 7 de octubre) a más de 1,4 millones por día (10 al 12 de octubre), y la ruta de credenciales de billetera explica entre el 75 % y el 91 % de ese volumen. En los logs de SmartPedidos se midieron unas 16 consultas por segundo a esa ruta, con el 98 % respondiendo sin contenido (204). Otros servicios también aportan: Orders ocupa el 19 % del total almacenado y su ritmo también subió desde el 7 de octubre (de unos 3 a unos 6 a 8 GB por día; no se determinó la causa); en una muestra de una hora, el 93 % de sus líneas eran peticiones de latido.

El cambio para que SmartPedidos deje de reintentar de inmediato ([GITIN-2220](https://smartit-ar.atlassian.net/browse/GITIN-2220)) se desplegó en SmartPedidos el 14 de octubre. El ritmo ya bajó desde el pico (el índice actual de Business, abierto el 12 de octubre, promedia unos 15 GB por día), en buena parte antes del despliegue, aunque con estos datos no se puede precisar el día; falta medir el efecto del cambio con los días siguientes y todavía no está confirmado que esos reintentos expliquen todo el volumen; el seguimiento del espacio de Graylog está en [GITIN-2209](https://smartit-ar.atlassian.net/browse/GITIN-2209). El 9 de octubre se amplió el disco a 768 GB, de modo que hay margen mientras se mide el efecto del cambio. Ampliar el almacenamiento es barato (según la estimación de junio, un disco de 1 TB cuesta del orden de USD 135 por mes) y lo usamos como margen mientras se corrige la causa, pero no resuelve el origen del volumen.

La alerta de Zabbix por poco espacio en disco fue la que dio origen a la investigación y permitió, además de actuar sobre Graylog, ubicar el origen del aumento (el servicio Business y, dentro de él, las consultas de credenciales de billetera). Como complemento, se podría agregar una alerta por ritmo de ingreso de cada conjunto de índices: según el tamaño de los índices (estimación), el aumento ya era visible desde el 7 de octubre. Es una idea, todavía no decidida.

Quedo atento a cualquier consulta.

Saludos,
Dante
