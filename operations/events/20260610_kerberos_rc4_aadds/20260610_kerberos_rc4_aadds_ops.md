# AADDS123 — Kerberos RC4 Encryption Enabled

## Resumen

El equipo de Azure AD Domain Services emitió la alerta crítica AADDS123 el 10 de junio de 2026 por cifrado RC4 de Kerberos habilitado en el dominio administrado `smartit.azure`. La alerta en sí es una configuración de dominio por defecto, pero la auditoría de cuentas expuso el riesgo operacional real: la cuenta `itservices` es la identidad de todos los grupos de aplicaciones IIS en los servidores Windows Server 2019 de producción de SmartLoyalty. Esta cuenta no tiene declaración explícita de tipo de cifrado — depende del valor por defecto del dominio. Si RC4 se deshabilita sin validar previamente que IIS sobre WS2019 negocia AES correctamente con esta clase de cuenta, todos los servicios web de SmartLoyalty perderían autenticación contra el dominio simultáneamente: WebService, WebServiceV2, Website, Mobile, Club, CG y TaskOperatorService. El impacto es total e inmediato. Por este motivo la remediación está bloqueada hasta completar el plan de pruebas en entorno aislado.

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

El atributo `kerberosRc4Encryption` nunca fue configurado explícitamente en `domainSecuritySettings` del dominio administrado — el valor predeterminado de AADDS habilita RC4. Ninguna GPO restringe los tipos de cifrado permitidos. La cuenta `itservices`, que actúa como identidad transversal de IIS en toda la flota de servidores web, tampoco tiene `msDS-SupportedEncryptionTypes` declarado: hereda el default del dominio. Esta combinación crea una dependencia oculta: la autenticación Kerberos de todos los app pools de IIS en WS2019 funciona hoy únicamente porque RC4 está disponible. Al deshabilitarlo sin declarar AES explícitamente en `itservices` primero, el KDC no podría emitir tickets válidos para esa cuenta bajo el nuevo régimen de cifrado.

## Hallazgos

| # | Hallazgo | Riesgo |
|---|---|---|
| H1 | `kerberosRc4Encryption` ausente en `domainSecuritySettings` — valor predeterminado = Habilitado | Alto |
| H2 | `ntlmV1: Enabled` — NTLMv1 habilitado en el dominio | Alto |
| H3 | 38 cuentas de equipo con `msDS-SupportedEncryptionTypes: 28` (RC4 + AES-128 + AES-256) | Bajo — soporte AES confirmado |
| H4 | 1 cuenta de equipo sin atributo: `SFCG-DEVO-TEST` | Bajo — máquina de desarrollo/prueba |
| H5 | 6 cuentas de usuario sin atributo (no críticas): `Guest`, `dcaasadmin`, `claudioa`, `gastona`, `dantep`, `rubenf` — heredan default del dominio | Bajo |
| H6 | **`itservices` sin `msDS-SupportedEncryptionTypes` — identidad IIS (app pool) en WS2019 para la totalidad de los servidores web de SmartLoyalty. Sin declaración AES explícita, deshabilitar RC4 en el dominio interrumpe la autenticación Kerberos de todos los app pools simultáneamente: WebService (SFCG-WEBS-01/02/03), WebServiceV2 (SFCG-WSV2-01/02), Website (SFCG-WSIT-01), Mobile (SFCG-MOBI-01/02), Club (SFCG-CLUB-01/02), CG (SFCG-WSCG-01), TaskOperator (SFCG-TO-01)** | **Crítico — bloqueante de remediación** |
| H7 | `kerberosArmoring` ausente — FAST (Flexible Authentication Secure Tunneling) deshabilitado | Medio |
| H8 | LDAPS deshabilitado — LDAP sin cifrado en tránsito | Medio |

## Recursos afectados

### Cuenta crítica

| Recurso | Rol | `msDS-SupportedEncryptionTypes` | Impacto si RC4 se deshabilita sin AES declarado |
|---|---|---|---|
| **itservices** | Identidad de app pool IIS en **todos** los servidores web WS2019 de SmartLoyalty | **Sin atributo** — hereda default del dominio | **Caída total de autenticación en todos los servicios web de SmartLoyalty** |

### Servidores dependientes de itservices

Todos los servidores listados a continuación ejecutan uno o más app pools IIS bajo la identidad `SMARTIT\itservices`. Un fallo de autenticación Kerberos en esta cuenta afecta a todos simultáneamente.

| Servidor | Servicio | `msDS-SupportedEncryptionTypes` | Estado AES |
|---|---|---|---|
| SFCG-WEBS-01, 02, 03 | SmartLoyalty WebService | 28 (RC4+AES) | ✓ Confirmado |
| SFCG-WSV2-01, 02 | SmartLoyalty WebServiceV2 | 28 (RC4+AES) | ✓ Confirmado |
| SFCG-WSIT-01 | SmartLoyalty Website | 28 (RC4+AES) | ✓ Confirmado |
| SFCG-MOBI-01, 02 | Mobile service | 28 (RC4+AES) | ✓ Confirmado |
| SFCG-WSCG-01 | CG web service | 28 (RC4+AES) | ✓ Confirmado |
| SFCG-CLUB-01, 02 | Club Grido website | 28 (RC4+AES) | ✓ Confirmado |
| SFCG-TO-01 | TaskOperatorService | 28 (RC4+AES) | ✓ Confirmado |

### Otros recursos del dominio

| Servidor | Tipo | `msDS-SupportedEncryptionTypes` | Observación |
|---|---|---|---|
| SFCG-DB01 / SFCG-DB-01 | SQL Server (producción) | 28 (RC4+AES) | AES confirmado — dos entradas en dominio |
| SFCG-JENKINS-01 | CI/CD | 28 (RC4+AES) | AES confirmado |
| SFCG-SMTP-01, 02 | SMTP | 28 (RC4+AES) | AES confirmado |
| SFCG-SP-PROD | SmartPedidos producción | 28 (RC4+AES) | AES confirmado |
| SFCG-DEVO-TEST | Desarrollo/prueba | Sin atributo | Hereda default — máquina de pruebas del plan |

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

3. **Declarar AES explícito en `itservices` (C10)** — establecer `msDS-SupportedEncryptionTypes: 24` (AES-128 + AES-256) en `CN=appaccess` vía `ldapmodify`. Este paso es el más crítico de la secuencia: declara formalmente al KDC que `itservices` soporta AES antes de que RC4 sea deshabilitado a nivel de dominio. Sin este paso previo, el KDC no emitiría tickets válidos para los app pools de IIS al cambiar el régimen de cifrado. Requiere aprobación post-pruebas. *(Pendiente)*

4. **Deshabilitar RC4 en AADDS (C11)** — ejecutar `az ad ds update` con `kerberosRc4Encryption=Disabled`. El cambio toma efecto en minutos; no requiere reinicio de controladores de dominio ni servidores de aplicación. *(Pendiente)*

5. **Verificar aplicación del cambio (C12)** — confirmar que `kerberosRc4Encryption: Disabled` aparece en `domainSecuritySettings`. *(Pendiente)*

6. **Verificar autenticación de servicios en producción** — tras el cambio de dominio, confirmar que los servidores de aplicación autentican correctamente: `SFCG-WEBS-01/02/03`, `SFCG-WSV2-01/02`, `SFCG-DB01`, `SFCG-TO-01`. *(Pendiente)*

## Hallazgos secundarios

| # | Hallazgo | Acción recomendada |
|---|---|---|
| S1 | `ntlmV1: Enabled` — NTLMv1 es un protocolo deprecado con vulnerabilidades similares a RC4 | Deshabilitar en una ventana de cambio separada: `az ad ds update --domain-security-settings ntlmV1=Disabled` |
| S2 | `SFCG-DB-01` y `SFCG-DB01` — dos entradas para el mismo servidor DB | Verificar si `SFCG-DB-01` es una entrada obsoleta y eliminarla del dominio |
| S3 | LDAPS deshabilitado | Evaluar habilitación de LDAP sobre TLS para cifrar el tráfico de directorio |
