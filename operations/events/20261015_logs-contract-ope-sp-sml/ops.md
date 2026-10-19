# Propuesta — Contrato de logs entre Operaciones, SmartPedidos y SmartLoyalty

**Tags:** `Operaciones`, `Obserbavilidad`, `SRE`

## Qué pasó

- Al investigar los reinicios de tareas de platform-service (GITIN-2222) y crear la alerta de Zabbix sobre mensajes FATAL (GITIN-2229), Operaciones encontró que los logs de las aplicaciones no siempre traen lo necesario para observar y alertar:
  - El servicio se identifica con dos campos distintos (`ServiceName` y `msg_service`) y el nivel de la aplicación está en `msg_level`, no en el `level` de Graylog.
  - platform-service termina el proceso tras registrar una línea FATAL; concentrador-service no registra ninguna línea FATAL ante un rechazo no manejado.
  - Parte de los rechazos que terminan el proceso los provoca el propio código de registro (error al serializar objetos con referencias circulares y llamadas incorrectas al sanitizador de headers).
  - Las líneas no indican la versión o imagen que las emitió.
- Los logs de SmartLoyalty (.NET) se generan con una biblioteca propia, sin nivel Fatal, y llegan a Graylog por otro camino (archivos CSV y registros de IIS enviados con NXLog), con mensajes sin el formato de SmartPedidos.
- Ya existe un conjunto de 19 axiomas de logging (proyecto `sp-logs`) que cubre gran parte de estas reglas desde el lado del código; no cubre los puntos anteriores ni cómo Operaciones verifica el cumplimiento en Graylog.
- Por eso se propone un contrato entre Operaciones y los equipos de SmartPedidos y SmartLoyalty: los axiomas como base y un anexo de Operaciones con lo que debe llegar al almacén central de logs.
