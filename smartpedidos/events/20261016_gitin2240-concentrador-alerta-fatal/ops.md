# GITIN-2240 — [SP] Concentrador: Alerta FATAL Zabbix

**Tags:** `SmartPedidos`, `Concentrador`, `Obserbavilidad`, `SRE`, `PROD`

## Qué pasó

- Subtarea de [GITIN-2222](https://smartit-ar.atlassian.net/browse/GITIN-2222). Para platform-service ya existe una alerta de Zabbix basada en los mensajes FATAL de Graylog ([GITIN-2229](https://smartit-ar.atlassian.net/browse/GITIN-2229)); se pidió la misma alerta para concentrador-service.
- En Graylog hubo 223 líneas FATAL en 7 días y todas son de platform-service; ninguna es de concentrador-service.
- Hoy no existe una alerta en Zabbix basada en mensajes FATAL de concentrador-service.

## Resumen

Se creó en Zabbix la misma regla que para Platform, aplicada a concentrador-service: un item que consulta cada minuto la cantidad de líneas FATAL de los últimos 5 minutos, un trigger de severidad alta que se abre cuando hay al menos una, y un trigger de severidad media que avisa si el item deja de recibir datos (Graylog inaccesible, token inválido o consulta con error). El item se lee sin errores y devuelve 0, que coincide con la consulta directa a Graylog (0 resultados en 5 minutos y en 7 días). concentrador-service no registra mensajes FATAL, por lo que el trigger de severidad alta no puede abrirse hasta que Desarrollo agregue ese registro.

## Tabla resumen

| Campo | Valor |
|---|---|
| Ticket Jira | [GITIN-2240](https://smartit-ar.atlassian.net/browse/GITIN-2240) (subtarea de [GITIN-2222](https://smartit-ar.atlassian.net/browse/GITIN-2222)) |
| ID alerta | NA |
| Sistema | Zabbix (host `Zabbix server`), Graylog de SmartPedidos, concentrador-service |
| Severidad | Alta (trigger FATAL) y Media (sin datos) |
| Detectado | 2026-10-16 |
| Resuelto | Parcial: alerta creada y leída sin errores; no puede abrirse hasta que concentrador-service registre FATAL (Desarrollo) |
| Responsable | SRE (alerta), Dev (registro FATAL) |

## Causa raíz

NA

## Hallazgos

| # | Hallazgo | Riesgo |
|---|---|---|
| H1 | concentrador-service no registra mensajes FATAL. En `api/src/index.js` (líneas 46 a 55, rama `develop`, commit `01494650`) el manejador de rechazos no manejados crea un error que se registra como `[INFRA/ERROR] custom_error` (nivel ERROR), y el manejador de excepciones no capturadas está registrado con el nombre `'uncaughtException:'` (con dos puntos al final), por lo que Node nunca lo ejecuta. No se encontró ninguna llamada de log `[INFRA/FATAL]` en `api/src`. | Medio |
| H2 | El registrador de concentrador-service ya admite el nivel FATAL y escribe una línea JSON por la salida estándar con el nombre del servicio tomado de la variable `SERVICE_NAME`, que vale `concentrador-service` en la definición de contenedor de producción. Por eso el cambio de Desarrollo es pequeño: llamar al registrador con nivel FATAL en los manejadores. | Bajo |
| H3 | El registro por salida estándar se activa o desactiva en ejecución con un documento de configuración que el servicio lee cada 30 segundos; su valor actual no se leyó. concentrador-service ya envía muchos mensajes a Graylog, por lo que probablemente está activado. | Bajo |
| H4 | La consulta elegida es `msg_level:FATAL AND msg_service:"concentrador-service"`, con los mismos campos que usa la alerta de Platform. Que una línea FATAL futura de concentrador-service lleve esos valores es un supuesto tomado del esquema de Platform y del registrador; se comprobará cuando Desarrollo la publique. | Medio |

/

## Recursos afectados

| Componente | Estado |
|---|---|
| Zabbix, host `Zabbix server` | Macro, item y dos triggers creados |
| concentrador-service | Sin cambios; no registra FATAL |

## Acciones propuestas

| # | Responsable | Acción | Estado |
|---|---|---|---|
| 1 | Dev | Registrar una línea `[INFRA/FATAL]` en los manejadores de proceso de concentrador-service con el mismo esquema que Platform (`msg_level=FATAL`, `msg_category=INFRA`, `msg_service=concentrador-service`) y corregir el nombre del evento `'uncaughtException:'`. Si el proceso debe además terminar es decisión de Desarrollo. Relacionado con [GITIN-1477](https://smartit-ar.atlassian.net/browse/GITIN-1477). | Pendiente |
| 2 | SRE | Cuando Desarrollo publique el cambio, comprobar con un evento real o con una prueba controlada que la línea FATAL coincide con la consulta y que el trigger se abre y notifica al Chat de Operaciones. | Pendiente |
