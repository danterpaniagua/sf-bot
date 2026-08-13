Asunto: itservices — Rotación de contraseña completada en toda la flota SmartLoyalty

Hola equipo,

Les cuento que quedó completada la rotación de contraseña de la cuenta `itservices`, identidad compartida de App Pool IIS en los 12 servidores de producción de SmartLoyalty (WebService, WebServiceV2, Website, Mobile, Club, CG, TaskOperator).

Durante el proceso la cuenta sufrió bloqueos recurrentes en Azure AD DS mientras la contraseña nueva coexistía con la anterior en distintos servidores de la flota — el detalle completo quedó documentado en el ticket `20260723_itservices_bloqueo_password` (`operations/events/20260723_itservices_bloqueo_password/`). Con la rotación ya aplicada en todos los servidores, los App Pools están operativos con la nueva credencial y no se registran nuevos bloqueos.

Queda pendiente una verificación puntual de `badPwdCount`/`lockoutTime` a nivel LDAP en ambas réplicas de Azure AD DS antes de dar el ticket por cerrado formalmente — la incluyo como próximo paso en el ticket.

También dejé un runbook (`operations/docs/itservices_rotacion_password_runbook.md`) con el procedimiento paso a paso para la próxima vez que haya que tocar esta cuenta, dado que cualquier cambio sobre ella debe tratarse como operación de flota completa.

Saludos,
Dante
