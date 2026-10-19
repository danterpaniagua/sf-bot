**Asunto:** FWD: Espacio de logs de SmartCloud: SmartPedidos reintenta en exceso cuando MercadoPago rechaza un acceso

Hola team,

Sobre la consulta de retención: los índices de logs de SmartCloud se conservan entre 30 y 40 días y esa política no es la causa del problema de espacio. Lo que consume el disco es el volumen: unos 10 GB por día hasta el 6 de octubre (dentro de lo dimensionado en junio) y entre 37 y 52 GB por día del 8 al 12 de octubre (estimación según el tamaño de los índices).

**Detección.** La alerta de Zabbix por poco espacio en disco dio origen a la investigación y permitió ubicar el origen: el servicio Business y, dentro de él, las consultas de credenciales de billetera, que se repiten cuando MercadoPago rechaza un acceso y SmartPedidos reintenta sin pausa. Como complemento se podría agregar una alerta por ritmo de ingreso de cada conjunto de índices (idea, todavía no decidida).

**Trabajo realizado.** El 9 de octubre se amplió el disco a 768 GB (el almacenamiento es barato: del orden de USD 135 por mes por 1 TB, según la estimación de junio) y el 14 de octubre se desplegó el cambio para que SmartPedidos deje de reintentar de inmediato ([GITIN-2220](https://smartit-ar.atlassian.net/browse/GITIN-2220)). Falta medir cuánto baja el volumen en los próximos días, y todavía no está confirmado que estos reintentos expliquen todo el aumento (Orders también subió desde el 7 de octubre).

Seguimiento: [GITIN-2209](https://smartit-ar.atlassian.net/browse/GITIN-2209).

Saludos,
Dante
