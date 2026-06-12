# AADDS123 — Kerberos RC4 Encryption Enabled

## Resumen

El equipo de Azure AD Domain Services emitió la alerta crítica AADDS123 el 10 de junio de 2026, indicando que el cifrado RC4 de Kerberos está habilitado en el dominio administrado `smartit.azure`. El cifrado RC4 (Kerberos etype 23, RC4-HMAC) es un algoritmo deprecado, vulnerable a ataques de Kerberoasting que permiten el descifrado offline de tickets Kerberos. La configuración no fue establecida explícitamente; el dominio opera con el valor predeterminado de AADDS que habilita RC4. Se realizó auditoría completa de cuentas. Se identificó que la cuenta `itservices` opera como identidad de grupos de aplicaciones IIS en Windows Server 2019 en todos los servidores web de producción — esto eleva el impacto de la remediación a Alto. Se requiere un plan de pruebas de compatibilidad AES en entorno aislado antes de aplicar cambios en producción.

## Tabla resumen

| Campo | Valor |
|---|---|
| ID alerta | AADDS123 |
| Sistema | Azure AD Domain Services — `smartit.azure` |
| Resource Group | `DefaultGroup01` |
| Conjunto de réplicas | East US / sfcgvnet01 / DMZ-AD |
| Severidad | Crítica |
| Detectado | 2026-06-10 16:27:17 UTC |
| Investigado | 2026-06-12 |
| Estado | En pruebas — remediación pendiente de validación |
| Resuelto | Pendiente |
| Responsable | Dante Paniagua |

## Causa raíz

El atributo `kerberosRc4Encryption` nunca fue configurado explícitamente en la sección `domainSecuritySettings` del dominio administrado. El valor predeterminado de Azure AD Domain Services habilita RC4, lo que activa la alerta AADDS123. No existe una política de grupo (GPO) que restrinja los tipos de cifrado Kerberos permitidos, y ninguna cuenta tiene el tipo de cifrado configurado de forma explícita que fuerce AES.

## Hallazgos

| # | Hallazgo | Riesgo |
|---|---|---|
| H1 | `kerberosRc4Encryption` ausente en `domainSecuritySettings` — valor predeterminado = Habilitado | Alto |
| H2 | `ntlmV1: Enabled` — NTLMv1 habilitado en el dominio | Alto |
| H3 | 38 cuentas de equipo con `msDS-SupportedEncryptionTypes: 28` (RC4 + AES-128 + AES-256) | Bajo — soporte AES confirmado |
| H4 | 1 cuenta de equipo sin atributo: `SFCG-DEVO-TEST` | Bajo — máquina de desarrollo/prueba |
| H5 | 7 cuentas de usuario sin atributo: `Guest`, `dcaasadmin`, `claudioa`, `gastona`, `dantep`, `itservices`, `rubenf` | Medio |
| H6 | Cuenta `itservices` sin atributo — usada por todos los servidores de aplicación para autenticación Kerberos | Medio — cuenta de servicio crítica |
| H7 | `kerberosArmoring` ausente — FAST (Flexible Authentication Secure Tunneling) deshabilitado | Medio |
| H8 | LDAPS deshabilitado — LDAP sin cifrado en tránsito | Medio |
| H9 | `itservices` opera como identidad de app pool IIS en Windows Server 2019 — la autenticación Kerberos hacia `SFCG-DB01` (SQL Server) depende de este canal en todos los servidores web | **Alto — requiere prueba de compatibilidad AES antes de remediación** |

## Recursos afectados

| Recurso | Tipo | `msDS-SupportedEncryptionTypes` | Observación |
|---|---|---|---|
| SFCG-WEBS-01, 02, 03 | Servidor web (SmartLoyalty WebService) | 28 (RC4+AES) | AES confirmado |
| SFCG-WSV2-01, 02 | Servidor web v2 | 28 (RC4+AES) | AES confirmado |
| SFCG-WSIT-01 | Website | 28 (RC4+AES) | AES confirmado |
| SFCG-MOBI-01, 02 | Servicio mobile | 28 (RC4+AES) | AES confirmado |
| SFCG-WSCG-01 | CG web service | 28 (RC4+AES) | AES confirmado |
| SFCG-CLUB-01, 02 | Club Grido website | 28 (RC4+AES) | AES confirmado |
| SFCG-TO-01 | TaskOperatorService | 28 (RC4+AES) | AES confirmado |
| SFCG-DB01 / SFCG-DB-01 | SQL Server (producción) | 28 (RC4+AES) | AES confirmado — dos entradas en dominio |
| SFCG-JENKINS-01 | CI/CD | 28 (RC4+AES) | AES confirmado |
| SFCG-SMTP-01, 02 | SMTP | 28 (RC4+AES) | AES confirmado |
| SFCG-SP-PROD | SmartPedidos producción | 28 (RC4+AES) | AES confirmado |
| SFCG-DEVO-TEST | Desarrollo/prueba | Sin atributo | Hereda default del dominio |
| itservices | Cuenta de servicio IIS (app pool identity, WS2019) | Sin atributo | ⚠️ Alta criticidad — requiere prueba de compatibilidad AES/WS2019 antes de remediación |

## Comandos ejecutados

**Investigación y auditoría:** `20260610_kerberos_rc4_aadds_scripts.sh`  
**Plan de pruebas (bash):** `20260610_kerberos_rc4_aadds_test.sh`  
**Plan de pruebas (PowerShell / WS2019):** `20260610_kerberos_rc4_aadds_test.ps1`

| # | Archivo | Comando / Script | Propósito |
|---|---|---|---|
| C1 | scripts.sh | `az resource list` | Localizar resource group del dominio administrado AADDS |
| C2 | scripts.sh | `az ad ds show` (completo) | Obtener detalle completo del dominio: configuración, réplicas, estado |
| C3 | scripts.sh | `az ad ds show --query domainSecuritySettings` | Verificar configuración de seguridad — confirmar RC4 habilitado por defecto |
| C4 | scripts.sh | `az ad ds show --query replicaSets` | Estado del conjunto de réplicas East US |
| C5 | scripts.sh | `az ad ds show --query healthAlerts` | Listado de alertas activas con URL de resolución |
| C6 | scripts.sh | `ldapsearch` usuarios con RC4 explícito | Auditar cuentas de usuario con bit RC4 activo en msDS-SupportedEncryptionTypes |
| C7 | scripts.sh | `ldapsearch` usuarios sin atributo | Auditar cuentas de usuario que heredan el default del dominio |
| C8 | scripts.sh | `ldapsearch` equipos con RC4 explícito | Auditar cuentas de equipo con bit RC4 activo — confirmar soporte AES |
| C9 | scripts.sh | `ldapsearch` equipos sin atributo | Auditar cuentas de equipo sin tipo de cifrado configurado |
| C10 ⚠️ | scripts.sh | `ldapmodify` en `CN=appaccess` | Establecer AES-128+AES-256 (valor 24) en cuenta `itservices` antes del cambio de dominio |
| C11 ⚠️ | scripts.sh | `az ad ds update kerberosRc4Encryption=Disabled` | Deshabilitar RC4 en la configuración de seguridad del dominio administrado |
| C12 | scripts.sh | `az ad ds show --query domainSecuritySettings` | Verificar que `kerberosRc4Encryption` figura como `Disabled` tras la actualización |
| T1 ⚠️ | test.sh | `az ad user create svc-aestest` | Crear usuario de prueba AES-only en Entra ID |
| T2 | test.sh | `ldapsearch svc-aestest` | Confirmar sincronización del usuario de prueba a AADDS |
| T3 ⚠️ | test.sh | `ldapmodify svc-aestest` | Establecer msDS-SupportedEncryptionTypes: 24 en cuenta de prueba |
| T4 | test.sh | `ldapsearch svc-aestest` (verificación) | Confirmar atributo AES-only aplicado |
| T5 ⚠️ | test.ps1 | `New-WebAppPool AESTestPool` | Crear app pool IIS con identidad svc-aestest en SFCG-DEVO-TEST |
| T6 | test.ps1 | `klist` | Verificar tipo de cifrado del ticket Kerberos activo — debe ser 0x12 o 0x11 |
| T7 | test.ps1 | `Get-WinEvent 4769` | Consultar log de seguridad del DC — confirmar etype AES en ticket emitido a svc-aestest |
| T8 ⚠️ | test.sh + test.ps1 | `az ad user delete` + `Remove-WebAppPool` | Limpieza: eliminar usuario y app pool de prueba |

## Acciones propuestas

1. **Ejecutar plan de pruebas AES/WS2019 (T1–T7)** — crear cuenta `svc-aestest` con AES-only, configurar app pool de IIS en `SFCG-DEVO-TEST`, y verificar que el ticket Kerberos emitido usa etype `0x12` o `0x11`. La remediación en producción queda bloqueada hasta que esta prueba sea exitosa. *(En ejecución)*

2. **Limpiar entorno de pruebas (T8)** — eliminar `svc-aestest` de Entra ID y el app pool `AESTestPool` de `SFCG-DEVO-TEST` tras confirmar resultados. *(Pendiente de T1–T7)*

3. **Actualizar `itservices` a AES-only (C10)** — ejecutar `ldapmodify` para establecer `msDS-SupportedEncryptionTypes: 24` en `CN=appaccess`. Requiere aprobación post-pruebas. *(Pendiente)*

4. **Deshabilitar RC4 en AADDS (C11)** — ejecutar `az ad ds update` con `kerberosRc4Encryption=Disabled`. El cambio toma efecto en minutos; no requiere reinicio de controladores de dominio ni servidores de aplicación. *(Pendiente)*

5. **Verificar aplicación del cambio (C12)** — confirmar que `kerberosRc4Encryption: Disabled` aparece en `domainSecuritySettings`. *(Pendiente)*

6. **Verificar autenticación de servicios en producción** — tras el cambio de dominio, confirmar que los servidores de aplicación autentican correctamente: `SFCG-WEBS-01/02/03`, `SFCG-WSV2-01/02`, `SFCG-DB01`, `SFCG-TO-01`. *(Pendiente)*

## Hallazgos secundarios

| # | Hallazgo | Acción recomendada |
|---|---|---|
| S1 | `ntlmV1: Enabled` — NTLMv1 es un protocolo deprecado con vulnerabilidades similares a RC4 | Deshabilitar en una ventana de cambio separada: `az ad ds update --domain-security-settings ntlmV1=Disabled` |
| S2 | `SFCG-DB-01` y `SFCG-DB01` — dos entradas para el mismo servidor DB | Verificar si `SFCG-DB-01` es una entrada obsoleta y eliminarla del dominio |
| S3 | LDAPS deshabilitado | Evaluar habilitación de LDAP sobre TLS para cifrar el tráfico de directorio |
