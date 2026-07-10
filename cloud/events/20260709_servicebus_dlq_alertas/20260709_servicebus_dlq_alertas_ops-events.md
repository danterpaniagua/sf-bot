# Eventos — Configurar alertas DLQ Service Bus Grido PRO

## 2026-07-09 — Apertura

Se ha iniciado la tarea a pedido del equipo de desarrollo. Se ha confirmado que Gastón habría configurado alertas previamente pero el equipo no recibió notificaciones. Se deberá auditar la configuración existente antes de crear o modificar reglas. Destinatarios confirmados: Dante Paniagua, Javier Allende, Javier Picco, Gaspar. Emails de los tres últimos pendientes de confirmar.

## 2026-07-09 — CX-01b/02/03: Auditoría de alert rules y action groups

**Comando:** CX-01b — az monitor metrics alert list / CX-02 — az monitor action-group list / CX-03 — az servicebus queue list
**Resultado:** Se han encontrado 4 alert rules activas (2 sobre DeadletteredMessages, 2 sobre ActiveMessages). Action group `Service_Bus_Group` existe en RG `SmartFran.Cloud.PRO` (distinto al RG del namespace). El namespace usa Topics, no Queues — topic encontrado: `saleclosed`.
**Observación:** Se ha identificado la causa raíz: el action group `Service_Bus_Group` solo tenía configurado `operaciones@smartfran.com` como receptor de email. Gastón solo recibía notificaciones vía Azure App push (`gastona@smartfran.com`), no por email. Por eso el equipo no recibió nada.

## 2026-07-09 — CX-07: Actualización de action group con destinatarios

**Comando:** CX-07 — az monitor action-group update Service_Bus_Group --add-action email x4
**Resultado:** Se han agregado 4 receptores de email al action group `Service_Bus_Group`: `dantep@smartfran.com`, `claudioa@smartfran.com`, `javierp@smartfran.com`, `gasparc@smartfran.com`. Todos con status Enabled.
**Observación:** Se ha verificado que los 4 receptores quedaron correctamente configurados junto al receptor original `operaciones@smartfran.com`. Pendiente verificación de recepción mediante test de notificación.

## 2026-07-09 — Verificación de recepción de notificación

**Comando:** Test de notificación via portal — Monitor → Action groups → Service_Bus_Group → Test action group → Metric alert
**Resultado:** Se ha confirmado recepción de email en todos los destinatarios.
**Observación:** Se ha verificado el correcto funcionamiento del action group `Service_Bus_Group`. La configuración de alertas DLQ queda operativa.

## 2026-07-09 — Hallazgos operacionales sobre notificaciones por email en Azure Monitor

Se han identificado dos limitaciones a tener en cuenta en la operación de alertas por email:

**Demora en entrega:** Las notificaciones de test se envían de forma secuencial por receptor y pueden mostrar estado "Running" durante 1–2 minutos por dirección. Durante la verificación del action group `Service_Bus_Group` se observó que el envío a `gasparc@smartfran.com` permaneció en estado "Running" por varios minutos antes de completarse. Se ha confirmado que es comportamiento normal de Azure Monitor.

**Límite de emails:** Azure Monitor limita las notificaciones por email a **100 emails por hora por receptor y región**. Adicionalmente, un action group tiene un tope de **1.000 acciones de email en total**. Al superar cualquiera de estos límites, las alertas se suprimen silenciosamente. En escenarios de alta frecuencia (alertas disparando cada minuto), el límite horario puede agotarse en minutos. Se recomienda ampliar la ventana de evaluación o el período de agregación de las reglas de alerta para reducir la frecuencia de disparo.
