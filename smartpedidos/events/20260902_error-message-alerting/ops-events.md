# Eventos — 20260902_error-message-alerting

## 2026-09-02 — Identidad de ticket confirmada, carpeta creada

He confirmado que este trabajo corresponde a GITIN-1979, "[SP] Envío de mensaje de error", subtarea de GITIN-1872. He creado esta carpeta y he reconstruido en `investigation.md` la investigación ya realizada durante la sesión antes de que la URL de Jira estuviera confirmada.

## 2026-09-02 — Infraestructura de alertamiento existente descubierta

He listado las reglas de EventBridge con patrón de evento en la cuenta y he identificado seis reglas propias (no de terceros) sobre eventos de ECS, además de un conjunto mayor de reglas `MontyCloud-*` pertenecientes a una herramienta SaaS externa, no relevantes para este trabajo. He pulido el target de `ECS-ServiceAction-Team` y he encontrado un tópico SNS existente, `Alertas-EventBridge-PROD`.

## 2026-09-02 — Corregido un supuesto incorrecto: dos tópicos SNS, no uno

He verificado los targets de las cinco reglas restantes en vez de asumir que todas apuntaban al mismo tópico por convención de nombre. He confirmado que en realidad existen dos tópicos distintos: `Alertas-EventBridge-PROD` (tres reglas) y `SNS-SmartPedidosTeam-PROD` (las otras tres). He comparado sus suscriptores reales vía `list-subscriptions-by-topic`: `SNS-SmartPedidosTeam-PROD` alcanza la lista de distribución del equipo más un individuo, mientras `Alertas-EventBridge-PROD` solo alcanza a un individuo. He decidido reutilizar `SNS-SmartPedidosTeam-PROD`.

## 2026-09-03 — Bridge SNS -> Google Chat construido y validado localmente

He construido `handler.py` en Python, el lenguaje elegido para este bridge, que lee mensajes de SNS y los reenvía a webhooks de Google Chat usando solo la librería estándar (`urllib`). He diseñado el formateo para manejar dos formas de mensaje sin asumir una sola — notificaciones de alarma de CloudWatch (JSON) y mensajes de texto plano como los que ya produce la infraestructura ECS existente. He validado ambos formatos localmente con `test_local.py`, sin llamar webhooks reales.

## 2026-09-03 — Rediseñado para transmitir a más de un equipo

Operations y SmartPedidos necesitan recibir las alertas por separado, no un solo equipo. He refactorizado `handler.py` para leer `GOOGLE_CHAT_WEBHOOK_URLS` como una lista separada por comas y publicar el mismo mensaje a cada URL configurada, con manejo de fallos por webhook independiente (un fallo en un equipo no bloquea la entrega al otro, pero la función igual lanza una excepción al final si alguno falló). He revalidado localmente con dos URLs de prueba.

## 2026-09-03 — Revisión de seguridad realizada antes de desplegar

He confirmado que el diseño no abre exposición entrante (sin Function URL ni API Gateway), que el permiso de invocación SNS quedará acotado al ARN específico del tópico, y que el rol de ejecución no tendrá acceso a ningún recurso AWS más allá de sus propios logs de CloudWatch. He identificado un único trade-off real: las URLs de webhook quedarán como variables de entorno en texto plano, visibles para cualquiera con permiso de lectura de configuración del Lambda — mismo patrón ya usado para las credenciales de MongoDB en el Lambda fuente. El usuario decidió mantener este patrón en vez de migrar a SSM Parameter Store `SecureString`.

## 2026-09-03 — Alarmas de CloudWatch creadas y confirmadas

He creado dos alarmas sobre la métrica `Errors` de `AWS/Lambda` (umbral ≥1 en 5 minutos, `TreatMissingData: notBreaching`), una para `grido-redacted-etl` y otra para `mongo-to-s3-CFN-ScheduledMongoToS3-1EZXBGD94CJVO`, ambas publicando a `SNS-SmartPedidosTeam-PROD`. He confirmado vía `describe-alarms` que ambas quedaron con `ActionsEnabled: true` y `StateValue: OK`. He referenciado esta alarma también en el registro de eventos propio de GITIN-1970, ya que modifica el estado operativo de esa función específica.

## 2026-09-03 — Rol IAM y función desplegados

He creado el rol de ejecución `sp-pipeline-alerts-chat-bridge-role` (solo `AWSLambdaBasicExecutionRole`, sin políticas adicionales) y he desplegado la función `sp-pipeline-alerts-chat-bridge`. He agregado descripciones en español tanto a esta función como a `grido-redacted-etl`.

## 2026-09-03 — Error real de despliegue detectado y corregido

He detectado que el primer `create-function` se ejecutó mientras el archivo de variables de entorno aún tenía texto de placeholder literal, pese a que el usuario había reportado haberlo editado — lo he encontrado revisando la configuración realmente desplegada, no confiando en el reporte. Antes de eso, he identificado que un intento previo de `create-function` había fallado silenciosamente por la opción `noclobber` de la shell del usuario, bloqueando la redirección de salida sin ejecutar el comando en sí — el archivo de salida vacío inicialmente parecía indistinguible de una ejecución exitosa. He corregido ambos problemas: usando `>|` para forzar la sobreescritura, y luego `update-function-configuration` con los valores reales una vez confirmados en el archivo local.

## 2026-09-03 — Validado vía invocación directa, confirmado en ambos espacios de Chat

He invocado la función directamente con un payload sintético con forma de evento SNS, marcado explícitamente como prueba en el texto del mensaje. La ejecución completó sin errores en el log, sin traceback de excepción. El usuario confirmó que el mensaje de prueba llegó correctamente a ambos espacios de Google Chat (Operations y SmartPedidos).

## 2026-09-03 — Conectado al tópico SNS real

He otorgado permiso a `sns.amazonaws.com` para invocar la función, acotado al ARN específico de `SNS-SmartPedidosTeam-PROD`, y he suscrito la función al tópico (protocolo Lambda, confirmación automática). He verificado vía `list-subscriptions-by-topic` que el tópico ahora tiene tres suscripciones: las dos de email ya existentes más esta función.

## 2026-09-03 — Validación end-to-end con una alarma real, confirmada

He forzado la alarma `grido-redacted-etl-errors` a estado `ALARM` vía `set-alarm-state` para probar el camino de producción completo, no solo la invocación directa sintética. El usuario confirmó que la alerta llegó a ambos espacios de Google Chat y a ambos correos del equipo por el camino real (Alarma → SNS → Lambda → Chat/email). He revertido la alarma a `OK` inmediatamente después y confirmado el estado final vía `describe-alarms`. Esto cierra la entrega principal de GITIN-1979 para estos dos Lambdas del pipeline.

## 2026-09-03 — Desactivado el canal de Google Chat por exceso de verbosidad

He desuscrito `sp-pipeline-alerts-chat-bridge` de `SNS-SmartPedidosTeam-PROD` — decisión reversible frente a eliminar la función o el rol, ya que permite reactivar el canal más adelante sin perder la infraestructura construida. He confirmado vía `list-subscriptions-by-topic` que el tópico quedó únicamente con las dos suscripciones de email preexistentes. Las alarmas de CloudWatch no se modificaron y siguen publicando al tópico — solo el canal de Chat dejó de recibir mensajes.
