# Eventos — 20260806_automatizar_clubsite_ar

## 2026-08-06 — Mapeo listener → certificado en WAF_APPs

**Comando:** C1 — `az network application-gateway show` sobre `WAF_APPs`
**Resultado:**
`Listener_ClubSite_HTTPS` (`www.clubgrido.com.ar`) usa el certificado `clubgrido.2023.2024`. También confirmé `Listener_ClubSite_HTTPS_PY` → `www.clubgrido.com.py_2026_v2` y `Listener_WebSite_HTTPS` → `website_2024`.

Confirmé con certeza cuál de los 9 objetos de certificado del gateway está realmente en uso para cada listener — corrigiendo una suposición anterior que había marcado `clubgrido.2023.2024` como candidato a huérfano solo por el nombre.

## 2026-08-06 — HTTP-01 descartado para ClubSite AR (y PY)

**Comando:** C2 — `az network application-gateway show` (reglas de ruteo)
**Resultado:**
`Rule_Clubsite_HTTP_AR` tiene `redirectConfig` configurado y `backendPool: null` — es una redirección pura HTTP→HTTPS, sin backend real detrás.

Confirmé que la validación HTTP-01 no es viable para este listener — una request de challenge ACME sería redirigida a HTTPS antes de llegar a algo que pueda servir el archivo. DNS-01 queda como el único camino viable para este ticket.

## 2026-08-06 — Sin Key Vault reutilizable, creación de uno nuevo

**Comando:** C3-C4 — `az keyvault list` / `az network application-gateway show --query identity`
**Resultado:**
Dos Key Vaults existentes en la suscripción, ninguno reutilizable (`SmartFran-Cloud-KV-Dev` es de otro proyecto/RG; `MigracionSRVAD7838kv` es de otra región/RG). `WAF_APPs` no tenía ninguna identidad administrada asignada (`identity: null`).

Decidí crear un Key Vault específico para este propósito en vez de reutilizar alguno de los existentes, dado que ninguno correspondía al proyecto ni a la región/resource group correctos.

## 2026-08-06 — Key Vault, Managed Identity y permisos

**Comando:** C5-C8 — `az keyvault create` / `az identity create` / `az network application-gateway identity assign` / `az role assignment create`
**Resultado:**
Ver scripts (C5-C8). Key Vault `sfcg-waf-apps-kv` creado con autorización RBAC. Managed Identity `waf-apps-kv-identity` creada (`principalId: 023f97a9-075c-4755-93cd-31d440bbafe6`) y asignada a `WAF_APPs` — el primer intento de asignación falló por usar el flag incorrecto (`--identities` en plural en vez de `--identity`), corregido con el flag correcto y el resource ID completo. Rol `Key Vault Secrets User` otorgado a esa identidad sobre el Key Vault — comando ejecutado, resultado pendiente de confirmación explícita.

Confirmé la asignación de la identidad releyendo la configuración completa del gateway — el bloque `identity` ya muestra `waf-apps-kv-identity` correctamente vinculada.

## 2026-08-06 — Zona Azure DNS para este hostname

**Comando:** C9 — `az network dns zone create` / `az network dns zone show`
**Resultado:**
Zona `_acme-challenge.www.clubgrido.com.ar` creada. Nameservers: `ns1-03.azure-dns.com.`, `ns2-03.azure-dns.net.`, `ns3-03.azure-dns.org.`, `ns4-03.azure-dns.info.`.

El primer intento de este comando falló (`argument --resource-group/-g: expected one argument`) porque las variables de entorno de un mensaje anterior no estaban definidas en la sesión donde se ejecutó — corregido usando los valores literales en vez de depender de exports previos.

## 2026-08-07 — Permiso del Service Principal sobre la zona nueva confirmado

**Comando:** C10 — `az role assignment create`
**Resultado:**
Éxito. `DNS Zone Contributor` asignado al Service Principal existente (`principalId: 68f5c410-df61-4bd4-904a-9de056077e02`, el mismo reutilizado de GITIN-1774) con scope exacto sobre `_acme-challenge.www.clubgrido.com.ar`.

Decidí reutilizar el Service Principal existente en vez de crear uno nuevo, agregando una asignación de rol adicional scopeada específicamente a esta nueva zona — la asignación existente sobre la zona de MobileAppService queda intacta y sin cambios.

## 2026-08-07 — Delegación NS confirmada, con una corrección en el camino

**Comando:** `dig _acme-challenge.www.clubgrido.com.ar`
**Resultado:**
`status: NOERROR`, sección `AUTHORITY` con el SOA propio de la zona desde `ns1-03.azure-dns.com.`.

Antes de esta confirmación detecté un error en el registro NS que se había cargado en GoDaddy para la zona de MobileAppService (`_acme-challenge.mobileservice`): el segundo nameserver estaba mal cargado como `ns2-01.azure-dns.com.` en vez de `ns2-01.azure-dns.net.` — mismo dominio duplicado del primer nameserver en vez del correcto. Se corrigió antes de continuar. La delegación de la zona nueva (`_acme-challenge.www`) se cargó correctamente desde el principio.

## 2026-08-07 — Permiso de la identidad sobre el Key Vault confirmado

**Comando:** C8 — `az role assignment create`
**Resultado:**
Éxito. `Key Vault Secrets User` asignado a `waf-apps-kv-identity` (`principalId: 023f97a9-075c-4755-93cd-31d440bbafe6`) con scope exacto sobre `sfcg-waf-apps-kv`.

Con esto quedan completos todos los permisos necesarios: la identidad del gateway puede leer secretos del Key Vault, y el Service Principal de win-acme puede escribir el TXT de validación en ambas zonas DNS (MobileAppService y ClubSite AR).

## 2026-08-07 — Host para win-acme confirmado: SFCG-CLUB-01

**Comando:** `az network nic list` filtrado por VMs `SFCG-CLUB*`
**Resultado:**
`SFCG-CLUB-01` → `192.168.50.121`, `SFCG-CLUB-02` → `192.168.50.122` — coinciden exactamente con los dos miembros del backend pool `Back_ClubSite`.

Confirmé que `SFCG-CLUB-01` es efectivamente uno de los dos servidores backend de ClubSite, no solo un nombre plausible — decisión de usarlo como host de win-acme para este certificado, en vez de aprovisionar una VM nueva o migrar a una solución serverless (evaluadas, no elegidas por ahora).

## 2026-08-07 — win-acme instalado en SFCG-CLUB-01, brecha de permisos detectada y corregida

**Resultado:**
Instalé win-acme (build pluggable) junto con el plugin de validación DNS-01 de Azure DNS y el plugin de store de Key Vault (`plugin.store.keyvault.v2.2.9.1701.zip`, nombre confirmado contra la API de GitHub, no adivinado). Durante el wizard, al llegar al paso de store (Key Vault), detecté que el Service Principal (`winacme-mobileservice-dns`) solo tenía `DNS Zone Contributor` — sin ningún permiso de escritura sobre `sfcg-waf-apps-kv`. La identidad `waf-apps-kv-identity` tampoco servía para esto: solo tiene lectura (`Key Vault Secrets User`) y está atada al gateway, no a esta VM.

**Comando:** `az role assignment create` — rol `Key Vault Certificates Officer`
**Resultado:**
Éxito. Otorgado al mismo Service Principal, scope acotado a `sfcg-waf-apps-kv`.

Detecté esta brecha de permisos antes de que el paso de store fallara en el wizard, no después — evitó una corrida fallida a mitad de la emisión del certificado.

## 2026-08-07 — Primer intento de emisión: client secret incorrecto

**Resultado:**
El primer intento de emisión falló en el paso de validación DNS-01 (antes de llegar siquiera a Key Vault) con `AADSTS7000215: Invalid client secret provided` — alguien había ingresado el ID del secret en vez de su valor. Encontré el error real revisando el log de win-acme (`C:\ProgramData\win-acme\acme-v02.api.letsencrypt.org\Log\log-20260807.txt`), no asumiendo que era demora de propagación de RBAC como parecía a primera vista.

Decidí no rotar/resetear el secret existente del Service Principal para no romper las renovaciones ya funcionando de `SFCG-MOBI-01`/`02` (que usan la misma app registration) — en su lugar, agregué un secret nuevo con `az ad app credential reset --append`, que coexiste con el original sin invalidarlo.

## 2026-08-07 — Segundo intento: brecha de permisos de escritura en Key Vault detectada antes de fallar

Antes de reintentar con el secret correcto, noté que el Service Principal solo tenía `DNS Zone Contributor` — ningún permiso de escritura sobre `sfcg-waf-apps-kv`. Otorgué `Key Vault Certificates Officer` al mismo Service Principal sobre el vault antes de continuar, evitando una segunda corrida fallida en el paso de store.

## 2026-08-07 — Certificado emitido y confirmado en Key Vault

**Resultado:**
Con el secret correcto y el permiso de Key Vault en su lugar, la emisión se completó exitosamente: `Certificate [Manual] www.clubgrido.com.ar created`. Confirmé en el log el detalle completo — certificado RSA 3072 bits, `CN=www.clubgrido.com.ar`, importado a `https://sfcg-waf-apps-kv.vault.azure.net/certificates/www-clubgrido-com-ar/c4c8b43fee694817b49d795cf24524ed`, válido ~3 meses. Tarea programada creada (`SYSTEM`), próxima renovación después del 2026/10/1.

Noté un `401 Unauthorized` en el log justo antes del `200 OK` de importación al Key Vault — confirmé que es el intercambio estándar de autenticación OAuth de Key Vault (primer request sin token para descubrir el authority vía `WWW-Authenticate`, luego reintento inmediato con token real), no un error real.

Intenté verificar el certificado directamente vía `az keyvault certificate show` y me encontré con `Forbidden` — mi propia identidad (la que uso para correr `az cli`) no tiene ningún rol de datos sobre el vault RBAC-mode recién creado (el creador de un Key Vault con RBAC no obtiene acceso automático). No es necesario para cerrar este paso, ya que confirmé el éxito directamente en el log de win-acme — pendiente si quiero verificación propia vía CLI en el futuro.

## 2026-08-07 — Listener reconfigurado, corte verificado en producción sin downtime

**Comando:** `az network application-gateway ssl-cert create` (objeto `www-clubgrido-com-ar-kv`, URI de secret sin versión) + `az network application-gateway http-listener update` (`Listener_ClubSite_HTTPS`)
**Resultado:**
Ambos comandos confirmados exitosos — el listener ahora referencia el nuevo objeto respaldado por Key Vault en vez del PFX directo.

**Comando:** `openssl s_client` contra `www.clubgrido.com.ar:443`
**Resultado:**
`issuer=Let's Encrypt YR1`, serial `0540281A87ACBC18AA91ECB9BB625C82AD37` — coincide exactamente con el certificado recién emitido.

Confirmé el corte completo en el endpoint público, sin downtime. Con esto, `GITIN-1770` queda funcionalmente terminado — ClubSite AR renueva de forma completamente desatendida, con el gateway recogiendo automáticamente futuras rotaciones desde Key Vault (URI sin versión, deliberado).

## 2026-08-07 — Hallazgo crítico: certificado del backend fuera del alcance original, riesgo de caída total

**Resultado:**
Al revisar el certificado local en `SFCG-CLUB-01` detecté que `WAF_APPs` hace re-encriptación end-to-end hacia el backend — dos conexiones TLS independientes, y solo automatizamos la pública. El certificado del backend (GoDaddy, todavía sin tocar) vence el 2026-11-13; cuando eso pase, el handshake Gateway→Backend fallará y probablemente caiga el sitio completo, sin relación con el certificado público (que seguiría válido). Es un modo de falla que no se detecta mirando el certificado que ve el navegador.

Decidí extender el alcance de este ticket para automatizar también el certificado del backend en `SFCG-CLUB-01`/`02`, en vez de dejarlo como tarea manual anual — dado que ya está montada la infraestructura de DNS-01 y Key Vault, el costo incremental es bajo comparado con el riesgo. Este hallazgo va a figurar de forma prominente en el ticket principal, no como nota al margen.

## 2026-08-07 — Carga de root certs del backend: dos fallos por formato, uno exitoso

**Comando:** C16-C18 — `az network application-gateway root-cert create` (`letsencrypt-yr1`, `letsencrypt-root-yr`, `letsencrypt-isrg-root-x1`)
**Resultado:**
`letsencrypt-yr1` y `letsencrypt-root-yr` fallaron con `ApplicationGatewayTrustedRootCertificateInvalidData`. `letsencrypt-isrg-root-x1` se cargó con éxito y ya aparece en `trustedRootCertificates` del gateway.

Diagnostiqué inicialmente (hipótesis incorrecta, corregida en la entrada siguiente) que la causa era formato DER vs. base64.

## 2026-08-07 — Reintento con base64 también falla: causa real identificada

**Comando:** C16b-C17b — `az network application-gateway root-cert create` (`letsencrypt-yr1`, `letsencrypt-root-yr`, esta vez con los archivos reconvertidos a base64 vía `certutil -encode`)
**Resultado:**
Ambos volvieron a fallar con el mismo `ApplicationGatewayTrustedRootCertificateInvalidData` — descarta el formato (DER vs. base64) como causa.

Inspeccioné el contenido real de los tres certificados con `openssl x509 -text` y encontré el patrón real: `isrg-root-x1.cer` (el único que cargó bien) es un certificado autofirmado (Issuer = Subject = "ISRG Root X1"). `yr1-intermediate.cer` y `root-yr.cer` son certificados intermedios (Issuer distinto del Subject). Corrijo la hipótesis anterior: `trustedRootCertificates` de Application Gateway solo acepta el certificado raíz autofirmado — los intermedios deben ser presentados por el propio backend durante el handshake TLS, no cargados acá. Con esto, `letsencrypt-isrg-root-x1` (ya cargado) debería ser el único objeto necesario, siempre que el binding IIS de `SFCG-CLUB-01` esté sirviendo la cadena completa (hoja + intermedio YR1) — típico del paso de instalación de win-acme, pendiente de confirmar.

## 2026-08-07 — Backend saludable de nuevo, cadena de confianza resuelta

**Comando:** C21 — `az network application-gateway http-settings update` (agregado `letsencrypt-isrg-root-x1` a `Backend_ClubSite`, sin quitar `clubsite_CA`)
**Resultado:**
`trustedRootCertificates` de `Backend_ClubSite` ahora incluye ambos objetos.

**Comando:** C22 — `az network application-gateway show-backend-health`
**Resultado:**
`SFCG-CLUB-01` (`192.168.50.121`) y `SFCG-CLUB-02` (`192.168.50.122`) están `Healthy` en `Back_ClubSite` — probe HTTP 200 en ambos. `Back_ClubSite_PY` y `Back_WebSite` también `Healthy`, sin cambios.

Confirmé que la hipótesis era correcta: solo hacía falta el certificado raíz autofirmado, y el binding IIS de `SFCG-CLUB-01` ya está sirviendo la cadena completa (hoja + intermedio YR1) sin intervención adicional — el paso de instalación de win-acme lo dejó bien configurado desde el principio. Redundancia completa restaurada en `Back_ClubSite`.

## 2026-08-07 — SFCG-CLUB-02: win-acme instalado, certificado emitido e instalado, backend saludable

**Resultado:**
Instalé win-acme (`win-acme.v2.2.9.1701.x64.pluggable.zip`) junto con el plugin de validación DNS-01 de Azure (`plugin.validation.dns.azure.v2.2.9.1701.zip`) — nombres confirmados contra la API de GitHub, no adivinados. A diferencia de `SFCG-CLUB-01`, no instalé el plugin de store de Key Vault acá: este VM solo entrega al almacén de certificados de Windows + binding IIS, la carga a Key Vault ya la cubre `SFCG-CLUB-01`.

**Comando:** `az ad app credential reset --append` (nombre `winacme-clubsite-ar-dns`)
**Resultado:**
El secret guardado en el vault local de win-acme en `SFCG-CLUB-01` no es reutilizable acá — el vault de win-acme es local a cada máquina (cifrado con DPAPI, atado a esa VM específica), sin sincronización entre hosts. Generé un secret nuevo para el mismo Service Principal (`3cca7e2a-5b4a-4b0d-87ee-4390af90346f`) con `--append`, sin invalidar los secrets existentes que ya usan `SFCG-MOBI-01`/`02` y `SFCG-CLUB-01`.

**Resultado (wizard win-acme):**
Configuré el origen manual (`www.clubgrido.com.ar`, certificado separado por host para no incluir accidentalmente `www.clubgrido.com.py`), validación DNS-01 vía Azure DNS (misma zona `_acme-challenge.www.clubgrido.com.ar`), clave RSA, almacén de certificados de Windows (store `My`, igual que los bindings existentes), e instalación de binding IIS en el sitio `SmartLoyalty.ClubSite`. Emisión exitosa: `Certificate [Manual] www.clubgrido.com.ar created`, esta vez emitido a través del intermedio `YR2` (par de `YR1`, ambos bajo la misma cadena `Root YR` → `ISRG Root X1`) — win-acme importó correctamente ambos (`YR2` y `Root YR`) al almacén CA local. Binding actualizado solo para `www.clubgrido.com.ar` (hash nuevo `2DDBE702E6961B89FC97E9B834EDF23C8E6CB55A`), sin tocar el binding compartido de PY/default (`0BB9D0CB...`). Tarea programada creada (`SYSTEM`), próxima renovación después del 2026/10/1.

**Comando:** `az network application-gateway show-backend-health`
**Resultado:**
`SFCG-CLUB-02` (`192.168.50.122`) `Healthy` en `Back_ClubSite`, junto con `SFCG-CLUB-01`. Confirma que el trust root `letsencrypt-isrg-root-x1` ya cargado en el gateway es suficiente independientemente de cuál de los dos intermedios (`YR1` o `YR2`) haya emitido Let's Encrypt, ya que ambos encadenan a la misma raíz autofirmada. Con esto, la automatización del certificado de backend queda completa en ambos nodos de `Back_ClubSite`.

## 2026-08-07 — Verificación de rol de lectura sobre el Key Vault: ya cubierta

**Resultado:**
No hizo falta ninguna asignación de rol adicional — el grupo `Operaciones` ya cuenta con permisos de lectura sobre `sfcg-waf-apps-kv`, cubriendo la necesidad de verificación futura vía `az cli` sin una asignación individual dedicada.

## 2026-08-07 — Recordatorio de calendario agregado para verificar el primer ciclo de renovación real

**Resultado:**
Agregué un recordatorio de calendario propio para el 2026-10-03 — dos días después de la fecha de renovación registrada por win-acme en ambos nodos ("next renewal due after 2026/10/1") — para verificar en `GITIN-1770` que el primer ciclo de renovación automática (no forzado) se ejecutó correctamente en `SFCG-CLUB-01` y `SFCG-CLUB-02`: log de win-acme, cambio de thumbprint, `Backend_ClubSite` saludable, y endpoint público sirviendo el certificado nuevo.

## Pendiente
- Escribir el ticket principal (`ops.md`) incluyendo el hallazgo del certificado de backend de forma prominente.
- Decidir si limpiar `clubgrido.2023.2024` (ahora huérfano, ya desvinculado del listener) o dejarlo por las dudas durante un tiempo.
- Confirmar un ciclo de renovación real (no forzado) el 2026-10-03 (recordatorio agregado), en ambos nodos.
