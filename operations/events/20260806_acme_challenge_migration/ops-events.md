# Eventos — 20260806_acme_challenge_migration

## 2026-08-06 — Creación de la zona Azure DNS y delegación

**Comando:** C1-C2 — `az network dns zone create` / `az network dns zone show`
**Resultado:**
Ver scripts (C1-C2). Zona `_acme-challenge.mobileservice.clubgrido.com.ar` creada en `DefaultGroup01`. Nameservers asignados: `ns1-01.azure-dns.com.`, `ns2-01.azure-dns.net.`, `ns3-01.azure-dns.org.`, `ns4-01.azure-dns.info.`.

He creado la zona Azure DNS acotada específicamente a `mobileservice.clubgrido.com.ar`, sin esperar confirmación de un alcance más amplio para los tickets de ClubSite/WebSite. Agregué manualmente el registro NS correspondiente en GoDaddy con estos cuatro nameservers.

## 2026-08-06 — Delegación confirmada

**Comando:** C5 — `dig _acme-challenge.mobileservice.clubgrido.com.ar`
**Resultado:**
`status: NOERROR`, sección `AUTHORITY` con el SOA propio de la zona desde `ns1-01.azure-dns.com.`.

He confirmado que la delegación GoDaddy → Azure DNS está activa y resolviendo correctamente antes de continuar con la configuración de win-acme.

## 2026-08-06 — Service Principal y permisos

**Comando:** C3-C4 — `az ad sp create-for-rbac` / `az role assignment create`
**Resultado:**
Ver scripts (C3-C4). Service Principal `winacme-mobileservice-dns` creado (`appId: 3cca7e2a-5b4a-4b0d-87ee-4390af90346f`, `tenant: 33ee786b-c072-4326-8759-7be9b82e9801`). Rol `DNS Zone Contributor` asignado sobre la zona con scope exacto, confirmado por la respuesta del comando.

He creado el Service Principal para que win-acme pueda escribir el TXT de validación en la zona delegada, y le asigné el permiso mínimo necesario (`DNS Zone Contributor`, acotado a esa zona específica, no a nivel suscripción). El client secret no quedó registrado en ningún archivo de este repositorio — se mostró una sola vez y debe guardarse fuera de aquí.

## 2026-08-06 — Instalación del plugin de Azure DNS en SFCG-MOBI-01

**Comando:** C6 — descarga/instalación del plugin (PowerShell)
**Resultado:**
Primer intento con un nombre de archivo adivinado devolvió 404. Confirmé el nombre real (`plugin.validation.dns.azure.v2.2.9.1701.zip`) contra la API de GitHub antes de reintentar, y la segunda descarga funcionó.

He verificado que el plugin de Azure DNS no estaba instalado en `SFCG-MOBI-01` — solo se habían instalado el build base de win-acme y el plugin de GoDaddy en la configuración original del 04/08. Instalé el plugin correcto tras confirmar el nombre real del archivo.

## 2026-08-06 — Reconfiguración y verificación en SFCG-MOBI-01

**Comando:** C7-C9 — `wacs.exe` interactivo (Manage renewals → Edit → Validation → Azure DNS) + verificación de tarea programada + `Get-ChildItem` sobre el store de certificados
**Resultado:**
Renovación editada con `AzureCloud`, sin managed identity, credenciales del Service Principal, zona `_acme-challenge.mobileservice.clubgrido.com.ar`, tarea programada sin cambio de cuenta (mantiene `SYSTEM`). La tarea programada corrió sola y terminó exitosamente (`Task Scheduler successfully finished ... for user "NT AUTHORITY\SYSTEM"`). Certificado nuevo confirmado: thumbprint `059B73F29D2F2879FE3E5D5412D8BEAF638816DD`, válido 2026-08-06 a 2026-11-04.

He confirmado que `SFCG-MOBI-01` renueva de forma completamente desatendida vía Azure DNS-01, sin ningún paso manual de TXT record durante la corrida.

## 2026-08-06 — Reconfiguración y verificación en SFCG-MOBI-02

**Comando:** C6-C9 repetidos en la segunda VM
**Resultado:**
Mismo procedimiento que en `-01`, con dos diferencias: el secret del Service Principal se guardó esta vez en el vault local de win-acme (nombre `winacme-mobileservice-dns`, con comentario de scope/rol — sí había caso de reuso al ser la misma credencial en una segunda VM), y la instalación del certificado mostró el mensaje benigno `Unable to save using CryptoAPI, retrying with CNG...` antes de completarse con éxito. Certificado nuevo confirmado: thumbprint `73C2B039A82297F091D6F3A2367B8C56F0A1B902`, válido 2026-08-06 a 2026-11-04.

He confirmado que `SFCG-MOBI-02` también renueva de forma completamente desatendida, con el mismo mecanismo que `-01`.

## 2026-08-06 — Verificación final en el endpoint público

**Comando:** C10 — `openssl s_client` contra `mobileservice.clubgrido.com.ar:8043` (a través de la LB, no bypaseada)
**Resultado:**
`notBefore`/`notAfter` coinciden exactamente con el certificado de `SFCG-MOBI-02` (afinidad de sesión de la LB enrutó la verificación a esa VM). Emisor Let's Encrypt (`YE2`).

He confirmado que el endpoint público sirve correctamente el certificado renovado. Con esto doy por cerrada la implementación de GITIN-1774 — actualicé el runbook (`operations/docs/mobileappservice_ssl_renewal_runbook.md`, sección 5) con los pasos reales ejecutados, y generé el ticket principal (`ops.md`) de este evento.
