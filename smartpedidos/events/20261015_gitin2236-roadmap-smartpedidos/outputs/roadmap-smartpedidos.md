# Roadmap SmartPedidos — Operaciones / SRE (borrador)

Borrador para [GITIN-2236](https://smartit-ar.atlassian.net/browse/GITIN-2236). Cada fila es una Story con sus tareas. La columna "Tickets existentes" muestra los GITIN que ya cubren el trabajo; donde no hay, dice "No hay ticket aún". La estimación de tiempo (días de trabajo de una persona de SRE) está en la columna "Estimación"; el cálculo y los supuestos están en `tabla-roadmap.md`. "Proyecto" indica a qué proyecto pertenece (Platform, Concentrador o INFRA SRE para trabajo de infraestructura). "¿Requiere DEV?" indica si la tarea necesita al equipo de desarrollo; en las tareas de logs, si no se modifica código de negocio se puede hacer sin Dev. La prioridad es una propuesta de Operaciones según criticidad y esfuerzo, para revisar.

**Aviso sobre las estimaciones:** los tiempos se tomaron de proyectos anteriores de Operaciones y de la experiencia en tareas similares, y son rangos de trabajo de una persona de SRE, no fechas de entrega. Las alertas y tareas del día a día interrumpen el trabajo planificado y lo pausan, por lo que los plazos reales pueden ser mayores. El tiempo de Dev no está incluido donde se indica.

## Por qué hace falta identificar la deuda técnica

La deuda técnica es trabajo que hoy no se ve en ningún tablero pero que ya produce efectos: cambios más riesgosos, errores sin rastro en los logs, accesos y credenciales difíciles de controlar y alertas que llegan tarde o no llegan. Registrarla con un dueño, una criticidad y un esfuerzo permite decidir qué se hace primero en lugar de descubrirla durante un incidente.

## Resumen

| # | Story | Proyecto | Tickets existentes | ¿Requiere DEV? | Prioridad OPE (criticidad / esfuerzo) | Estimación |
|---|---|---|---|---|---|---|
| 1 | Mejoras de despliegue | INFRA SRE | [GITIN-2169](https://smartit-ar.atlassian.net/browse/GITIN-2169) | Parcial | Alta / Alta | SRE: 13–25 días, sin la tarea del escenario web de Zabbix (a estimar); Dev a estimar |
| 2 | AWS WAF | INFRA SRE | No hay ticket aún | No (validación con Dev) | Alta / Media | SRE: 7–13 días; Dev a estimar |
| 3 | Credenciales en código | INFRA SRE + Platform + Concentrador | [GITIN-2129](https://smartit-ar.atlassian.net/browse/GITIN-2129), [GITIN-1606](https://smartit-ar.atlassian.net/browse/GITIN-1606) | Sí | Alta / Alta | SRE: 13–25 días; Dev a estimar |
| 4 | Escalado con múltiples umbrales para Platform | INFRA SRE (Platform) | [GITIN-2170](https://smartit-ar.atlassian.net/browse/GITIN-2170) (relacionados: [GITIN-2110](https://smartit-ar.atlassian.net/browse/GITIN-2110), [GITIN-2162](https://smartit-ar.atlassian.net/browse/GITIN-2162)) | No | Alta / Media | SRE: 7–13 días |
| 5 | Revisión de logs | Platform + Concentrador | [GITIN-1477](https://smartit-ar.atlassian.net/browse/GITIN-1477), [GITIN-2222](https://smartit-ar.atlassian.net/browse/GITIN-2222), [GITIN-2229](https://smartit-ar.atlassian.net/browse/GITIN-2229) | Depende: si no se modifica código de negocio, se puede hacer sin Dev | Alta / Baja | SRE: 4–8 días; Dev a estimar si se toca código de negocio |
| 6 | Contratos SP–SRE (logs y consultas a Mongo) | INFRA SRE | No hay ticket aún | Parcial | Media / Media | SRE: 6–11 días; Dev a estimar |
| 7 | Nuevas alertas en Zabbix | INFRA SRE | [GITIN-2229](https://smartit-ar.atlassian.net/browse/GITIN-2229), [GITIN-2171](https://smartit-ar.atlassian.net/browse/GITIN-2171) | No | Media / Baja | SRE: 3–6 días |
| 8 | Graylog en los ambientes DEV | INFRA SRE | No hay ticket aún | Parcial | Baja / Media | SRE: 5–10 días; Dev a estimar |
| 9 | Refactor del controlador de sucursales de Concentrador | Concentrador | No hay ticket aún | Sí | Media / Alta | SRE: 3–6 días de validación; Dev a estimar |
| 10 | Fallas silenciosas en el cron de pedidos rechazados | Concentrador | No hay ticket aún | Depende: si no se modifica código de negocio, se puede hacer sin Dev | Alta / Baja | SRE: 4–8 días; Dev a estimar si se toca código de negocio |
| 11 | Deuda de logging en Platform | Platform | No hay ticket aún | Depende: si no se modifica código de negocio, se puede hacer sin Dev | Baja a media / Media | SRE: 5–11 días; Dev a estimar si se toca código de negocio |
| 12 | Gestión de la deuda técnica | Platform + Concentrador | No hay ticket aún | No | Media / Baja | SRE: 3–6 días |

## Detalle por Story

### 1. Mejoras de despliegue

- **Por qué es necesario:** hoy los desarrolladores comparten credenciales genéricas y pueden desplegar desde sus máquinas; separar roles por ambiente reduce el riesgo de un cambio accidental en producción.
- **Objetivo:** que sea transparente para los desarrolladores, con un rol por ambiente y, una vez automatizado el despliegue, sin deploy a PROD desde máquinas personales.
- **Comentarios:** los usuarios trabajan en Windows, por lo que el entorno local y el README deben contemplarlo.
- **Escenario web de Zabbix:** en la lista de escenarios web de Zabbix leída el 2026-10-19 (16 escenarios) no hay ninguno de SmartPedidos; SmartLoyalty sí tiene. Un escenario web pide, después de cada despliegue y cada minuto, las direcciones que se le indiquen y falla si la respuesta no es la esperada, de modo que la persona que despliega puede confirmar el resultado en Zabbix. Qué direcciones y qué respuesta confirman que el despliegue quedó bien lo define Desarrollo junto con SRE; los escenarios de SmartLoyalty solo comprueban en su mayoría el código 200 y no validan el certificado, por lo que conviene decidir qué se espera de este.

| Tarea | Proyecto | Ticket existente | ¿Requiere DEV? |
|---|---|---|---|
| Pasar de credenciales genéricas a credenciales por usuario | INFRA SRE | [GITIN-2169](https://smartit-ar.atlassian.net/browse/GITIN-2169) | Parcial: SRE configura los accesos; los desarrolladores actualizan su entorno local |
| Definir y ordenar los ambientes | INFRA SRE | No hay ticket aún | Parcial |
| Docker | Platform + Concentrador | No hay ticket aún | Sí (archivos en los repositorios) |
| README para levantar el ambiente local | Platform + Concentrador | No hay ticket aún | Sí |
| Un rol por ambiente | INFRA SRE | No hay ticket aún | No |
| Automatizar el despliegue y quitar el deploy a PROD desde máquinas personales | INFRA SRE | No hay ticket aún | Parcial: SRE arma la automatización; Dev adapta su flujo |
| Escenario web de Zabbix que verifique cada despliegue (agregada el 2026-10-19) | INFRA SRE | No hay ticket aún | Parcial: SRE crea el escenario; Dev indica las direcciones y la respuesta que confirma que el despliegue quedó bien |

### 2. AWS WAF

- **Por qué es necesario:** hay accesos no autorizados que hoy no se bloquean; las reglas del WAF permiten filtrarlos antes de que lleguen a las aplicaciones.
- **Comentarios:** el reto es que todo siga funcionando como hoy; por eso se reúnen primero los datos de los últimos meses.

| Tarea | Proyecto | Ticket existente | ¿Requiere DEV? |
|---|---|---|---|
| Reunir los datos de accesos no autorizados de los últimos meses | INFRA SRE | No hay ticket aún | No |
| Definir las reglas | INFRA SRE | No hay ticket aún | No |
| Habilitar las reglas, por etapas (propuesta) | INFRA SRE | No hay ticket aún | No |
| Verificar que el tráfico legítimo no se vea afectado | INFRA SRE | No hay ticket aún | Parcial: validación con Dev |

### 3. Credenciales en código

- **Por qué es necesario:** hay credenciales en archivos de entorno; sacarlas del código y rotarlas reduce el impacto de una filtración.
- **Objetivo:** que sea transparente para los desarrolladores, con acceso a las credenciales según su rol, y reforzar la seguridad.
- **Comentarios:** la rotación de las claves de sal debe probarse y monitorearse a fondo; después de cambiar credenciales hacen falta pruebas extensas.

| Tarea | Proyecto | Ticket existente | ¿Requiere DEV? |
|---|---|---|---|
| Migrar las credenciales de los archivos de entorno a un servicio de AWS | Platform + Concentrador | [GITIN-2129](https://smartit-ar.atlassian.net/browse/GITIN-2129), [GITIN-1606](https://smartit-ar.atlassian.net/browse/GITIN-1606) | Sí (el código debe leerlas del nuevo servicio) |
| Rotación inicial de credenciales | INFRA SRE | No hay ticket aún | Parcial: reinicio y pruebas con Dev |
| Rotación automática de las claves de sal | Platform + Concentrador | No hay ticket aún | Sí |
| Honeypot con credenciales en los archivos | INFRA SRE | No hay ticket aún | Parcial |
| Pruebas posteriores a los cambios | Platform + Concentrador | No hay ticket aún | Sí |

### 4. Escalado con múltiples umbrales para Platform

- **Por qué es necesario:** hoy una función automática escala en un único nivel; con varios umbrales Platform puede ajustar su capacidad de forma más gradual ante la demanda.

| Tarea | Proyecto | Ticket existente | ¿Requiere DEV? |
|---|---|---|---|
| Analizar el comportamiento actual del escalado | INFRA SRE (Platform) | [GITIN-2170](https://smartit-ar.atlassian.net/browse/GITIN-2170) (relacionados: [GITIN-2110](https://smartit-ar.atlassian.net/browse/GITIN-2110), [GITIN-2162](https://smartit-ar.atlassian.net/browse/GITIN-2162)) | No |
| Diseñar los umbrales | INFRA SRE (Platform) | No hay ticket aún | No |
| Implementar los umbrales | INFRA SRE (Platform) | No hay ticket aún | No |
| Probar y monitorear | INFRA SRE (Platform) | No hay ticket aún | No |

### 5. Revisión de logs

- **Por qué es necesario:** sin líneas FATAL ni un registro confiable de los errores, un reinicio o una caída no deja rastro suficiente para alertar ni para analizar la causa.
- **Comentarios:** Platform ya registra FATAL; Concentrador no. En [GITIN-2222](https://smartit-ar.atlassian.net/browse/GITIN-2222) se encontraron además defectos en el propio código de registro. Si el cambio no toca código de negocio puede hacerse sin Dev; si hay que editar archivos de negocio (por ejemplo, las llamadas que arman los datos del log dentro de las funciones de cada plataforma), lo hace o lo revisa Desarrollo.

| Tarea | Proyecto | Ticket existente | ¿Requiere DEV? |
|---|---|---|---|
| Registrar FATAL en Concentrador | Concentrador | [GITIN-1477](https://smartit-ar.atlassian.net/browse/GITIN-1477) | Depende: si no se modifica código de negocio, se puede hacer sin Dev |
| Corregir los defectos del código de registro encontrados en [GITIN-2222](https://smartit-ar.atlassian.net/browse/GITIN-2222) | Platform | [GITIN-2222](https://smartit-ar.atlassian.net/browse/GITIN-2222) | Depende: si no se modifica código de negocio, se puede hacer sin Dev |
| Revisar los logs creados hasta hoy | Platform + Concentrador | No hay ticket aún | No |

### 6. Contratos SP–SRE

- **Por qué es necesario:** acordar qué debe contener un log y cómo se hacen las consultas a la base permite alertar y revisar sin depender de cada caso.

| Tarea | Proyecto | Ticket existente | ¿Requiere DEV? |
|---|---|---|---|
| Contrato de logs | INFRA SRE | No hay ticket aún | Parcial: SRE redacta; Dev revisa y aplica |
| Contrato de consultas a Mongo | INFRA SRE | No hay ticket aún (relacionados: [GITIN-2013](https://smartit-ar.atlassian.net/browse/GITIN-2013), [GITIN-2006](https://smartit-ar.atlassian.net/browse/GITIN-2006)) | Parcial: SRE redacta; Dev revisa y aplica |

### 7. Nuevas alertas en Zabbix

- **Por qué es necesario:** las alertas actuales se basan en promedios y no siempre muestran el error; las que salen de los logs avisan en el momento y con el texto.
- **Comentarios:** la alerta de FATAL de Platform ya está creada; falta confirmar la entrega de un aviso real al Chat de Operaciones.

| Tarea | Proyecto | Ticket existente | ¿Requiere DEV? |
|---|---|---|---|
| Alerta de FATAL de Platform | INFRA SRE | [GITIN-2229](https://smartit-ar.atlassian.net/browse/GITIN-2229) | No |
| Revisar Graylog y analizar nuevas alertas | INFRA SRE | No hay ticket aún | No |
| Alerta de FATAL de Concentrador, cuando registre FATAL | INFRA SRE | No hay ticket aún | No (depende de que Concentrador registre FATAL) |
| Agregar Lambdas al esquema de monitoreo | INFRA SRE | [GITIN-2171](https://smartit-ar.atlassian.net/browse/GITIN-2171) | No |

### 8. Graylog en los ambientes DEV

- **Por qué es necesario:** ver los logs en DEV permite detectar errores de registro antes de llegar a producción.

| Tarea | Proyecto | Ticket existente | ¿Requiere DEV? |
|---|---|---|---|
| Definir el alcance y habilitar Graylog en DEV | INFRA SRE | No hay ticket aún | Parcial: SRE habilita; Dev configura sus ambientes |

### 9. Refactor del controlador de sucursales de Concentrador

- **Por qué es necesario:** un solo controlador de unas 4.200 líneas concentra varias responsabilidades y variantes copiadas por plataforma; cada cambio es más riesgoso y bloquea mejoras de logging.
- **Comentarios:** verificado en la rama principal de Concentrador (develop) el 2026-10-15: el controlador sigue siendo grande (el registro de junio hablaba de 5.571 líneas) y sigue habiendo funciones de cierre de sucursal copiadas para cinco plataformas. Las funciones de chequeo y envío de estado por plataforma ya se movieron a otra clase, aunque siguen siendo una variante por plataforma. El código de prueba que quedó en producción sigue ahí.

| Tarea | Proyecto | Ticket existente | ¿Requiere DEV? |
|---|---|---|---|
| Separar las responsabilidades del controlador | Concentrador | No hay ticket aún | Sí |
| Eliminar el código de prueba que quedó en producción | Concentrador | No hay ticket aún | Sí |
| Unificar las funciones de cierre de sucursal copiadas por plataforma (y las variantes por plataforma de la clase de estado) | Concentrador | No hay ticket aún | Sí |
| Sacar el registro de errores en línea (88 puntos de llamada; depende de la separación) | Concentrador | No hay ticket aún | Sí |

### 10. Fallas silenciosas en el cron de pedidos rechazados

- **Por qué es necesario:** el proceso que rechaza pedidos pendientes, cada 30 segundos, descarta los errores sin dejar rastro, por lo que un pedido puede quedar sin rechazar sin que nadie lo vea.
- **Comentarios:** confirmado en el código de la rama principal de Concentrador (develop) el 2026-10-15: el bloque de captura de errores solo continúa con el siguiente pedido. No se verificó en producción si ocurre.

| Tarea | Proyecto | Ticket existente | ¿Requiere DEV? |
|---|---|---|---|
| Registrar el error con el pedido y contarlo | Concentrador | No hay ticket aún | Depende: si no se modifica código de negocio, se puede hacer sin Dev |
| Crear una alerta | INFRA SRE | No hay ticket aún | No |

### 11. Deuda de logging en Platform

- **Por qué es necesario:** el código repite el cálculo de tiempos en cada plataforma y los mensajes de error llevan el identificador del pedido dentro del texto, lo que dificulta buscar y alertar.
- **Comentarios:** verificado en la rama principal de Platform (develop) el 2026-10-15: ambos problemas siguen. Tampoco existe todavía el interceptor HTTP que usa Concentrador para medir tiempos. El identificador del pedido en las fallas del consumidor de la cola ya se registra, por lo que esa tarea del registro de junio está resuelta.

| Tarea | Proyecto | Ticket existente | ¿Requiere DEV? |
|---|---|---|---|
| Usar un interceptor HTTP para medir tiempos en lugar de repetir el código en cada plataforma | Platform | No hay ticket aún | Depende: si no se modifica código de negocio, se puede hacer sin Dev |
| Pasar los mensajes de error a campos estructurados | Platform | No hay ticket aún | Depende: si no se modifica código de negocio, se puede hacer sin Dev |

### 12. Gestión de la deuda técnica

- **Por qué es necesario:** sin un registro vivo, la deuda se redescubre en cada incidente.

| Tarea | Proyecto | Ticket existente | ¿Requiere DEV? |
|---|---|---|---|
| Mantener el registro al día y asignar identificadores de Jira | Platform + Concentrador | No hay ticket aún | No |
| Registrar lo nuevo de [GITIN-2222](https://smartit-ar.atlassian.net/browse/GITIN-2222) (llamadas incorrectas al sanitizador de headers, serialización de errores, política de los manejadores de proceso en Platform y Concentrador) | Platform + Concentrador | [GITIN-2222](https://smartit-ar.atlassian.net/browse/GITIN-2222) | No |

## Pendiente

- Revisar las estimaciones de tiempo con el PM y con Dev.
- Confirmar la prioridad propuesta.
- Posibles Stories adicionales a evaluar: actualización de dependencias e imágenes ([GITIN-2107](https://smartit-ar.atlassian.net/browse/GITIN-2107)), pipeline de calidad (SonarQube y ESLint), rendimiento y tamaño de la base, salud del propio Graylog, respaldos y recuperación ante desastres (sin evidencia en los eventos revisados).
