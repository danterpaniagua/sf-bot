# 20260806_automatizar_clubsite_ar

**Tags:** Operaciones, SmartLoyalty, ClubSite, Azure, DNS, SSL

## Resumen

Se automatizó la renovación del certificado SSL de ClubSite AR (`www.clubgrido.com.ar`), cubriendo dos conexiones TLS independientes que antes se renovaban de forma manual: el certificado público del listener en `WAF_APPs` (antes un PFX cargado directamente, sin integración con Key Vault) y, tras un hallazgo crítico detectado durante el trabajo, el certificado del tramo Gateway→Backend en `SFCG-CLUB-01` y `SFCG-CLUB-02` (antes un certificado GoDaddy con vencimiento el 2026-11-13, fuera del alcance original del ticket). Ambos tramos quedaron migrados a Let's Encrypt vía validación DNS-01 (Azure DNS delegado desde GoDaddy) y verificados en producción sin downtime.

## Tabla resumen

| Campo | Valor |
|---|---|
| Ticket Jira | [GITIN-1770](https://smartit-ar.atlassian.net/browse/GITIN-1770) |
| Historia | [GITIN-1768](https://smartit-ar.atlassian.net/browse/GITIN-1768) — Automatización de renovación de certificados SSL |
| Sistema | `WAF_APPs` (Application Gateway), `SFCG-CLUB-01`, `SFCG-CLUB-02` |
| Severidad | N/A (tarea de automatización) — ver H4 para el riesgo detectado durante el trabajo |
| Iniciado | 2026-08-06 |
| Resuelto | 2026-08-07 (ambos tramos completados y verificados; ver Acciones propuestas para ítems de seguimiento) |
| Responsable | SRE |

## Causa raíz

El certificado público de `www.clubgrido.com.ar` en `WAF_APPs` era un PFX cargado directamente, sin integración con Key Vault, por lo que cada renovación requería re-carga manual del certificado en el gateway. La validación HTTP-01 no es viable para este host (la regla HTTP tiene `redirectConfig` configurado y `backendPool: null` — redirección pura, sin backend real), por lo que se optó por DNS-01, delegando el subdominio `_acme-challenge.www.clubgrido.com.ar` a una zona Azure DNS de la misma forma que en `GITIN-1774`.

Durante la implementación se identificó una segunda causa raíz, independiente de la original: `WAF_APPs` hace re-encriptación end-to-end hacia el backend, es decir, dos conexiones TLS completamente independientes (Cliente↔Gateway y Gateway↔Backend). El certificado del backend —local en `SFCG-CLUB-01`/`02`, emitido por GoDaddy— no formaba parte del pedido original y no tenía ninguna automatización, con vencimiento el 2026-11-13.

## Hallazgos

| # | Hallazgo | Riesgo |
|---|---|---|
| H1 | El certificado público del listener era un PFX cargado directamente, sin integración con Key Vault — cada renovación exigía re-carga manual en el gateway. | Medio |
| H2 | Validación HTTP-01 descartada: `Rule_Clubsite_HTTP_AR` tiene `redirectConfig` configurado y `backendPool: null`, sin backend real que pueda responder al challenge. | Bajo (informativo) |
| H3 | `clubgrido.com.ar` está en GoDaddy sin acceso a la Domains API — resuelto delegando únicamente el subdominio `_acme-challenge.www.clubgrido.com.ar` a una zona Azure DNS, sin tocar el resto de los registros del dominio. | Bajo (mitigado) |
| H4 | El certificado del backend (tramo Gateway→Backend, independiente del público) vencía el 2026-11-13 y no tenía ninguna automatización — de no resolverse, hubiera causado una caída total del sitio al vencer, sin relación con la validez del certificado público. Hallazgo fuera del alcance original de este ticket. | Alto |
| H5 | `trustedRootCertificates` de Application Gateway solo acepta certificados raíz autofirmados — los certificados intermedios de la cadena de Let's Encrypt (`YR1`/`YR2`) no pueden cargarse ahí; deben ser servidos por el propio backend durante el handshake TLS. Dos intentos de carga de intermedios fallaron con `ApplicationGatewayTrustedRootCertificateInvalidData` antes de identificar esta causa. | Bajo (informativo, ya resuelto) |
| H6 | El certificado `clubgrido.2023.2024` quedó huérfano en el gateway tras el corte del listener al objeto respaldado por Key Vault — no está vinculado a ningún listener actualmente. | Bajo |

## Recursos afectados

| Recurso | Rol |
|---|---|
| `WAF_APPs` | Application Gateway — listener público (`Listener_ClubSite_HTTPS`) y HTTP settings del backend (`Backend_ClubSite`) |
| `sfcg-waf-apps-kv` | Key Vault nuevo (RBAC), almacena el certificado público con URI de secret sin versión |
| `waf-apps-kv-identity` | Managed Identity del gateway, con `Key Vault Secrets User` sobre el Key Vault |
| `_acme-challenge.www.clubgrido.com.ar` | Zona Azure DNS nueva, delegada desde GoDaddy, valida los challenges DNS-01 |
| Service Principal `winacme-mobileservice-dns` (appId `3cca7e2a-...`) | Reutilizado de `GITIN-1774`, con roles adicionales (`DNS Zone Contributor` en la zona nueva, `Key Vault Certificates Officer` en el Key Vault) y un segundo client secret (`--append`, sin invalidar los existentes) |
| `SFCG-CLUB-01` | Backend #1 de ClubSite — corre win-acme, entrega al Key Vault (certificado público) y al almacén de certificados local + binding IIS (certificado de backend) |
| `SFCG-CLUB-02` | Backend #2 de ClubSite — corre win-acme de forma independiente, entrega al almacén de certificados local + binding IIS (certificado de backend) |
| `letsencrypt-isrg-root-x1` | Objeto de certificado raíz confiable agregado a `WAF_APPs`, referenciado por `Backend_ClubSite` |

## Comandos ejecutados

| # | Comando / Script | Propósito |
|---|---|---|
| C1-C2 | `az network application-gateway show` (listeners, reglas de ruteo) | Mapeo listener→certificado y descarte de HTTP-01 |
| C3-C4 | `az keyvault list` / `show --query identity` | Confirmar que no había Key Vault ni identidad reutilizable |
| C5 | `az keyvault create` | ⚠️ Crear `sfcg-waf-apps-kv` (RBAC) |
| C6 | `az identity create` | ⚠️ Crear `waf-apps-kv-identity` |
| C7 | `az network application-gateway identity assign` | ⚠️ Adjuntar la identidad al gateway |
| C8 | `az role assignment create` | ⚠️ Otorgar `Key Vault Secrets User` a la identidad |
| C9 | `az network dns zone create` / `show` | ⚠️ Crear la zona Azure DNS y obtener nameservers |
| C10 | `az role assignment create` | ⚠️ Otorgar `DNS Zone Contributor` al Service Principal sobre la zona nueva |
| — | Registro NS en GoDaddy (manual) | ⚠️ Delegar `_acme-challenge.www` a la zona Azure DNS |
| C11-C14 | Instalación win-acme + `az ad app credential reset --append` + `wacs.exe` en `SFCG-CLUB-01` | ⚠️ Emitir y desplegar el certificado público a Key Vault |
| — | `az network application-gateway ssl-cert create` + `http-listener update` | ⚠️ Cortar el listener al objeto respaldado por Key Vault |
| — | `openssl s_client` | Verificar el certificado servido en el endpoint público |
| C16-C18 | `az network application-gateway root-cert create` (x3) | ⚠️ Intentos de carga de la cadena de confianza (2 fallidos, 1 exitoso — ver H5) |
| C19-C20 | Reconversión de formato + `openssl x509 -text` | Diagnóstico local de la causa real del fallo (certificados intermedios vs. raíz autofirmado) |
| C21 | `az network application-gateway http-settings update` | ⚠️ Adjuntar `letsencrypt-isrg-root-x1` a `Backend_ClubSite` |
| C22 | `az network application-gateway show-backend-health` | Confirmar `SFCG-CLUB-01` saludable tras el fix de cadena de confianza |
| C23-C26 | Instalación win-acme + `az ad app credential reset --append` + `wacs.exe` en `SFCG-CLUB-02` | ⚠️ Emitir e instalar el certificado de backend de forma independiente en el segundo nodo |

Detalle completo en `scripts.sh`.

## Acciones propuestas

1. **(SRE, ya aplicada)** Migrar el certificado público del listener a Key Vault con URI de secret sin versión, para que el gateway recoja automáticamente futuras rotaciones sin reconfiguración manual.
2. **(SRE, ya aplicada)** Automatizar la renovación DNS-01 del certificado público desde `SFCG-CLUB-01`, verificada end-to-end en el endpoint público sin downtime.
3. **(SRE, ya aplicada)** Automatizar el certificado del backend en `SFCG-CLUB-01` (hallazgo H4) — emitido, instalado, `Backend_ClubSite` saludable.
4. **(SRE, ya aplicada)** Repetir la automatización del certificado de backend en `SFCG-CLUB-02` de forma independiente (clave privada propia, sin copiar desde `-01`) — emitido, instalado, `Backend_ClubSite` saludable en ambos nodos.
5. **(SRE, ya aplicada)** Cargar la cadena de confianza de Let's Encrypt en `Backend_ClubSite` — solo el certificado raíz autofirmado (`letsencrypt-isrg-root-x1`) fue necesario tras diagnosticar H5.
6. **(SRE, pendiente)** Confirmar que el primer ciclo de renovación real (no forzado) se ejecute correctamente en ambos nodos — recordatorio de calendario agregado para 2026-10-03.
7. **(SRE, pendiente de decisión)** Definir si se limpia el certificado huérfano `clubgrido.2023.2024` del gateway o se deja como respaldo temporal.

## Hallazgos secundarios

- Durante la carga del nuevo registro NS de este ticket se detectó y corrigió un error preexistente en el registro NS de la zona de MobileAppService (`_acme-challenge.mobileservice`, `GITIN-1774`): el segundo nameserver estaba cargado como `ns2-01.azure-dns.com.` en lugar de `ns2-01.azure-dns.net.` (duplicado del primero por un error de copiado). No afectó a este ticket, documentado en `GITIN-1774`.
- `GITIN-1769` (ClubSite PY) permanece bloqueado — sin acceso DNS al dominio `.com.py` y sin backend real para HTTP-01 — sin acción tomada en el marco de este ticket.
