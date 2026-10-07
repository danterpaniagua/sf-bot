# Eventos — 20260826_wsv2lb_vm2_trustedlaunch_no_traffic

## 2026-08-26 14:00 — Retoma del ticket estancado GITIN-1238

He retomado esta investigación, abierta originalmente sin resolución ni caso de soporte abierto. He confirmado que `SFCG-WSV2-02` sigue existiendo pero está apagada administrativamente — decisión deliberada para no arriesgar el tráfico de producción en `SFCG-WSV2-01` mientras ambas VMs estuvieran activas en el pool.

## 2026-08-26 14:30 — Re-verificación de la configuración del Load Balancer

He confirmado en vivo la configuración de `SFCG-WSV2-LB`: una única regla de entrada, un único probe, y el backend pool con configuración idéntica para ambas VMs — ninguna asimetría en el propio Load Balancer.

## 2026-08-26 18:07 — Falla bloqueante en el application pool de VM2, detectada y resuelta

He encontrado que el application pool de `SmartLoyalty.WebServiceV2` en `SFCG-WSV2-02` estaba detenido por una identidad inválida (Event ID 5021), coincidiendo con una rotación de credenciales reciente. He resuelto este bloqueo puntual antes de poder continuar probando la ruta del Load Balancer.

## 2026-08-26 19:08 — Retractación: el tráfico real nunca llegó a VM2

He verificado la métrica `DipAvailability` por IP de backend y he confirmado que el probe de salud de `SFCG-WSV2-02` estuvo en 0% durante toda la sesión — cada prueba que interpreté como "atendida por VM2" en realidad fue atendida por VM1. He retractado esa conclusión.

## 2026-08-27 10:41 — Recuperación espontánea del probe de VM2

He verificado, con la métrica separada por IP, que el probe de `SFCG-WSV2-02` pasó de 0% a saludable sin intervención directa. He descartado la hipótesis de firewall/perfil de red mal categorizado tras revisar `Get-NetFirewallProfile` en la propia VM.

## 2026-08-27 11:00 — Dos falsos positivos de prueba descartados (bypass local)

He detectado que varias pruebas que parecían confirmar tráfico real a través del Load Balancer en realidad se ejecutaron desde las propias VMs, resueltas localmente vía una entrada en el archivo hosts — no pasaron por el Load Balancer en ningún momento.

## 2026-08-27 11:25 — Síntoma original reproducido desde un cliente externo real

He ejecutado conexiones nuevas desde una máquina externa genuina contra la IP pública del Load Balancer: de 11 intentos, 9 fueron atendidos por `SFCG-WSV2-01` y 2 fallaron con timeout de conexión sin respuesta — exactamente el síntoma original reportado, ahora sin ninguna de las confusiones metodológicas previas.

## 2026-08-27 11:37 — Causa raíz encontrada: regla de NSG sin la IP de VM2

He confirmado, vía `test-ip-flow` del plano de control de Azure, que el flujo real hacia `SFCG-WSV2-02` es denegado por la regla por defecto (`DenyAllInBound`). He identificado la regla `WebService_V2_PRO` del NSG `sfcgnetsec01` como la causa: su lista fija de IPs de destino nunca incluyó `192.168.50.172`.

## 2026-08-27 11:41 — Corrección aplicada

He agregado `192.168.50.172` a la lista de destinos de la regla `WebService_V2_PRO`. He confirmado el cambio con una nueva consulta a `test-ip-flow`, que ahora devuelve `Allow`.

## 2026-08-27 12:00 — Prueba aislada construida para eliminar toda ambigüedad

He creado una regla y un pool temporales en el Load Balancer conteniendo únicamente la NIC de `SFCG-WSV2-02`, para probar el tráfico real sin ninguna posibilidad de que la respuesta provenga de VM1. He confirmado una respuesta exitosa completa a través de esa ruta aislada.

## 2026-08-27 12:25 — Lectura obsoleta de logs corregida; tráfico real de producción confirmado en VM2

He detectado que una lectura previa del log de IIS de `SFCG-WSV2-02` estaba obsoleta (problema de caché de disco de Azure, no del estado real del archivo). Al releer, he confirmado tráfico real de clientes ya distribuyéndose correctamente hacia ambas VMs, incluyendo tráfico genuino de POS de producción. He dado por resuelta la investigación de red.

## 2026-08-27 12:38 — Recursos de la prueba aislada eliminados; estado final del pool confirmado

He eliminado la regla y el pool temporales del Load Balancer, y he confirmado que `SFCG-WSV2-02` quedó reincorporada al pool de producción `SFCG-WSV2-LB-backendpool01`.

## 2026-08-27 12:41 — Cambio de probe de salud intentado y revertido

He intentado reemplazar el probe TCP simple por uno HTTPS contra `/healthcheck.ashx`. El nuevo probe hizo caer la disponibilidad de `SFCG-WSV2-02` a 0% en pocos minutos. He revertido de inmediato al probe original; he confirmado la recuperación completa de VM2 en los minutos siguientes. He dejado esta mejora pendiente para un intento futuro más cuidadoso, con los bindings de sitio IIS revisados de antemano.

## 2026-08-27 13:00 — Monitoreo de Zabbix clonado de VM1 hacia VM2

He clonado el host de Zabbix de `SFCG-WSV2-01` hacia `SFCG-WSV2-02` (mismas plantillas y macros) y he confirmado la llegada de datos reales y actuales. Dado que `SFCG-WSV2-02` no permanece encendida las 24 horas, he creado una ventana de mantenimiento diaria (00:00–09:00 UTC-3) para evitar falsas alarmas por su apagado programado, sin modificar ningún disparador existente.

## 2026-08-27 13:15 — Incorporación de SFCG-WSV2-02 cerrada

He dado por completa la incorporación de `SFCG-WSV2-02`: causa raíz de red corregida y verificada de punta a punta, monitoreo de Zabbix en paridad con VM1. Quedan pendientes, fuera de este ticket: confirmar el propósito de la IP `192.168.50.174` agregada en la misma edición de NSG, y migrar el despliegue de la aplicación fuera del disco temporal de `SFCG-WSV2-02`.
