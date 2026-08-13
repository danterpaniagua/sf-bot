# OPS — Renovación y automatización del certificado SSL de MobileAppService

**Tags:** `Operaciones`, `MobileAppService`, `Azure`, `SRE`, `PROD`

## Resumen

El certificado SSL del endpoint público `mobileservice.clubgrido.com.ar:8043` (servicio MobileAppService, parte de SmartLoyalty) vence el 9 de agosto de 2026, sin proceso de renovación automática vigente. El certificado actual ya es de Let's Encrypt, lo que indica que fue emitido manualmente en un ciclo anterior sin haberse automatizado. El servicio corre sobre IIS en dos VMs Windows (`SFCG-MOBI-01` y `SFCG-MOBI-02`) detrás de un Load Balancer L4, sin Application Gateway/WAF de por medio. Severidad crítica dado el impacto sobre la disponibilidad pública del servicio si el certificado vence sin reemplazo.

## Tabla resumen

| Campo | Valor |
|---|---|
| Ticket Jira | GITIN-1786 |
| ID alerta | — |
| Sistema | MobileAppService — IIS — `mobileservice.clubgrido.com.ar:8043` |
| Severidad | Crítica |
| Detectado | 2026-08-04 |
| Resuelto | Pendiente |
| Responsable | Dante Paniagua |

## Causa raíz

El certificado de `mobileservice.clubgrido.com.ar` nunca tuvo un proceso de renovación automática, a pesar de ya ser un certificado Let's Encrypt (90 días de vigencia) emitido manualmente en un ciclo previo por el equipo/proceso anterior ("Grido"). Al no existir automatización, el certificado quedó sin renovar hasta quedar a días de su vencimiento. La topología de red (Load Balancer sin regla de puerto 80/443, solo 8043) impide validación ACME HTTP-01 sin abrir una regla nueva exclusivamente para eso, y la cuenta de GoDaddy que administra el DNS del dominio no tiene habilitado el acceso a su API de Domains (`403 ACCESS_DENIED`), lo que bloquea la automatización DNS-01 directa contra GoDaddy.

## Hallazgos

| # | Hallazgo | Riesgo |
|---|---|---|
| H1 | Certificado de `mobileservice.clubgrido.com.ar` (Let's Encrypt) sin renovación automática, a días de vencer | Alto |
| H2 | Load Balancer `SFCG-MOBI-LB` solo expone la regla TCP 8043→8043 (`SourceIPProtocol`) — sin regla de puerto 80/443, bloquea validación ACME HTTP-01 | Medio |
| H3 | Cuenta GoDaddy sin acceso habilitado a la API de Domains (`403 ACCESS_DENIED`, confirmado con prueba directa) — bloquea automatización DNS-01 vía GoDaddy | Alto |
| H4 | El certificado original era compartido/duplicado manualmente entre `SFCG-MOBI-01` y `SFCG-MOBI-02`, sin proceso documentado de distribución | Medio |
| H5 | Primer token de API de GoDaddy generado con 11 scopes, incluyendo eliminación y transferencia de dominio, muy por encima de lo necesario (`domains.dns:update` únicamente) | Alto (seguridad) |
| H6 | `loyalty/docs/infrastructure.md` no documentaba el detalle de VM de MobileAppService (tamaño, IP, subnet, subscripción) — corregido durante esta investigación | Bajo |

## Recursos afectados

| Recurso | Tipo | Detalle |
|---|---|---|
| `SFCG-MOBI-01` | VM Windows / IIS | `Standard_B2as_v2`, DMZ, `DefaultGroup01`, sub. Smart IT - Grido |
| `SFCG-MOBI-02` | VM Windows / IIS | Mismo grupo/subscripción que `-01` |
| `SFCG-MOBI-LB` | Load Balancer (L4) | IP pública `20.121.19.174`, única regla TCP 8043→8043 |
| `mobileservice.clubgrido.com.ar` | Dominio público | DNS gestionado en GoDaddy |
| Cuenta GoDaddy (`clubgrido.com.ar`) | Cuenta DNS | Sin acceso habilitado a API de Domains |

## Comandos ejecutados

| # | Comando / Script | Propósito |
|---|---|---|
| C1-C5 | Inventario Azure (NICs, LB, frontend IP, IP pública) | Confirmar topología de red de MobileAppService |
| C6 | `dig NS` / `dig A` | Confirmar proveedor DNS (GoDaddy) y resolución pública |
| C7 | `openssl s_client` / `openssl x509` | Verificar emisor, vigencia y SAN del certificado vigente |
| C8, C11 | `netsh http show sslcert` | Capturar binding SSL anterior en cada VM (referencia de rollback) |
| C9 | win-acme, validación DNS-01 vía plugin GoDaddy | ⚠️ Intento fallido — bloqueado por restricción de cuenta GoDaddy |
| C10, C12 | win-acme, validación DNS-01 manual | ⚠️ Emisión y vinculación de certificado de reemplazo en `SFCG-MOBI-01` y `SFCG-MOBI-02` |

Ver: `20260804_mobileappservice_ssl_cert_renewal_scripts.sh`

## Acciones propuestas

1. **Emitir un certificado de reemplazo en `SFCG-MOBI-01`** mediante win-acme, con validación DNS-01 manual (registro TXT temporal en GoDaddy), y vincularlo al binding HTTPS del sitio `SmartLoyalty.MobileAppService` en el puerto 8043.
2. **Repetir el procedimiento de forma independiente en `SFCG-MOBI-02`** — no reutilizar el certificado de `-01`, dado que win-acme genera la clave privada como no exportable por defecto.
3. **Eliminar los registros TXT temporales** de validación en GoDaddy una vez emitidos ambos certificados.
4. **Revocar o reducir el alcance del token de API de GoDaddy** generado durante la investigación (11 scopes, incluye eliminación y transferencia de dominio) — no debe reutilizarse en su forma actual.
5. **Delegar el subdominio `_acme-challenge.mobileservice.clubgrido.com.ar` a una zona de Azure DNS**, mediante un único registro NS agregado manualmente en GoDaddy.
6. **Instalar el plugin de validación DNS-01 de Azure DNS en win-acme**, de forma independiente en `SFCG-MOBI-01` y `SFCG-MOBI-02`, y reconfigurar cada tarea programada de renovación para usar esta validación en lugar de la manual — esto habilita renovación automática real, sin dependencia de la API de GoDaddy.
7. **Confirmar y documentar la cuenta bajo la cual corre la tarea programada `win-acme renew` en `SFCG-MOBI-01`** (actualmente una cuenta nombrada, no confirmada) — evaluar alinearla con `SYSTEM` (usada en `SFCG-MOBI-02`) para evitar acoplamiento con el runbook de rotación de `SMARTIT\itservices`.
8. **Escalonar el horario de las tareas programadas de renovación** entre ambas VMs (p. ej. 09:00 en `-01`, 13:00 en `-02`) para evitar solapamiento, aunque DNS-01 soporta múltiples valores TXT concurrentes bajo el mismo nombre de registro.
9. **Verificar que la renovación automatizada funcione correctamente antes del 2026-09-28**, fecha de la próxima renovación programada en ambas VMs bajo el esquema actual.

## Hallazgos secundarios

**Restricción de acceso a API en cuentas GoDaddy:** la cuenta GoDaddy que administra `clubgrido.com.ar` no tiene habilitado el acceso a la API de Domains, una restricción a nivel de cuenta documentada por GoDaddy y no vinculada a las credenciales utilizadas. Cualquier otra automatización futura que dependa de esta API (para este dominio o para otros gestionados por la misma cuenta) se verá bloqueada de la misma manera — vale la pena evaluar si corresponde solicitar la habilitación a GoDaddy como mejora independiente de este ticket.

**Brecha de documentación corregida:** `loyalty/docs/infrastructure.md` listaba a `SFCG-MOBI-01/02` únicamente como "Mobile service", sin detalle de VM. Se actualizó con tamaño, IP pública, subnet y subscripción durante esta investigación.
