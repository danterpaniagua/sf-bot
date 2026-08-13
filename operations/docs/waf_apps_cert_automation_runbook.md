# Runbook — Automatización de certificados SSL en `WAF_APPs` (Key Vault + Application Gateway)

> Origen: historia `GITIN-1768`. Primer caso implementado y **completo**: `GITIN-1770` (ClubSite AR), evento `operations/events/20260806_automatizar_clubsite_ar/` — cubre tanto el certificado público (sección 4) como el certificado del backend (sección 6, agregado tras un hallazgo crítico fuera del alcance original). Diseñado para reutilizarse en `GITIN-1769` (ClubSite PY, bloqueado — ver "Notas" abajo) y `GITIN-1771` (WebSite) — **verificar en ambos si el gateway también hace re-encriptación end-to-end hacia su backend**, ya que de ser así aplica también la sección 6, no solo la 4.

## 1. Objetivo

Automatizar la renovación de certificados SSL para los hostnames servidos por el Application Gateway/WAF `WAF_APPs`, sin depender de una carga manual de PFX en cada ciclo. A diferencia de MobileAppService (`operations/docs/mobileappservice_ssl_renewal_runbook.md`), acá el certificado vive en **Azure Key Vault**, no en el store local de una VM — el gateway lo recoge automáticamente al rotar de versión.

## 2. Topología relevante

- **Application Gateway `WAF_APPs`** (WAF_v2, resource group `DefaultGroup01`), sin identidad administrada hasta `GITIN-1770` (`identity: null` confirmado 2026-08-06).
- **9 objetos de certificado cargados directamente (PFX)** en el gateway al momento de este trabajo — ninguno integrado con Key Vault. Solo 3 están realmente en uso (confirmado vía `.httpListeners[].sslCertificate`): `clubgrido.2023.2024` (ClubSite AR), `www.clubgrido.com.py_2026_v2` (ClubSite PY), `website_2024` (WebSite). Los otros 6 son huérfanos de ciclos de renovación manuales anteriores.
- **HTTP-01 no es viable para ningún hostname de este gateway** — los listeners HTTP existentes (`Listener_ClubSite_HTTP_AR`/`_PY`) son redirecciones puras a HTTPS (`redirectConfig` seteado, `backendPool: null`), sin backend real que pueda servir un archivo de challenge.
- **DNS-01 es el único método viable**, igual que en MobileAppService — pero requiere acceso de administración al dominio correspondiente (ver "Notas" para el caso de `clubgrido.com.py`, sin acceso).

## 3. Recursos de la automatización (compartidos entre hostnames de este gateway)

| Recurso | Nombre | Alcance |
|---|---|---|
| Key Vault | `sfcg-waf-apps-kv` | Compartido — un secret/certificado por hostname |
| Managed Identity (lectura) | `waf-apps-kv-identity` | Attachada a `WAF_APPs`, rol `Key Vault Secrets User` sobre `sfcg-waf-apps-kv` |
| Service Principal (escritura DNS) | `winacme-mobileservice-dns` (reutilizado de `GITIN-1774`, nombre heredado) | Rol `DNS Zone Contributor` — una asignación de rol nueva por cada zona `_acme-challenge.*` adicional, no una sola asignación de alcance amplio |

No crear una Managed Identity ni un Service Principal nuevo por cada hostname — reutilizar los de arriba, agregando solo las asignaciones de rol que falten (nueva zona DNS → nueva asignación `DNS Zone Contributor` scopeada a esa zona específica).

## 4. Procedimiento (por hostname)

### 4.1 Confirmar el certificado y listener reales

```bash
az network application-gateway show --name WAF_APPs --resource-group DefaultGroup01 \
  --subscription 0190fa7d-4ccf-4e3d-beb1-323b5780bfc8 -o json \
  | jq '.httpListeners[] | {name, hostName, sslCertificate: .sslCertificate.id}'
```

No asumir cuál certificado corresponde a cada listener por el nombre — confirmado que al menos un objeto (`clubgrido.2023.2024`) parecía huérfano por su nombre y en realidad estaba en uso.

### 4.2 Zona Azure DNS para el hostname

```bash
az network dns zone create --name "_acme-challenge.<hostname>" --resource-group DefaultGroup01 \
  --subscription 0190fa7d-4ccf-4e3d-beb1-323b5780bfc8

az network dns zone show --name "_acme-challenge.<hostname>" --resource-group DefaultGroup01 \
  --subscription 0190fa7d-4ccf-4e3d-beb1-323b5780bfc8 --query nameServers -o tsv
```

Delegar manualmente en el panel DNS correspondiente (registro NS, host `_acme-challenge.<subdominio>`) — **requiere acceso administrativo a ese dominio específico**. Verificar con `dig _acme-challenge.<hostname>` que la sección `AUTHORITY` devuelve el SOA propio de la zona nueva, no el del dominio padre.

### 4.3 Permiso del Service Principal sobre la zona nueva

```bash
az role assignment create \
  --assignee "<appId del Service Principal existente>" \
  --role "DNS Zone Contributor" \
  --scope "/subscriptions/0190fa7d-4ccf-4e3d-beb1-323b5780bfc8/resourceGroups/DefaultGroup01/providers/Microsoft.Network/dnszones/_acme-challenge.<hostname>" \
  --subscription 0190fa7d-4ccf-4e3d-beb1-323b5780bfc8
```

### 4.4 Key Vault y Managed Identity (una sola vez para todo el gateway, ya hecho)

```bash
az keyvault create --name sfcg-waf-apps-kv --resource-group DefaultGroup01 --location eastus \
  --enable-rbac-authorization true --subscription 0190fa7d-4ccf-4e3d-beb1-323b5780bfc8

az identity create --name waf-apps-kv-identity --resource-group DefaultGroup01 \
  --subscription 0190fa7d-4ccf-4e3d-beb1-323b5780bfc8

az network application-gateway identity assign --gateway-name WAF_APPs --resource-group DefaultGroup01 \
  --identity /subscriptions/0190fa7d-4ccf-4e3d-beb1-323b5780bfc8/resourcegroups/DefaultGroup01/providers/Microsoft.ManagedIdentity/userAssignedIdentities/waf-apps-kv-identity \
  --subscription 0190fa7d-4ccf-4e3d-beb1-323b5780bfc8

az role assignment create --assignee "<principalId de la identity>" --role "Key Vault Secrets User" \
  --scope "/subscriptions/0190fa7d-4ccf-4e3d-beb1-323b5780bfc8/resourceGroups/DefaultGroup01/providers/Microsoft.KeyVault/vaults/sfcg-waf-apps-kv" \
  --subscription 0190fa7d-4ccf-4e3d-beb1-323b5780bfc8
```

No repetir para hostnames adicionales — ya cubre todo el gateway.

### 4.5 win-acme: host, plugins y emisión (pendiente de detallar tras la primera ejecución real)

**Host elegido para ClubSite AR: `SFCG-CLUB-01`** (`192.168.50.121`, confirmado miembro real de `Back_ClubSite` vía `az network nic list`, no solo por el nombre). Se evaluaron una VM dedicada nueva y una alternativa serverless (`keyvault-acmebot`, proyecto de terceros en Azure Functions, purpose-built para este patrón exacto) — no elegidas por ahora, se prioriza reutilizar infraestructura existente.

Instalar en ese host: build pluggable de win-acme (`win-acme.v2.2.9.1701.x64.pluggable.zip`) + plugin de validación DNS-01 de Azure DNS (`plugin.validation.dns.azure.v2.2.9.1701.zip`, mismo que en `GITIN-1774`) + plugin de store de Key Vault (`plugin.store.keyvault.v2.2.9.1701.zip`) — nombres exactos confirmados contra la API de GitHub, no adivinados.

Wizard (`wacs.exe` → M, opciones completas): Source manual (hostname puntual, no todo el sitio IIS) → Validation Azure DNS (`AzureCloud`, sin managed identity, credenciales del Service Principal, zona `_acme-challenge.<hostname>`) → Store Key Vault (nombre del vault, sin managed identity — usa las mismas credenciales del Service Principal, que necesita `Key Vault Certificates Officer` sobre el vault, no solo `DNS Zone Contributor`) → sin paso de Installation (no hace falta binding local para el certificado público). El gateway recoge la nueva versión del secret automáticamente en ~4h, sin redeploy, siempre que el `sslCertificate` del listener referencie la URI del secret **sin versión** (`.../secrets/<nombre>`, sin el GUID de versión al final) — con versión explícita, el gateway queda fijado a esa versión para siempre.

## 5. Notas

- **`GITIN-1769` (ClubSite PY) está bloqueado** — sin acceso administrativo al dominio `clubgrido.com.py`, no se puede agregar el registro NS de delegación. HTTP-01 tampoco es viable (mismo hallazgo de redirección sin backend que ClubSite AR). Sin camino de automatización identificado hasta conseguir acceso DNS o agregar una regla de ruteo por path para `/.well-known/acme-challenge/*`.
- Este runbook asume que `GITIN-1771` (WebSite) sigue el mismo patrón — no verificado todavía si `gestion.clubgrido.com.ar` tiene el mismo tipo de acceso DNS que `clubgrido.com.ar` (debería, mismo dominio) ni si su listener HTTP (si existe) tiene el mismo problema de redirección sin backend.

## 6. Certificado del backend (tramo Gateway→Backend, si el gateway hace re-encriptación end-to-end)

**Antes de automatizar solo la sección 4 y dar el ticket por cerrado, confirmar si el gateway decripta y vuelve a encriptar hacia el backend** (`backendHttpSettingsCollection[].protocol: Https` con `trustedRootCertificates` seteado) — si es así, hay **dos certificados completamente independientes** por hostname: el público (sección 4, vive en el listener) y el del backend (esta sección, vive localmente en cada VM backend vía IIS). Automatizar solo uno dejando el otro en un certificado comprado/manual es un riesgo de caída total no relacionado con la validez del certificado público — así se descubrió en `GITIN-1770` (backend GoDaddy vencía 2026-11-13, fuera del alcance original del ticket).

### 6.1 Emisión e instalación (por VM backend, independiente en cada una)

Cada VM backend corre su propia automatización con **clave privada propia** — no copiar certificados/claves privadas entre VMs (mismo criterio que MobileAppService). Instalar win-acme con el plugin de validación DNS-01 de Azure DNS únicamente (**no** el plugin de store de Key Vault — el certificado de backend no va a Key Vault).

Wizard: Source manual (hostname puntual) → si el sitio IIS tiene múltiples hostnames por SNI (ej. ClubSite sirve `.ar` y `.py` en el mismo sitio), el wizard pregunta cómo agrupar (`1: por dominio`, `2: por host`, `3: por sitio IIS`, `4: certificado único`) — **elegir "2: por host"** y seleccionar únicamente el hostname deseado, para no arrastrar accidentalmente el resto de los hostnames del mismo sitio a la misma emisión → Validation Azure DNS (misma zona que la sección 4) → Store Windows Certificate Store, Local Computer, mismo store name que usan los bindings existentes (confirmar con `Get-WebBinding`, normalmente `My`) → Installation "Create or update bindings in IIS", seleccionar el sitio correspondiente.

El plugin de instalación IIS actualiza *todas* las bindings que usaban el certificado anterior — seguro mientras cada hostname tenga un hash de certificado distinto en el sitio (confirmar con `Get-WebBinding` antes de instalar).

**El vault de credenciales local de win-acme (donde se puede guardar el secret del Service Principal para reutilizar) está cifrado con DPAPI y es local a cada máquina — no se sincroniza entre VMs.** Un secret guardado en el vault de la VM A no es utilizable desde la VM B. Al automatizar la segunda VM en adelante, generar un secret nuevo para el mismo Service Principal (`az ad app credential reset --append` — nunca sin `--append`, invalidaría los secrets que ya usan otras VMs) en vez de intentar reutilizar el guardado en la primera.

Let's Encrypt puede emitir a través de intermedios "hermanos" distintos en cada corrida (ej. `YR1`/`YR2`, o `E5`/`E6`/`R10`/`R11` según el momento) — todos encadenan a la misma raíz autofirmada. No asumir que el nombre del intermedio se mantiene igual entre corridas.

### 6.2 Cadena de confianza en `trustedRootCertificates`

**Solo el certificado raíz autofirmado va en `trustedRootCertificates` — nunca un intermedio.** Verificar con `openssl x509 -noout -subject -issuer` antes de cargar: si `Issuer` ≠ `Subject`, es un intermedio y `az network application-gateway root-cert create` lo va a rechazar con `ApplicationGatewayTrustedRootCertificateInvalidData`, sin importar si el archivo está en DER o base64/PEM (confirmado en `GITIN-1770`, dos intentos fallidos con ambos formatos antes de identificar la causa real). El intermedio no hace falta cargarlo en el gateway — el propio IIS del backend ya lo sirve en el handshake TLS si win-acme lo instaló correctamente (se puede confirmar revisando que el certificado quedó en el almacén `CA` local, no solo en `My`).

```bash
# Diagnóstico rápido: ¿es raíz autofirmado o intermedio?
openssl x509 -inform DER -in certificado.cer -noout -subject -issuer
# Issuer == Subject -> raíz autofirmado, sirve para trustedRootCertificates
# Issuer != Subject -> intermedio, NO cargar acá

# ⚠️ ACTION — carga el root cert al gateway
az network application-gateway root-cert create \
  --gateway-name WAF_APPs --resource-group DefaultGroup01 \
  --name <nombre> --cert-file <archivo> \
  --subscription 0190fa7d-4ccf-4e3d-beb1-323b5780bfc8

# ⚠️ ACTION — adjunta el root cert a los HTTP settings del backend correspondiente
az network application-gateway http-settings update \
  --gateway-name WAF_APPs --resource-group DefaultGroup01 \
  --name <Backend_X> --root-certs <lista de nombres existentes> <nombre nuevo> \
  --subscription 0190fa7d-4ccf-4e3d-beb1-323b5780bfc8

# Verificación — todas las direcciones del backend pool deben quedar Healthy
az network application-gateway show-backend-health \
  --name WAF_APPs --resource-group DefaultGroup01 \
  --subscription 0190fa7d-4ccf-4e3d-beb1-323b5780bfc8 -o json
```
