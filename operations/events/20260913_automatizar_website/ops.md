# GITIN-1771 — Automatizar renovación SSL de WebSite (gestion.clubgrido.com.ar)

**Tags:** SmartFran, Azure, WAF_APPs, SSL, SRE, PROD

## Resumen

`gestion.clubgrido.com.ar` (host `SFCG-WSIT-01`, único nodo, sin redundancia), servido por `WAF_APPs`, tenía su certificado SSL en modo manual (PFX directo, sin automatización) en ambos tramos: el público (listener del gateway) y el del backend (binding IIS local, ya que el gateway re-encripta hacia el backend). Este ticket, subtarea de la épica `GITIN-1768`, automatiza ambos tramos siguiendo el mismo patrón ya implementado para ClubSite AR (`GITIN-1770`): DNS-01 vía Azure DNS delegado, win-acme como cliente, Key Vault para el certificado público y Windows Certificate Store + binding IIS para el del backend. Trabajo distribuido en dos sesiones: preparación de DNS/permisos/delegación (2026-09-13) y ejecución completa durante una ventana fuera de horario laboral (2026-09-22).

## Tabla resumen

| Campo | Valor |
|---|---|
| Ticket Jira | [GITIN-1771](https://smartit-ar.atlassian.net/browse/GITIN-1771) (subtarea de la épica [GITIN-1768](https://smartit-ar.atlassian.net/browse/GITIN-1768)) |
| Sistema | SmartFran Cloud/SmartLoyalty — `SFCG-WSIT-01`, Application Gateway `WAF_APPs` |
| Severidad | Media — automatización preventiva, no había caída activa |
| Detectado | N/A — trabajo proactivo dentro de la épica de automatización SSL |
| Resuelto | 2026-09-22 |
| Responsable | Dante Paniagua |

## Causa raíz

No aplica — no hubo incidente. El certificado previo se renovaba manualmente; este ticket reemplaza ese proceso manual por renovación automática en ambos tramos (público y backend).

## Hallazgos

| # | Hallazgo | Riesgo |
|---|---|---|
| H1 | Confirmado (2026-09-13): `gestion.clubgrido.com.ar` está en `WAF_APPs` (`Listener_WebSite_HTTPS`, backend real `Backend_WebSite`, no solo redirección) — mismo patrón que ClubSite AR | Informativo |
| H2 | Zona DNS `_acme-challenge.gestion.clubgrido.com.ar`, asignación de rol del Service Principal, y delegación NS en GoDaddy — todo confirmado funcionando (2026-09-13) | Informativo |
| H3 | `Backend_WebSite` solo confiaba en la CA vieja de GoDaddy — mismo gap de cadena de confianza que tuvo ClubSite AR. Corregido (2026-09-22): agregado `letsencrypt-isrg-root-x1` (ya cargado en el gateway desde el fix de ClubSite AR) a `trustedRootCertificates`. Verificado sin impacto — `Back_WebSite` healthy antes y después | Informativo (corregido) |
| H4 | Precheck de bindings IIS en `SFCG-WSIT-01` encontró dos bindings sobre el puerto 4430 compartiendo un mismo hash de certificado: la del hostname real (sitio `SmartLoyalty.WebSite`) y una sin hostname (sitio `DefaultAppPool`). Resuelto: `DefaultAppPool` apunta al mismo `PhysicalPath` (`D:\SmartLoyalty.WebSite`) — es la misma aplicación, no una distinta — actualizar ambas es correcto | Informativo (resuelto) |
| H5 | Certificado público emitido y validado correctamente vía DNS-01. El log de win-acme mostró `Store with KeyVault... Unauthorized`, que en un primer momento pareció una falla real (llevó a re-chequear permisos RBAC y ACLs de red del Key Vault, ambos correctos). **Resuelto**: es el comportamiento estándar de desafío OAuth de Key Vault (primer request sin token, reintento inmediato con token adjunto) — no una falla. Certificado confirmado en el vault (`enabled=true`, válido 2026-09-22 a 2026-12-21) | Bajo (falsa alarma, aclarado) |
| H6 | Listener del gateway repuntado de `website_2024` (PFX directo) al nuevo objeto `gestion-clubgrido-com-ar-kv` (Key Vault, URI de secret sin versión — el gateway recoge renovaciones automáticamente). `Back_WebSite` confirmado healthy antes y después del cambio | Informativo (confirmado) |
| H7 | Al ejecutar el segundo wizard (certificado del backend), win-acme ofreció sobrescribir la renovación existente (mismo nombre de entrada que la del certificado público) — **se rechazó** (`n`, no el default `y*`), evitando que ambas renovaciones quedaran fusionadas en una sola entrada, lo que habría roto la renovación automática de uno de los dos certificados en el futuro sin que fuera evidente hasta el próximo vencimiento | Alto (evitado — hubiera sido un problema silencioso a futuro) |
| H8 | El plugin de instalación IIS del certificado de backend actualizó solo la binding del sitio elegido en el wizard (`SmartLoyalty.WebSite`) — la binding sin hostname de `DefaultAppPool` (mismo hash antes, misma app) **no** se actualizó automáticamente, contradiciendo la premisa general documentada en el runbook ("actualiza todas las bindings que comparten el hash viejo"). Corregido manualmente (`AddSslCertificate`). Runbook actualizado con esta corrección para futuros casos | Medio (corregido, runbook actualizado) |
| H9 | Hallazgo no relacionado, fuera de alcance de este ticket, solo señalado: el segundo nodo de ClubSite AR (`192.168.50.122`) aparece `Unhealthy` en los chequeos de salud del backend realizados durante este ticket — "Cannot connect to backend server". No investigado acá | Medio (fuera de alcance, señalado al usuario) |

## Recursos afectados

| Recurso | Detalle |
|---|---|
| `SFCG-WSIT-01` | Host donde se instaló win-acme y se actualizaron los bindings IIS |
| `WAF_APPs` (`Listener_WebSite_HTTPS`, `Backend_WebSite`) | Listener repuntado a Key Vault; trust chain del backend corregida |
| `sfcg-waf-apps-kv` | Nuevo certificado `gestion-clubgrido-com-ar` almacenado |
| Service Principal `winacme-mobileservice-dns` | Nuevo secreto agregado (`--append`), scopeado a este host |

## Comandos ejecutados

| # | Comando/Script | Propósito |
|---|---|---|
| 1-3 | `http-settings show`/`update`, `show-backend-health` | Corregir y verificar la cadena de confianza del backend (H3) |
| 4 | `az ad app credential reset --append` | Nuevo secreto del Service Principal para `SFCG-WSIT-01` |
| 5-6 | `Get-WebBinding`, `Get-Website` | Precheck de bindings IIS antes del wizard (H4) |
| 7 | win-acme wizard, Run 1 (interactivo) | Emisión del certificado público, almacenado en Key Vault |
| 8 | `az keyvault certificate show` | Verificación independiente del certificado emitido |
| 9-10 | `ssl-cert create`, `http-listener update` | Repuntar el listener del gateway a Key Vault (H6) |
| 11 | win-acme wizard, Run 2 (interactivo) | Emisión del certificado de backend, instalado en el store local + binding IIS |
| 12 | `Get-WebBinding`, `AddSslCertificate` | Verificar y corregir la binding de `DefaultAppPool` (H8) |
| 13 | `show-backend-health` | Verificación final |

Detalle completo, incluyendo la secuencia exacta de elecciones de cada wizard, en `scripts.sh`.

## Acciones propuestas

1. **(SRE) Completado** — Automatización SSL de ambos tramos (público vía Key Vault, backend vía Windows Certificate Store + binding IIS) para `gestion.clubgrido.com.ar`, verificada de punta a punta.
2. **(SRE) Completado** — Runbook (`operations/docs/waf_apps_cert_automation_runbook.md`) actualizado con la corrección sobre el alcance real del plugin de instalación IIS (H8), para no repetir el supuesto incorrecto en `GITIN-1772`/`GITIN-1773` u otros casos futuros.
3. **(SRE) Pendiente, fuera de alcance** — Estado `Bloqueado` en el tablero de Jira para este ticket nunca se explicó técnicamente (no se encontró ningún bloqueador real durante la investigación ni la ejecución) — señalado, no resuelto.
4. **(SRE) Pendiente, fuera de alcance** — Nodo `192.168.50.122` de ClubSite AR aparece `Unhealthy` en los chequeos de salud del backend (H9) — ticket propio si se decide investigar.

## Hallazgos secundarios

Nodo `192.168.50.122` de `Back_ClubSite`/`Back_ClubSite_PY` (ClubSite AR/PY) confirmado `Unhealthy` ("Cannot connect to backend server") en los chequeos de salud realizados durante este ticket — no relacionado con WebSite, no investigado acá (ver H9).
