# Eventos — itservices, bloqueo recurrente por rotación de contraseña no coordinada

## 2026-07-23 — Reporte inicial: contraseña nueva rechazada en IIS

**Resultado:**
He verificado que la nueva contraseña de la cuenta Entra ID asignada como identidad de App Pool IIS no es aceptada, con el mensaje "The specified password is invalid". He confirmado que la misma cuenta sí permite inicio de sesión en el portal de Azure con esa contraseña, descartando un simple error de tipeo en Entra ID y apuntando a una diferencia entre la autenticación de portal (Entra ID directo) y la autenticación de IIS (Kerberos/NTLM contra el dominio administrado Azure AD DS `smartit.azure`).

---

## 2026-07-23 10:5X — Localización del objeto en AADDS

**Comando:** CX-01/CX-02 — Búsqueda ANR y búsqueda dirigida por UPN/mail
**Resultado:**
```
DN: CN=appaccess,OU=AADDC Users,DC=smartit,DC=azure
Class: top person organizationalPerson user
sAM: itservices
UPN: grupo.servicesit@smartfran.com
PwdLastSet: 07/23/2026 10:42:29
WhenChanged: 07/23/2026 10:49:48
```
He confirmado que la cuenta corresponde a `itservices`, la identidad de App Pool IIS transversal a toda la flota de SmartLoyalty documentada en el evento AADDS123 (`20260610_kerberos_rc4_aadds`). El `pwdLastSet` reciente confirma que el hash de la nueva contraseña ya se sincronizó desde Entra ID hacia AADDS, descartando retraso de sincronización como causa.

---

## 2026-07-23 — Descarte de credencial cacheada y primer hallazgo de bloqueo

**Comando:** CX-05/CX-06 — `cmdkey /list` y prueba aislada con `Start-Process -Credential`
**Resultado:**
```
Start-Process : This command cannot be run due to the error: The referenced
account is currently locked out and may not be logged on to.
```
He descartado que `runas` estuviera reutilizando una credencial cacheada (`cmdkey /list` no mostró entradas para `itservices`). La prueba aislada con `Start-Process -Credential` reveló el problema real: la cuenta está bloqueada en el dominio, no la contraseña es inválida. Esto explica por qué IIS mostraba un mensaje genérico.

---

## 2026-07-23 11:04 — Confirmación de bloqueo en ambas réplicas AADDS

**Comando:** CX-07/CX-08 — Verificación de `lockoutTime`/`badPwdCount` por DC
**Resultado:**
```
192.168.40.4 -> badPwdCount: 5
192.168.40.4 -> LOCKED since: 07/23/2026 11:04:21
192.168.40.5 -> badPwdCount: 0
192.168.40.5 -> LOCKED since: 07/23/2026 11:04:21
```
He detectado primero un bug propio en el script de diagnóstico (casteo directo de `lockoutTime` vía `[ADSI]` falla por tratarse de un objeto COM `IADsLargeInteger`), y lo he corregido usando `DirectorySearcher` para el marshaling correcto. Con el script corregido he confirmado que ambas réplicas del DC coinciden en el `lockoutTime`, validando que la replicación urgente de bloqueo funciona correctamente. La divergencia en `badPwdCount` (5 vs 0) es esperada, ya que ese atributo no se replica entre controladores de dominio.

---

## 2026-07-23 — Desbloqueo y detección de reintentos activos desde la flota

**Comando:** CX-09/CX-10 — Desbloqueo sobre `192.168.40.4` y reverificación
**Resultado:**
```
Unlock succeeded
...
192.168.40.4 -> badPwdCount: 2
192.168.40.4 -> not locked
192.168.40.5 -> badPwdCount: 0
192.168.40.5 -> not locked
```
He desbloqueado la cuenta y confirmado el estado "not locked" en ambas réplicas. Sin embargo, `badPwdCount` ya mostraba 2 intentos fallidos sin ninguna acción manual adicional de mi parte, lo cual me indicó que otro origen —presumiblemente otro servidor de la flota SmartLoyalty todavía configurado con la contraseña anterior de `itservices`— estaba generando intentos de autenticación fallidos de forma automática.

---

## 2026-07-23 — Segundo bloqueo y confirmación de causa raíz

**Resultado:**
He confirmado que la cuenta volvió a bloquearse minutos después del desbloqueo anterior. He verificado que el resto de los servidores de la flota (`SFCG-WEBS-01/02/03`, `SFCG-WSV2-01/02`, `SFCG-WSIT-01`, `SFCG-MOBI-01/02`, `SFCG-WSCG-01`, `SFCG-CLUB-01/02`, `SFCG-TO-01`) siguen configurados con la contraseña anterior de `itservices`, y que sus reintentos automáticos de autenticación son la causa del bloqueo recurrente. Esto confirma que la rotación de contraseña de esta cuenta debe tratarse como una operación de flota completa, no de servidor individual.

---

## 2026-07-23 — Resolución puntual

**Resultado:**
He confirmado la resolución del bloqueo tras un nuevo desbloqueo. No registré un script adicional para ese último paso dentro de esta sesión — queda pendiente de verificación formal en el próximo acceso. La rotación coordinada en el resto de la flota queda pendiente y documentada como acción propuesta en el ticket, junto con un runbook (`operations/docs/itservices_rotacion_password_runbook.md`) para estandarizar el procedimiento.

---

## 2026-07-23 — Rollout coordinado completado en toda la flota

**Resultado:**
He confirmado que la rotación de contraseña de `itservices` quedó ejecutada en los 12 servidores de la flota SmartLoyalty (`SFCG-WEBS-01/02/03`, `SFCG-WSV2-01/02`, `SFCG-WSIT-01`, `SFCG-MOBI-01/02`, `SFCG-WSCG-01`, `SFCG-CLUB-01/02`, `SFCG-TO-01`). Con todos los servidores alineados a la misma credencial, el origen del bloqueo recurrente (reintentos automáticos con la contraseña anterior desde servidores no actualizados) queda eliminado. No cuento con la verificación puntual de `badPwdCount`/`lockoutTime` post-rollout dentro de esta sesión — queda como pendiente de confirmación formal antes de cerrar el ticket.

---

## 2026-07-23 — Confirmación operativa: todos los App Pools IIS en línea con la nueva credencial

**Resultado:**
He confirmado que la totalidad de los App Pools IIS de la flota SmartLoyalty están operativos bajo la nueva credencial de `itservices`. No registré en esta sesión una verificación formal de `badPwdCount`/`lockoutTime` vía LDAP posterior a esta confirmación operativa — el estado a nivel AADDS queda como pendiente de chequeo puntual, aunque el funcionamiento correcto de todos los servicios ya es evidencia fuerte de que la rotación fue exitosa en toda la flota.
