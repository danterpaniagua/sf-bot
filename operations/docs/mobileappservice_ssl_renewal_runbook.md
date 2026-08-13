# Runbook — Renovación del certificado SSL de MobileAppService (`SFCG-MOBI-01/02`)

> Origen: ticket `GITIN-1786` (stopgap manual, sección 4), evento `operations/events/20260804_mobileappservice_ssl_cert_renewal/`. Automatización definitiva (sección 5) implementada bajo `GITIN-1774`, evento `operations/events/20260806_acme_challenge_migration/`. Ver esos eventos para el detalle completo de la investigación (topología de red, por qué se descartó GoDaddy como validador DNS-01, etc.).

## 1. Objetivo

Procedimiento para renovar el certificado SSL público de MobileAppService (`https://mobileservice.clubgrido.com.ar:8043`), tanto en su forma manual (stopgap, usada el 2026-08-04) como en su forma automatizada definitiva (delegación a Azure DNS, implementada el 2026-08-06 — ver sección 5). La sección 4 queda como referencia histórica/rollback; la renovación real ya no requiere ningún paso manual.

## 2. Topología relevante

- **Hosts:** `SFCG-MOBI-01` y `SFCG-MOBI-02`, Windows/IIS, `DefaultGroup01`, subscripción Smart IT - Grido (`0190fa7d-4ccf-4e3d-beb1-323b5780bfc8`). Sitio IIS: `SmartLoyalty.MobileAppService`, binding HTTPS en el puerto **8043**.
- **Certificado independiente por VM.** No hay Central Certificate Store (CCS) compartido — cada VM emite y renueva su propio certificado. win-acme genera claves privadas **no exportables** por defecto, por lo que no es posible copiar el `.pfx` de una VM a la otra; hay que repetir el procedimiento en cada una.
- **Load Balancer `SFCG-MOBI-LB`** (capa 4, sin WAF/Application Gateway): única regla TCP 8043→8043, distribución `SourceIPProtocol` (afinidad por IP de origen — un mismo cliente siempre cae en la misma VM backend). **No existe regla de puerto 80/443** — la validación ACME HTTP-01 no es viable sin abrir una regla nueva solo para eso; usar siempre DNS-01.
- **DNS:** `clubgrido.com.ar` gestionado en **GoDaddy** (`pdns07/08.domaincontrol.com`). La cuenta GoDaddy **no tiene habilitado el acceso a su API de Domains** (`403 ACCESS_DENIED`, confirmado 2026-08-04) — no usar el plugin GoDaddy de win-acme hasta que esto cambie.

## 3. Prerrequisitos

- Acceso RDP/PowerShell como administrador a `SFCG-MOBI-01` y `SFCG-MOBI-02`.
- Acceso al panel de GoDaddy para agregar/eliminar registros DNS de `clubgrido.com.ar` — solo necesario para el procedimiento manual histórico (sección 4) o para el registro NS único de la delegación (sección 5, ya realizado). Las renovaciones normales, con la sección 5 implementada, no requieren ningún acceso manual.
- win-acme (`wacs.exe`), build **x64 pluggable** (no `trimmed` — la validez de esta distinción no está 100% verificada contra la versión exacta que se use, confirmar en la propia herramienta si el store de plugins no carga) — descargar desde `https://github.com/win-acme/win-acme/releases`.

## 4. Procedimiento manual (stopgap — usado el 2026-08-04)

Repetir en cada VM (`SFCG-MOBI-01`, luego `SFCG-MOBI-02`) de forma independiente.

### 4.1 Capturar el binding SSL anterior (referencia de rollback)

```powershell
netsh http show sslcert ipport=0.0.0.0:8043
```

Guardar `Certificate Hash`, `Application ID` y `Certificate Store Name` de la salida — necesarios para revertir si algo falla.

### 4.2 Instalar win-acme

```powershell
New-Item -ItemType Directory -Force -Path C:\win-acme | Out-Null
Invoke-WebRequest -Uri "https://github.com/win-acme/win-acme/releases/download/v2.2.9.1701/win-acme.v2.2.9.1701.x64.pluggable.zip" -OutFile "C:\win-acme\win-acme.zip"
Expand-Archive -Path "C:\win-acme\win-acme.zip" -DestinationPath "C:\win-acme" -Force
Get-ChildItem C:\win-acme -Recurse | Unblock-File
```

(Verificar la URL/versión vigente en la página de releases — puede haber cambiado.)

### 4.3 Ejecutar el asistente

```powershell
cd C:\win-acme
.\wacs.exe
```

Como administrador. Secuencia de menú:

| Paso | Opción |
|---|---|
| Menú principal | **M** — Create certificate (full options) |
| Origen del dominio | **2** — Manual input → `mobileservice.clubgrido.com.ar` |
| División de certificados | **4** — Single certificate |
| Validación | **[dns] Create verification records manually** (el número exacto varía según qué plugins estén instalados — confirmar en pantalla) |
| Registro TXT | Agregar manualmente en el panel de GoDaddy el registro `_acme-challenge.mobileservice.clubgrido.com.ar` con el valor indicado, esperar confirmación, continuar |
| Tipo de clave | **1** — Elliptic Curve key (coincide con el certificado actual) |
| Almacenamiento | **4** — Windows Certificate Store (Local Computer) |
| Store específico | **3** — Default (WebHosting) |
| ¿Otro paso de store? | **5** — No (additional) store steps |
| Instalación | **1** — Create or update bindings in IIS → sitio `SmartLoyalty.MobileAppService` |
| ¿Otro paso de instalación? | **3** — No (additional) installation steps |
| Cuenta de la tarea programada | **SYSTEM** (responder `n` a "specify the user") — evita acoplar la renovación al runbook de rotación de `SMARTIT\itservices` |
| Horario | Escalonar entre VMs — p. ej. `09:00` en `-01`, `13:00` en `-02` — para evitar que ambas intenten renovar en la misma ventana |

### 4.4 Verificar

```powershell
# Verificación local (bypasea el LB)
$tcp = New-Object System.Net.Sockets.TcpClient('localhost', 8043)
$ssl = New-Object System.Net.Security.SslStream($tcp.GetStream(), $false, ({$true}))
$ssl.AuthenticateAsClient('mobileservice.clubgrido.com.ar')
$cert = [System.Security.Cryptography.X509Certificates.X509Certificate2]$ssl.RemoteCertificate
$cert | Select-Object Thumbprint, NotBefore, NotAfter, Subject, Issuer
$ssl.Close(); $tcp.Close()
```

Confirmar `NotAfter` extendido (~90 días) y `Subject = CN=mobileservice.clubgrido.com.ar`. Repetir en la otra VM.

### 4.5 Limpieza

Eliminar el registro TXT temporal en GoDaddy — ya no es necesario una vez validado.

### 4.6 Rollback (si algo falla)

```powershell
netsh http delete sslcert ipport=0.0.0.0:8043
netsh http add sslcert ipport=0.0.0.0:8043 certhash=<HASH_ANTERIOR> appid='<APP_ID_ANTERIOR>' certstorename=<STORE_ANTERIOR>
```

Usando los valores capturados en el paso 4.1. win-acme no elimina el certificado anterior del store, solo desvincula el binding — el certificado viejo sigue disponible para revertir mientras no haya vencido.

**Advertencia no evidente:** si la app móvil hace *certificate pinning*, un certificado nuevo (aunque válido) puede romper la conexión de clientes existentes incluso sin ningún error visible del lado del servidor. Verificar con un cliente real, no solo con `openssl`/PowerShell.

## 5. Procedimiento automatizado (definitivo — implementado 2026-08-06)

**Estado: implementado y verificado en ambas VMs (ticket `GITIN-1774`).** La renovación ahora corre de forma completamente desatendida vía validación DNS-01 sobre una zona Azure DNS delegada — sin el plugin GoDaddy (la cuenta no tiene acceso habilitado a su API de Domains, ver sección 2, sin ETA de resolución) y sin ningún paso manual de TXT record.

### 5.1 Zona Azure DNS y delegación (una sola vez, ya realizado)

```bash
az network dns zone create \
  --name "_acme-challenge.mobileservice.clubgrido.com.ar" \
  --resource-group DefaultGroup01 \
  --subscription 0190fa7d-4ccf-4e3d-beb1-323b5780bfc8

az network dns zone show \
  --name "_acme-challenge.mobileservice.clubgrido.com.ar" \
  --resource-group DefaultGroup01 \
  --subscription 0190fa7d-4ccf-4e3d-beb1-323b5780bfc8 \
  --query nameServers -o tsv
```

Nameservers asignados (ya delegados en GoDaddy vía registro NS manual, host `_acme-challenge.mobileservice`):

```
ns1-01.azure-dns.com.
ns2-01.azure-dns.net.
ns3-01.azure-dns.org.
ns4-01.azure-dns.info.
```

Verificar la delegación con `dig _acme-challenge.mobileservice.clubgrido.com.ar` — debe devolver `status: NOERROR` con el SOA de la propia zona en la sección `AUTHORITY` (no el de GoDaddy).

### 5.2 Service Principal para win-acme (una sola vez, ya realizado)

```bash
az ad sp create-for-rbac --name "winacme-mobileservice-dns" --skip-assignment

az role assignment create \
  --assignee "<appId-devuelto-arriba>" \
  --role "DNS Zone Contributor" \
  --scope "/subscriptions/0190fa7d-4ccf-4e3d-beb1-323b5780bfc8/resourceGroups/defaultgroup01/providers/Microsoft.Network/dnszones/_acme-challenge.mobileservice.clubgrido.com.ar" \
  --subscription 0190fa7d-4ccf-4e3d-beb1-323b5780bfc8
```

**El `password`/client secret devuelto por `az ad sp create-for-rbac` no se guarda en ningún archivo de este repo** — se muestra una sola vez por Azure; guardarlo en un gestor de secretos propio. Si se pierde, no es recuperable — hay que regenerarlo (`az ad app credential reset`) y volver a configurar ambas VMs.

Datos ya creados (no regenerar salvo rotación): `appId: 3cca7e2a-5b4a-4b0d-87ee-4390af90346f`, `tenant: 33ee786b-c072-4326-8759-7be9b82e9801`. Este Service Principal es compartido entre `SFCG-MOBI-01` y `SFCG-MOBI-02` — no crear uno nuevo por VM.

### 5.3 Instalar el plugin de Azure DNS en win-acme (repetir por VM)

```powershell
cd C:\win-acme
Invoke-WebRequest -Uri "https://github.com/win-acme/win-acme/releases/download/v2.2.9.1701/plugin.validation.dns.azure.v2.2.9.1701.zip" -OutFile "C:\win-acme\azure-dns-plugin.zip"
Expand-Archive -Path "C:\win-acme\azure-dns-plugin.zip" -DestinationPath "C:\win-acme" -Force
Get-ChildItem C:\win-acme -Recurse | Unblock-File
```

**Nota:** verificar el nombre exacto del archivo en la página de releases para la versión de win-acme instalada — no asumir el patrón de nombre; confirmarlo contra la API de GitHub (`https://api.github.com/repos/win-acme/win-acme/releases/tags/<version>`) si hay dudas, un primer intento con un nombre adivinado dio 404 en esta implementación.

### 5.4 Reconfigurar la renovación existente (repetir por VM)

```powershell
cd C:\win-acme
.\wacs.exe
```

Como administrador. Secuencia de menú:

| Paso | Opción |
|---|---|
| Menú principal | **A** — Manage renewals |
| Renovación | Seleccionar `mobileservice.clubgrido.com.ar` |
| Acción | **E** — Edit renewal |
| Sección a editar | **5** — Validation (no re-hacer el wizard completo) |
| Validación | **[dns] Create verification records in Azure DNS** (el número exacto varía según qué plugins estén instalados — confirmar en pantalla) |
| Ambiente de Azure | **2** — AzureCloud |
| Managed service identity | **n** (no) — se usa el Service Principal, no MSI |
| Directory/tenant id | `33ee786b-c072-4326-8759-7be9b82e9801` |
| Application client id | `3cca7e2a-5b4a-4b0d-87ee-4390af90346f` |
| Cómo ingresar el secret | **1** — Type/paste in console (salvo que ya esté guardado en el vault local de win-acme de esa VM) |
| Save to vault for future reuse? | **n** en `-01` (sin caso de reuso en esa VM); **y** en `-02` si se quiere buscarlo la próxima vez sin reingresarlo — si se guarda, pide nombre y comentario para identificarlo |
| AzureSubscriptionId | `0190fa7d-4ccf-4e3d-beb1-323b5780bfc8` |
| AzureHostedZone | `_acme-challenge.mobileservice.clubgrido.com.ar` |
| ¿Especificar usuario de la tarea programada? | **n** — mantiene `SYSTEM` |

Al finalizar, `wacs.exe` fuerza una renovación inmediata, reemplaza el binding de IIS y recrea la tarea programada. `[Manual]` en los mensajes de salida se refiere al plugin de **Source** (entrada manual del hostname), no al de Validation — no es señal de que la validación manual siga activa.

### 5.5 Verificar

```powershell
Get-ChildItem Cert:\LocalMachine\WebHosting | Where-Object { $_.Subject -like "*mobileservice*" } | Select-Object Thumbprint, NotBefore, NotAfter, Subject
```

Confirmar thumbprint distinto del anterior y `NotAfter` ~90 días. Mejor prueba real: forzar/esperar a que corra la tarea programada (no el wizard interactivo) y confirmar en el Visor de Eventos (`Microsoft-Windows-TaskScheduler/Operational`) que terminó exitosamente sin ningún paso manual — esa es la prueba de que quedó verdaderamente desatendido.

Verificación pública (a través de la LB, no bypaseada):

```bash
echo | openssl s_client -connect mobileservice.clubgrido.com.ar:8043 -servername mobileservice.clubgrido.com.ar 2>/dev/null | openssl x509 -noout -issuer -subject -dates -serial
```

Por la afinidad de sesión `SourceIPProtocol` de la LB, una sola corrida solo muestra el certificado de una de las dos VMs — no es prueba de ambas simultáneamente, pero confirma que el endpoint público sirve un certificado válido y nuevo.

### 5.6 Próxima renovación automática

Las tareas programadas de ambas VMs corren diariamente (`09:00` + hasta 4h de retraso aleatorio); `wacs.exe` solo renueva efectivamente cuando el certificado entra en su ventana de renovación (por defecto, los últimos ~30 días de un certificado de 90 días de Let's Encrypt). Próximo vencimiento real: 2026-11-04. No requiere intervención manual salvo que la delegación DNS o el Service Principal cambien.

## 6. Notas

- El certificado original (previo a esta renovación) era compartido/duplicado manualmente entre `SFCG-MOBI-01` y `SFCG-MOBI-02` — sin proceso documentado. Este runbook reemplaza esa práctica por certificados independientes por VM.
- `loyalty/docs/infrastructure.md` tiene el detalle de VM de `SFCG-MOBI-01/02` (tamaño, IP, subnet, subscripción).
