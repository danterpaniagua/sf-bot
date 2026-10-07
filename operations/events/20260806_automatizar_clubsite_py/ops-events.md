# Eventos — 20260806_automatizar_clubsite_py

## 2026-09-01 09:00 — Retomada la investigación: decisión de camino para superar el bloqueo de acceso DNS

No tengo acceso administrativo a `clubgrido.com.py`, así que he decidido avanzar igual con el lado de Azure DNS del mecanismo DNS-01 y pedir el registro de delegación NS por correo a quien administra ese dominio, en vez de esperar a resolver el acceso directo.

## 2026-09-01 09:05 — Zona de Azure DNS creada para el subdominio del challenge

**Comando:** C1 — crear zona Azure DNS `_acme-challenge.www.clubgrido.com.py`
**Resultado:**
Zona creada correctamente (`zoneType: Public`, `numberOfRecordSets: 2`, solo SOA/NS por defecto).

He confirmado que la zona quedó creada sin inconvenientes, con el mismo patrón que he usado en GITIN-1774 y GITIN-1770.

## 2026-09-01 09:06 — Nameservers asignados por Azure obtenidos

**Comando:** C2 — obtener nameservers de la zona
**Resultado:**
ns1-07.azure-dns.com.
ns2-07.azure-dns.net.
ns3-07.azure-dns.org.
ns4-07.azure-dns.info.

Tengo los 4 nameservers que necesito para armar el pedido de delegación.

## 2026-09-01 09:10 — Correo de solicitud de delegación a Jordan (IT Grido) redactado

He redactado el correo (`email_ops.md`) pidiendo el registro NS `_acme-challenge.www` bajo `clubgrido.com.py` apuntando a los 4 nameservers de Azure. Todavía no lo he enviado ni he confirmado que Jordan lo haya recibido.

## 2026-09-01 09:15 — Correo enviado, queda a la espera de la respuesta de Jordan

He enviado el correo de solicitud de delegación a Jordan (IT Grido). He pausado este ticket hasta que confirme el registro NS agregado.

## 2026-09-08 16:05 — IT Grido reporta la creación de la delegación

IT Grido reportó haber agregado el registro NS de delegación solicitado. No he tratado este reporte como confirmado sin verificarlo — he pedido una consulta `dig` independiente antes de dar el bloqueo por resuelto.

## 2026-09-08 16:08 — Delegación NS confirmada de forma independiente

He verificado la delegación vía `dig NS _acme-challenge.www.clubgrido.com.py` (`data/dig_ns_delegation_check.txt`): los 4 nameservers de Azure (`ns1-07.azure-dns.com.`, `ns2-07.azure-dns.net.`, `ns3-07.azure-dns.org.`, `ns4-07.azure-dns.info.`) resuelven correctamente. He confirmado que DNS-01 ya no está bloqueado por acceso al dominio. He actualizado `ops.md` (H1 resuelto, Resuelto: Parcial) y dejado como pendientes la decisión de entrega del certificado (Key Vault vs. PFX) y el host desde el que correrá win-acme.

## 2026-09-09 08:44 — Asignación de rol `DNS Zone Contributor` creada sobre la zona PY

**Comando:** C3 (`scripts.sh`) — `az role assignment create`, mismo Service Principal reutilizado de GITIN-1774/GITIN-1770 (`appId 3cca7e2a-5b4a-4b0d-87ee-4390af90346f`), scopeado únicamente a la zona `_acme-challenge.www.clubgrido.com.py`.
**Resultado:**
Asignación creada correctamente (`data/role_assignment_create.json`): `roleDefinitionId befefa01-2a29-4197-83a8-272ff33ce314` (DNS Zone Contributor), `principalId 68f5c410-df61-4bd4-904a-9de056077e02`, scope confirmado limitado a la zona PY.

He confirmado que el Service Principal ya tiene el permiso necesario para completar la validación DNS-01 en la zona de PY. Sigue pendiente correr el wizard de win-acme en `SFCG-CLUB-01` (runbook §4.5) y entender por qué `Backend_ClubSite_PY.trustedRootCertificates` está en `null` antes de tocar la pata del backend (runbook §6).

## 2026-09-09 — Listado de objetos raíz confiables del gateway, dos candidatos específicos de PY sin adjuntar

**Comando:** C7 (`scripts.sh`) — `az network application-gateway show --query "trustedRootCertificates[].name"`
**Resultado:**
5 objetos: `clubsite_CA`, `www.ca.py`, `2023.gestion.clubgrido_CA`, `clubgrido_PY_2024_CA_ROOT`, `letsencrypt-isrg-root-x1` (`data/gateway_trusted_root_names.txt`).

He confirmado que existen dos objetos específicos de PY (`www.ca.py`, `clubgrido_PY_2024_CA_ROOT`) que no están adjuntados a `Backend_ClubSite_PY` (su `trustedRootCertificates` sigue en `null`). No he determinado todavía si son objetos huérfanos (como los 6 certificados PFX huérfanos ya encontrados en este gateway) o si son referencias obsoletas. Sigo bloqueado para confirmar el emisor real del certificado del backend de PY — el intento de inspeccionarlo remotamente vía `openssl s_client` desde fuera de la red `192.168.50.x` no tuvo éxito (posible bloqueo de red, sin respuesta clara todavía sobre si hay alcance).

## 2026-09-09 — Inspección local en SFCG-CLUB-01: causa del `trustedRootCertificates: null` resuelta, y hallazgo urgente sin relación al bloqueador original

**Comando:** C8–C10 (`scripts.sh`) — `Get-WebBinding`, `Get-ChildItem Cert:\LocalMachine\My\...`, construcción de cadena completa vía `X509Chain`, ejecutados directamente en `SFCG-CLUB-01` por acceso RDP/PowerShell (la inspección remota vía `openssl` no era viable por falta de alcance de red a `192.168.50.x`).
**Resultado:**
El binding `www.clubgrido.com.py` usa el hash `0BB9D0CBDB426A421C162EE71B59A39F4A43DBB9` (store `My`), un certificado **ya emitido por Let's Encrypt** (`CN=www.clubgrido.com.py`, emisor `YE2`), cadena completa: hoja → YE2 → Root YE → ISRG Root X2 → ISRG Root X1 (raíz autofirmada). Vence el 2026-09-15.

He confirmado que esto explica el `trustedRootCertificates: null`: la raíz `ISRG Root X1` es una CA pública reconocida que Application Gateway v2 confía por defecto cuando no hay un objeto de confianza explícito — no hay ninguna laguna ni objeto huérfano involucrado, y `www.ca.py`/`clubgrido_PY_2024_CA_ROOT` no tienen relación con este binding.

**Hallazgo urgente, sin relación al bloqueador original de este ticket:** este certificado fue emitido el 6/17/2026, antes de que arrancara la épica `GITIN-1768` (2026-08-06) — no fue emitido por ninguna automatización de este proyecto. He verificado si la Scheduled Task `win-acme renew (acme-v02.api.letsencrypt.org)` en este mismo host lo cubre, dada la hipótesis de que podría hacerlo por compartir la VM con AR — **descartada**: el único archivo de renovación existente en `C:\ProgramData\win-acme\acme-v02.api.letsencrypt.org\` (`SwTuz4cBaEqYqmX6WK7cCw.renewal.json`) apunta únicamente a `www.clubgrido.com.ar`. **El certificado del backend de PY no tiene ninguna renovación automática configurada y vence en 6 días.**

Este hallazgo pasa a tener prioridad sobre el trabajo original de DNS-01/certificado público de este ticket, por el mismo patrón de riesgo de caída total que motivó la sección 6 del runbook en `GITIN-1770`.

## 2026-09-09 — Wizard de win-acme ejecutado en SFCG-CLUB-01: certificado combinado (público + backend) emitido y validado

**Comando:** C14 (`scripts.sh`) — wizard interactivo de win-acme (`data/py_backend_winacme_wizard_output.txt`), origen manual `www.clubgrido.com.py`, validación Azure DNS (credencial reutilizada `winacme-clubsitear-dns`), doble destino (Key Vault `sfcg-waf-apps-kv` + Windows Certificate Store `My`), instalación de binding IIS en `SmartLoyalty.ClubSite`.
**Resultado:**
Validación DNS-01 exitosa (1 reintento por propagación, normal). Certificado instalado en el store local `My` y binding `www.clubgrido.com.py:443` actualizado — solo 1 binding modificado, confirmando que el binding por defecto (sin SNI) no fue tocado. Tarea de renovación creada, próxima el 2026/11/3.

He verificado directamente (no asumido) la línea ambigua "KeyVault... Unauthorized" del log — **confirmado correcto**: `data/py_keyvault_cert_check.json` muestra el certificado `www-clubgrido-com-py` habilitado en el vault, vence 2026-12-08. El mismo patrón de 401 benigno que documentó `GITIN-1770`, no una falla real.

He verificado el estado de salud del backend después del cambio (`data/backend_health_after_py_reissue.json`): `SFCG-CLUB-01` (192.168.50.121) está `Healthy` en las tres pools (`Back_ClubSite`, `Back_ClubSite_PY`, `Back_WebSite`). `SFCG-CLUB-02` (192.168.50.122) está `Unhealthy` en `Back_ClubSite` y `Back_ClubSite_PY` — he confirmado que es intencional: IIS quedó caído en `.122` a la espera de actualizar su propio certificado, mismo criterio que el pase independiente de `GITIN-1770` sobre `.02` para AR (emisión propia, sin Key Vault). Queda pendiente repetir el mismo flujo de win-acme (solo backend) en `.122`.

## 2026-09-09 — Listener público migrado a Key Vault: automatización del certificado público completa (nodo .121)

He confirmado, verificando directamente en el WAF, que el certificado actual del listener público todavía mostraba las fechas del certificado viejo (No antes 17/6/2026, No después 15/9/2026) — el mismo vencimiento que tenía el certificado del backend antes de C14. Esto confirmó que `Listener_ClubSite_HTTPS_PY` nunca había sido migrado del objeto PFX directo (`www.clubgrido.com.py_2026_v2`), y que el riesgo de vencimiento en 6 días también afectaba el lado público, no solo el backend.

**Comando:** C18 — `az network application-gateway ssl-cert create`, objeto `www-clubgrido-com-py-kv` referenciando el secret de Key Vault por su URI **sin versión** (para que el gateway recoja renovaciones futuras automáticamente).
**Resultado:** creado correctamente (`data/gateway_ssl_cert_create.json`), `keyVaultSecretId` confirmado sin versión.

**Comando:** C19 — `az network application-gateway http-listener update`, redirige `Listener_ClubSite_HTTPS_PY` al nuevo objeto.
**Resultado:** actualizado correctamente (`data/gateway_listener_update.json`), `sslCertificate.id` ahora apunta a `www-clubgrido-com-py-kv`, `hostName` sin cambios.

He confirmado que la migración del certificado público quedó completa para el nodo `.121`. El objeto PFX viejo (`www.clubgrido.com.py_2026_v2`) queda huérfano — misma decisión pendiente que `GITIN-1770` dejó abierta para `clubgrido.2023.2024` (limpiar vs. dejar como respaldo temporal), no decidida todavía.

## 2026-09-09 — SFCG-CLUB-02: certificado de backend automatizado, redundancia completa restaurada

**Comando:** C21 (`scripts.sh`) — wizard de win-acme en `SFCG-CLUB-02`, solo backend (sin Key Vault, ese secret ya está cubierto por `.01`): origen manual `www.clubgrido.com.py`, validación Azure DNS (credencial reutilizada `winacme-clubsite-ar-dns`, guardada en este mismo host durante `GITIN-1770`), store Windows Certificate Store (`My`), instalación de binding IIS en `SmartLoyalty.ClubSite`.

He encontrado dos obstáculos durante la ejecución: (1) IIS estaba detenido en este host, deliberadamente, a la espera de esta actualización — el wizard reportó "No IIS sites detected" incluso después de reiniciar el servicio `W3SVC`, porque el proceso `wacs.exe` ya había cacheado el estado "sin sitios" al arrancar; se resolvió abortando y reiniciando el wizard desde cero. (2) Un error de tipeo envió literalmente el texto `host www.clubgrido.com.py` como hostname; se resolvió reintentando con el valor correcto.

**Resultado:** certificado emitido correctamente, binding `www.clubgrido.com.py:443` actualizado a un hash nuevo (`E6F1914274B020010A09E08FB9DC27A86E9721BB`), el binding por defecto y el de AR quedaron sin cambios (verificado con `Get-WebBinding`). Renovación agregada, próxima el 2026/11/3.

**Antes de dar esto por cerrado, surgió un riesgo real a verificar:** la tarea programada existente en este host (creada para AR en `GITIN-1770`) apunta a `C:\ProgramData\win-acme\wacs.exe`, pero el wizard de PY se ejecutó desde un binario distinto, `C:\win-acme\wacs.exe`. He verificado directamente (no asumido) si esto generaba una laguna de renovación: ambos binarios tienen `ConfigurationPath: null` en su `settings.json`, y ambas instalaciones resuelven a la misma carpeta de configuración por defecto (`C:\ProgramData\win-acme\acme-v02.api.letsencrypt.org\`) — confirmado listando los `.renewal.json` presentes ahí y verificando por `CommonName` cuál corresponde a cada hostname. **No hay laguna**: la tarea programada existente cubrirá la renovación de PY igual que la de AR.

He verificado el estado de salud del backend después del arreglo (`data/backend_health_after_02_fix.json`): `SFCG-CLUB-01` y `SFCG-CLUB-02` están `Healthy` en las tres pools (`Back_ClubSite`, `Back_ClubSite_PY`, `Back_WebSite`). Redundancia completa restaurada.

**El trabajo técnico de `GITIN-1769` está completo.** Pendiente: decidir sobre el objeto PFX huérfano (`www.clubgrido.com.py_2026_v2`); confirmar un ciclo de renovación real (no forzado) más adelante (próximo: 2026/11/3); escribir `ops.md`.
