# 20260806_automatizar_clubsite_py

**Tags:** Operaciones, SmartLoyalty, ClubSite, Azure, DNS, SSL

## Resumen

Se automatizó la renovación del certificado SSL de ClubSite PY (`www.clubgrido.com.py`), cubriendo dos conexiones TLS independientes que antes se renovaban de forma manual: el certificado público del listener en `WAF_APPs` (antes un PFX cargado directamente, sin integración con Key Vault) y el certificado del tramo Gateway→Backend en `SFCG-CLUB-01` y `SFCG-CLUB-02`. El ticket estuvo bloqueado desde el 2026-08-06 por falta de acceso administrativo al dominio `clubgrido.com.py` — se resolvió pidiendo por correo a IT Grido el registro de delegación NS, confirmado de forma independiente el 2026-09-08. Durante el trabajo se detectó un segundo hallazgo crítico, fuera del alcance original: el certificado del backend ya vencía en 6 días (2026-09-15) sin ninguna automatización configurada. Ambos tramos quedaron migrados a Let's Encrypt vía validación DNS-01 y verificados en producción sin downtime, con redundancia completa restaurada en ambos nodos.

## Tabla resumen

| Campo | Valor |
|---|---|
| Ticket Jira | [GITIN-1769](https://smartit-ar.atlassian.net/browse/GITIN-1769) |
| Historia | [GITIN-1768](https://smartit-ar.atlassian.net/browse/GITIN-1768) — Automatización de renovación de certificados SSL |
| Sistema | `WAF_APPs` (Application Gateway), `SFCG-CLUB-01`, `SFCG-CLUB-02` |
| Severidad | N/A (tarea de automatización) — ver H5 para el riesgo detectado durante el trabajo |
| Iniciado | 2026-08-06 |
| Resuelto | 2026-09-09 (ambos tramos completados y verificados; ver Acciones propuestas para ítems de seguimiento) |
| Responsable | SRE |

## Causa raíz

El certificado público de `www.clubgrido.com.py` en `WAF_APPs` era un PFX cargado directamente, sin integración con Key Vault, por lo que cada renovación requería re-carga manual del certificado en el gateway. La validación HTTP-01 no es viable para este host (`Rule_ClubSite_HTTP_PY` tiene `redirectConfig` configurado y `backendPool: null` — redirección pura, sin backend real), por lo que se optó por DNS-01, siguiendo el mismo patrón que `GITIN-1770` (ClubSite AR).

A diferencia de AR, este ticket quedó bloqueado desde el inicio: no había acceso administrativo al dominio `clubgrido.com.py`, lo que impedía agregar directamente el registro NS de delegación (a diferencia de `clubgrido.com.ar`, en GoDaddy con acceso confirmado). Se resolvió creando igualmente la zona Azure DNS y pidiendo por correo a Jordan (IT Grido), quien administra ese dominio, que agregara el registro de delegación — confirmado funcionando el 2026-09-08 vía `dig` independiente, no solo por el reporte de IT Grido.

Durante la implementación se identificó una segunda causa raíz, independiente de la original: al investigar por qué `Backend_ClubSite_PY.trustedRootCertificates` estaba en `null` (a diferencia de `clubsite_CA` explícito en AR pre-fix), se confirmó que el certificado del backend ya era Let's Encrypt (emitido antes de que arrancara la épica `GITIN-1768`, por un mecanismo no identificado) y vencía el 2026-09-15 — 6 días desde el hallazgo, sin ninguna automatización configurada en ningún host.

## Hallazgos

| # | Hallazgo | Riesgo |
|---|---|---|
| H1 | El certificado público del listener era un PFX cargado directamente, sin integración con Key Vault — cada renovación exigía re-carga manual en el gateway. | Medio |
| H2 | Validación HTTP-01 descartada: `Rule_ClubSite_HTTP_PY` tiene `redirectConfig` configurado y `backendPool: null`, sin backend real que pueda responder al challenge. | Bajo (informativo) |
| H3 | Sin acceso administrativo a `clubgrido.com.py` — bloqueó agregar directamente el registro NS de delegación. Resuelto pidiendo el registro por correo a IT Grido, confirmado funcionando de forma independiente vía `dig` (no solo por el reporte recibido). | Bajo (mitigado) |
| H4 | `trustedRootCertificates: null` en `Backend_ClubSite_PY` no era una laguna de configuración: el certificado del backend ya chain-eaba a `ISRG Root X1`, una CA pública que Application Gateway v2 confía por defecto. | Bajo (informativo) |
| H5 | El certificado del backend (tramo Gateway→Backend, independiente del público) vencía el 2026-09-15 — 6 días desde el hallazgo — sin ninguna automatización configurada en ningún host. De no resolverse, hubiera causado una caída total del sitio al vencer, sin relación con la validez del certificado público. Hallazgo fuera del alcance original de este ticket. | Alto |
| H6 | El certificado `www.clubgrido.com.py_2026_v2` quedó huérfano en el gateway tras el corte del listener al objeto respaldado por Key Vault — no está vinculado a ningún listener actualmente. | Bajo |

## Recursos afectados

| Recurso | Rol |
|---|---|
| `WAF_APPs` | Application Gateway — listener público (`Listener_ClubSite_HTTPS_PY`) y HTTP settings del backend (`Backend_ClubSite_PY`) |
| `sfcg-waf-apps-kv` | Key Vault compartido (creado en `GITIN-1770`) — ahora también almacena `www-clubgrido-com-py` |
| `waf-apps-kv-identity` | Managed Identity del gateway, ya existente — sin cambios en este ticket |
| `_acme-challenge.www.clubgrido.com.py` | Zona Azure DNS nueva, delegada desde `clubgrido.com.py` vía IT Grido |
| Service Principal `winacme-mobileservice-dns` (appId `3cca7e2a-...`) | Reutilizado de `GITIN-1774`/`GITIN-1770`, con un nuevo `DNS Zone Contributor` sobre la zona nueva — `Key Vault Certificates Officer` ya cubría este vault desde `GITIN-1770` |
| `SFCG-CLUB-01` | Backend #1 de ClubSite — corre win-acme, entrega al Key Vault (certificado público) y al almacén de certificados local + binding IIS (certificado de backend) |
| `SFCG-CLUB-02` | Backend #2 de ClubSite — corre win-acme de forma independiente, entrega al almacén de certificados local + binding IIS (certificado de backend) |
| `www-clubgrido-com-py-kv` | Objeto ssl-cert nuevo en `WAF_APPs`, referencia el secret de Key Vault sin versión |

## Comandos ejecutados

| # | Comando / Script | Propósito |
|---|---|---|
| C1-C2 | `az network dns zone create` / `show` | ⚠️ Crear la zona Azure DNS y obtener nameservers |
| — | Correo a Jordan (IT Grido) (`email_ops.md`) | ⚠️ Pedir el registro NS de delegación (sin acceso directo al dominio) |
| — | `dig NS _acme-challenge.www.clubgrido.com.py` | Confirmar la delegación de forma independiente, no solo por el reporte recibido |
| C3 | `az role assignment create` | ⚠️ Otorgar `DNS Zone Contributor` al Service Principal sobre la zona nueva |
| C4a-C7 | `openssl s_client` / `az network application-gateway show` | Diagnóstico de red y de objetos de confianza del gateway (ver H4) |
| C8-C12g | `Get-WebBinding` / inspección de cadena de certificados / `Get-ScheduledTask` / archivos `.renewal.json` en `SFCG-CLUB-01` | Confirmar el hallazgo H4 y H5 (certificado de backend sin renovación automática) |
| C13 | `az role assignment list` | Confirmar permiso `Key Vault Certificates Officer` ya existente sobre el vault |
| C14 | Instalación/wizard win-acme en `SFCG-CLUB-01` | ⚠️ Emitir certificado combinado (público → Key Vault, backend → almacén local + binding IIS) |
| C15-C16 | `az keyvault certificate show` / `show-backend-health` | Verificar la subida a Key Vault y la salud del backend tras el cambio |
| C17 | Verificación manual del certificado servido por el WAF | Confirmar que el listener público seguía sin migrar |
| C18-C20 | `az network application-gateway ssl-cert create` + `http-listener update` | ⚠️ Cortar el listener al objeto respaldado por Key Vault |
| C21-C22 | Wizard win-acme en `SFCG-CLUB-02` (solo backend) | ⚠️ Emitir e instalar el certificado de backend de forma independiente en el segundo nodo |
| C24-C26 | Inspección de `.renewal.json` en ambos hosts | Confirmar que ambas instalaciones de win-acme en `SFCG-CLUB-02` comparten la misma ruta de configuración (sin laguna de renovación) |
| C23 | `az network application-gateway show-backend-health` | Confirmar redundancia completa restaurada en ambos nodos |

Detalle completo en `scripts.sh`.

## Acciones propuestas

1. **(SRE, ya aplicada)** Migrar el certificado público del listener a Key Vault con URI de secret sin versión, para que el gateway recoja automáticamente futuras rotaciones sin reconfiguración manual.
2. **(SRE, ya aplicada)** Automatizar la renovación DNS-01 del certificado público desde `SFCG-CLUB-01`, verificada end-to-end en el endpoint público sin downtime.
3. **(SRE, ya aplicada)** Automatizar el certificado del backend en `SFCG-CLUB-01` y `SFCG-CLUB-02` (hallazgo H5) — emitido, instalado, `Backend_ClubSite_PY` saludable en ambos nodos.
4. **(SRE, pendiente)** Confirmar que el primer ciclo de renovación real (no forzado) se ejecute correctamente en ambos nodos — próximo vencimiento 2026-11-03.
5. **(SRE, pendiente de decisión)** Definir si se limpia el certificado huérfano `www.clubgrido.com.py_2026_v2` del gateway o se deja como respaldo temporal — misma decisión pendiente en `GITIN-1770` para `clubgrido.2023.2024`.
6. **(SRE, pendiente, baja prioridad)** Confirmar el proveedor DNS real de `clubgrido.com.py` — no bloqueante, la delegación ya funciona independientemente de cuál sea.

## Hallazgos secundarios

- `GITIN-1771` (WebSite) permanece sin iniciar — mismo patrón de automatización aplicaría, no verificado si `gestion.clubgrido.com.ar` comparte el mismo tipo de acceso DNS ni si su gateway hace re-encriptación end-to-end hacia el backend.
