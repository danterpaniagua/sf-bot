# 02-09-2026_error-message-alerting

**Tags:** SmartPedidos, AWS, DEPLOY, Lambda

## Resumen

Se construyó y desplegó alertamiento de fallos para dos Lambdas del pipeline GITIN-1872 (`grido-redacted-etl`, GITIN-1874; `mongo-to-s3-CFN-ScheduledMongoToS3-1EZXBGD94CJVO`, GITIN-1970): una `CloudWatch Alarm` por función sobre la métrica `Errors`, publicando al tópico SNS existente `SNS-SmartPedidosTeam-PROD` (elegido frente a `Alertas-EventBridge-PROD` tras comparar sus suscriptores reales), más un nuevo Lambda Python (`sp-pipeline-alerts-chat-bridge`) que reenvía cada alerta a dos espacios de Google Chat (Operations y SmartPedidos) vía webhooks entrantes. Validado extremo a extremo forzando una alarma real.

## Tabla resumen

| Campo | Valor |
|---|---|
| Ticket Jira | [GITIN-1979](https://smartit-ar.atlassian.net/browse/GITIN-1979) |
| ID alerta | — (construcción de infraestructura, no incidente) |
| Sistema | `sp-pipeline-alerts-chat-bridge`, alarmas `grido-redacted-etl-errors` / `mongo-to-s3-scheduled-errors` |
| Severidad | — |
| Detectado | — (no aplica) |
| Resuelto | 2026-09-03 — desplegado y validado extremo a extremo con una alarma real; canal de Google Chat desactivado el mismo día por exceso de verbosidad, queda solo alertamiento por email |
| Responsable | Dante Paniagua, SRE |

## Causa raíz

No aplica en sentido de incidente — este es un desarrollo nuevo, no una remediación.

## Hallazgos

| # | Hallazgo | Riesgo |
|---|---|---|
| H1 | Supuesto inicial incorrecto: se asumió que las seis reglas de EventBridge "-Team" existentes compartían un único tópico SNS por convención de nombre. Verificado directamente que en realidad son dos tópicos distintos (`Alertas-EventBridge-PROD` y `SNS-SmartPedidosTeam-PROD`) — el mismo patrón de error de "evidencia convergente con supuesto compartido" identificado más temprano en la sesión (ver `bots/CLAUDE.md`). | Bajo (corregido antes de decidir) |
| H2 | Comparación de suscriptores reales (`list-subscriptions-by-topic`) determinó `SNS-SmartPedidosTeam-PROD` como el tópico correcto a reutilizar: alcanza la lista de distribución del equipo (`smartpedidos@smartfran.com`) más un individuo, mientras `Alertas-EventBridge-PROD` solo alcanza a un individuo. | — (decisión informada por datos reales) |
| H3 | Error real de despliegue: el primer `create-function` usó el archivo de variables de entorno mientras aún tenía texto de placeholder literal, pese a que el usuario reportó haberlo editado. Detectado revisando la configuración realmente desplegada, no confiando en el reporte. Corregido con `update-function-configuration`. | Medio (corregido antes de que la función se usara en producción) |
| H4 | Configuración de shell (`noclobber`) causó que un primer intento de `create-function` con redirección `>` fallara silenciosamente sin ejecutar el comando — el archivo de salida quedó vacío, inicialmente indistinguible de un comando exitoso sin salida. Resuelto usando `>|` para forzar la sobreescritura. | Bajo (causó confusión, sin impacto de datos) |
| H5 | Revisión de seguridad solicitada por el usuario antes de desplegar: confirmado sin exposición entrante (sin Function URL/API Gateway), permiso de invocación SNS acotado al ARN específico del tópico, rol de ejecución sin acceso a recursos AWS más allá de CloudWatch Logs. Único trade-off aceptado explícitamente: las URLs de webhook (con token embebido) quedan como variables de entorno en texto plano, visibles para cualquiera con `lambda:GetFunctionConfiguration` — mismo patrón ya usado para `MONGO_USER`/`MONGO_PASSWD` en el Lambda fuente. El usuario eligió mantener este patrón en vez de SSM Parameter Store `SecureString`. | Bajo (trade-off aceptado explícitamente, no un hallazgo sin resolver) |

## Recursos afectados

| Componente | Impacto |
|---|---|
| `sp-pipeline-alerts-chat-bridge` (Lambda, nuevo) | Desplegado y activo. `python3.12`, `Timeout=30`, `MemorySize=128`. Suscrito a `SNS-SmartPedidosTeam-PROD`. |
| `sp-pipeline-alerts-chat-bridge-role` (IAM, nuevo) | Rol de ejecución mínimo — solo `AWSLambdaBasicExecutionRole` (CloudWatch Logs), sin acceso a otros recursos AWS. |
| `grido-redacted-etl-errors` / `mongo-to-s3-scheduled-errors` (CloudWatch Alarms, nuevas) | Publican a `SNS-SmartPedidosTeam-PROD` al detectar ≥1 error en 5 minutos en cada función respectivamente. |
| `SNS-SmartPedidosTeam-PROD` (existente) | Ganó una tercera suscripción (Lambda), además de las dos de email ya existentes. No modificado de otra forma. |
| Espacios de Google Chat (Operations, SmartPedidos) | Reciben mensajes automáticos nuevos ante fallos de estas dos funciones. |

## Comandos ejecutados

Detalle completo en `investigation.md`.

| # | Comando / Script | Propósito |
|---|---|---|
| C1 | `aws events list-rules --query "Rules[?EventPattern!=null]"` | Descubrir infraestructura de alertamiento EventBridge existente en la cuenta |
| C2 | `aws events list-targets-by-rule` (las seis reglas "-Team"/ECR) | Determinar los targets reales de cada regla — reveló dos tópicos SNS distintos, no uno |
| C3 | `aws sns list-subscriptions-by-topic` (ambos tópicos) | Comparar suscriptores reales para decidir cuál tópico reutilizar |
| C4 | `aws cloudwatch put-metric-alarm` (x2) | Crear las alarmas de `Errors` para `grido-redacted-etl` y `mongo-to-s3-CFN-ScheduledMongoToS3-1EZXBGD94CJVO` |
| C5 | `aws iam create-role` / `attach-role-policy` | Crear el rol de ejecución del bridge Lambda |
| C6 | `aws lambda create-function` / `update-function-configuration` | Desplegar `sp-pipeline-alerts-chat-bridge`, corregir el error de placeholder (H3) |
| C7 | `handler.py` `test_local.py` (ejecución local) | Validar el formateo de mensaje contra ambos formatos (alarma CloudWatch, texto plano) sin llamar webhooks reales |
| C8 | `aws lambda invoke` (payload de prueba sintético) | Validar el bridge end-to-end vía invocación directa — confirmado por el usuario en ambos espacios de Chat |
| C9 | `aws lambda add-permission` + `aws sns subscribe` | Conectar el bridge al tópico SNS real |
| C10 | `aws cloudwatch set-alarm-state` (ALARM, luego OK) | Prueba real forzando una transición de alarma — confirmó el camino de producción completo (Alarma → SNS → Lambda → Chat/email) |
| C11 | `aws sns unsubscribe` + `list-subscriptions-by-topic` | Desactivar el canal de Google Chat (exceso de verbosidad) manteniendo solo email — confirmado el tópico con únicamente las dos suscripciones de email (`data/sns_subscriptions_after_gchat_disable.json`) |

## Acciones propuestas

1. **(SRE)** Leer el cuerpo/comentarios reales del ticket GITIN-1979 en Jira — el alcance de este trabajo fue inferido de la conversación, nunca confirmado contra el ticket en sí.
2. **(SRE)** Eliminar `~/tmp-sp-alerts/environment.json` (fuera del repo) si aún no se hizo — contenía las URLs reales de webhook en texto plano.
3. **(Dev/SRE)** Evaluar si otros componentes del pipeline GITIN-1872 (más allá de estos dos Lambdas) necesitan el mismo alertamiento (por email, dado que Google Chat quedó desactivado).
4. **(SRE)** Si se decide reactivar Google Chat más adelante con un formato menos verboso, la infraestructura ya existe — solo requiere `aws sns subscribe` nuevamente (`sp-pipeline-alerts-chat-bridge` y su rol IAM no fueron eliminados).
5. **(SRE)** Si la postura de seguridad de la cuenta cambia, reconsiderar migrar `GOOGLE_CHAT_WEBHOOK_URLS` a SSM Parameter Store `SecureString` — decisión actual de mantener variables de entorno en texto plano fue explícita, no un descuido. Queda sin efecto práctico mientras el bridge esté desuscrito.

## Hallazgos secundarios

Desafíos que condicionaron el enfoque de esta tarea, sin ser hallazgos de causa raíz en sí mismos:

- **Identidad de ticket resuelta a mitad de sesión:** este trabajo comenzó como una solicitud ad-hoc dentro de la sesión de GITIN-1874, sin carpeta local propia, hasta que el usuario confirmó la URL de Jira (GITIN-1979) — la investigación inicial se reconstruyó en esta carpeta a partir de la conversación, no fue re-derivada desde cero.
- **El mismo patrón de "evidencia convergente con supuesto compartido" de esta sesión (ver H1) reapareció en un contexto completamente distinto** (infraestructura de alertamiento en vez de formato de archivos) — refuerza que es un patrón general de error a vigilar, no específico de un solo problema.
- **Broadcast a más de un equipo fue un requisito real, no anticipado en el diseño inicial:** el bridge se diseñó primero para un solo webhook, y se refactorizó a una lista separada por comas (`GOOGLE_CHAT_WEBHOOK_URLS`) cuando el usuario aclaró que Operations y SmartPedidos necesitaban recibir las alertas por separado.
