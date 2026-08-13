# Ticket — GITIN-1816

**Resumen:** una solicitud de recupero de cuenta ("Account Recovering") desde WebServiceCG (canal BOT) no resultó en la recepción del correo de recuperación por parte del socio. Se analizó un caso puntual (`Sofilualbornoz@icloud.com`, 2026-08-10 02:08 UTC): tanto la aplicación como el relay de correo local (hMailServer) completaron el envío hacia SendGrid sin error, pero no hay evidencia de que el correo haya llegado al destinatario. La causa raíz todavía no está confirmada — la investigación está bloqueada por falta de más ocurrencias que permitan determinar si se trata de un problema puntual (filtrado del dominio de destino) o de un problema más amplio (SendGrid / relay).

**Tabla resumen:**

| Campo | Valor |
|---|---|
| Ticket Jira | GITIN-1816 |
| Caso | Recupero de cuenta sin email — WebServiceCG |
| Sistema | SmartLoyalty — WebServiceCG / hMailServer / SendGrid |
| Severidad | A definir |
| Detectado | 2026-08-10 |
| Estado | En progreso — bloqueador de diagnóstico resuelto; causa raíz del email no recibido aún sin confirmar |
| Responsable | (SRE) |

**Causa raíz (no confirmada):** para el caso puntual analizado se descartó que la falla se origine en el código de WebServiceCG: la fila correspondiente en `Sml.CustomerAccountRecovery` (Id 746836) no registra excepción en el envío (`SendEmailError` nulo), y el log de hMailServer confirma que el mensaje fue aceptado y reenviado exitosamente a `smtp.sendgrid.net` en el mismo instante. Queda sin confirmar si la falla ocurre en SendGrid (rechazo o descarte posterior al relay) o en el filtrado de entrada del dominio de destino (iCloud). No hay evidencia suficiente para atribuir causa hasta contar con más casos y con el estado de entrega reportado por SendGrid.

**Hallazgos:**

| # | Hallazgo | Riesgo |
|---|---|---|
| H1 | `ExecuteRecovery` (WebServiceCG) ignora el valor de retorno de `SendMailConfirmation` y siempre responde éxito (200) al llamador, sin importar si el envío de email falló. No fue la causa del caso puntual analizado (no hubo excepción), pero enmascararía fallas reales de envío en otros casos. | Medio |
| H2 | El caso puntual analizado no pudo confirmarse como entregado a destino: la aplicación y el relay local completaron el envío hacia SendGrid, pero no hay evidencia de entrega final al buzón del socio. | Alto — pendiente confirmar alcance (caso aislado vs. sistémico) |
| H3 (resuelto) | La instrumentación NXLog de las VM de relay de correo (`SFCG-SMTP-01`/`SFCG-SMTP-02`, `192.168.50.161`/`.162`) no permitía correlacionar el ID de mensaje de hMailServer con el envío en Graylog. La interrupción intermitente observada durante el diagnóstico se debió a un reinicio del contenedor de OpenSearch que sostiene esa instancia de Graylog (confirmado por sus logs, no relacionado con la configuración de NXLog). Con eso resuelto, se desplegó la extracción de `MessageId` en ambas VM y se confirmó funcionando en producción. | Resuelto — habilita el punto 1 de "Acciones propuestas" |

**Consultas ejecutadas:**

| # | Query | Propósito |
|---|---|---|
| Q1 | Solicitudes recientes por canal BOT | Contexto general de recuperos recientes en `Sml.CustomerAccountRecovery` |
| Q2 | Solicitudes con `SendEmailError` no nulo | Buscar errores de envío a nivel de aplicación en la ventana reciente |
| Q3 | Caso puntual — `Sofilualbornoz@icloud.com` | Confirmar si el envío a nivel de aplicación falló para el caso reportado (resultado: no falló) |

**Acciones propuestas:**

1. Recopilar más ocurrencias del mismo síntoma (otros socios/emails/fechas) para determinar si el problema está acotado al dominio `icloud.com` o es más amplio — ya disponible vía correlación por `MessageId` en Graylog (H3).
2. Revisar el log de actividad de SendGrid para el mensaje 5669021 y para las ocurrencias adicionales que se recopilen, para obtener el estado final de entrega (entregado / rebotado / bloqueado / descartado). Sigue pendiente — no realizado todavía.
3. ~~Confirmar el host que genera el log de hMailServer analizado~~ — completado: `192.168.50.161` = `SFCG-SMTP-01`, `192.168.50.162` = `SFCG-SMTP-02`. Falta documentar el salto de relay de correo en `loyalty/docs/infrastructure.md`.
4. (Independiente del caso puntual) Corregir el manejo del valor de retorno de `SendMailConfirmation` en `ExecuteRecovery`, para que la API refleje fallas reales de envío en casos futuros en lugar de responder siempre éxito.
