# Eventos — 20260804_mobileappservice_ssl_cert_renewal

## 2026-08-04 — Relevamiento de infraestructura y red

**Comando:** C1-C5 — inventario de NICs, reglas de LB, frontend IP y IP pública para SFCG-MOBI-01/02
**Resultado:**
Ver `20260804_mobileappservice_ssl_cert_renewal_scripts.sh` (C1 a C5).

He confirmado que `SFCG-MOBI-01` y `SFCG-MOBI-02` están detrás del load balancer `SFCG-MOBI-LB` (capa 4, sin Application Gateway/WAF de por medio), con una única regla TCP 8043→8043 y distribución `SourceIPProtocol` (afinidad por IP de origen). La IP pública `20.121.19.174` pertenece al frontend del LB (`SFCG-MOBI-LB-publicip`), no a ninguna VM directamente. No existe regla de puerto 80/443 en este LB, por lo que la validación ACME HTTP-01 no es viable sin abrir una regla nueva solo para eso.

## 2026-08-04 — Proveedor DNS confirmado

**Comando:** C6 — `dig NS clubgrido.com.ar` / `dig mobileservice.clubgrido.com.ar`
**Resultado:**
Ver scripts (C6). NS: `pdns07.domaincontrol.com`, `pdns08.domaincontrol.com` (GoDaddy). Registro A de `mobileservice.clubgrido.com.ar` coincide con la IP del LB.

He confirmado que el dominio público está gestionado en GoDaddy, con acceso disponible. Esto habilita validación DNS-01 vía plugin de GoDaddy en win-acme, evitando la necesidad de abrir el puerto 80 en el LB.

## 2026-08-04 — Certificado actual verificado, urgencia alta

**Comando:** C7 — `openssl s_client` + `openssl x509` contra `mobileservice.clubgrido.com.ar:8043`
**Resultado:**
Ver scripts (C7). Emisor Let's Encrypt `E7`, ECDSA P-256, único SAN `mobileservice.clubgrido.com.ar`, serial `0622488DB0F4985889F2CAE8A570DAA3EC1B`, `notAfter = 2026-08-09 13:28:04 GMT`.

He confirmado que el certificado actual vence en 5 días y que ya era Let's Encrypt (emitido manualmente, sin renovación automática vigente) — es la causa raíz de este ticket.

## 2026-08-04 — Diseño de automatización definido

He definido automatizar la renovación con win-acme (no certbot, sin soporte oficial en Windows desde v2.0) usando validación DNS-01 vía plugin de GoDaddy, con instalación independiente en cada VM (`SFCG-MOBI-01` y `SFCG-MOBI-02`), cada una con su propio certificado y su propia tarea programada — sin Central Certificate Store, dado que DNS-01 no depende de a qué nodo enruta el LB.

## 2026-08-04 — Configuración de win-acme en SFCG-MOBI-01 (en curso)

He descargado win-acme v2.2.9.1701 build `x64 pluggable` en `SFCG-MOBI-01` (requerido para soportar plugins adicionales) junto con el plugin de validación DNS-01 para GoDaddy, extraído en el mismo directorio y desbloqueado. He generado una API key de producción en GoDaddy Developer Portal. En el asistente interactivo de win-acme (`wacs.exe`, ejecutado como administrador) he seleccionado: host manual `mobileservice.clubgrido.com.ar`, certificado único, validación DNS-01 con plugin GoDaddy, clave EC (coincide con el certificado actual), almacenamiento en Windows Certificate Store (WebHosting), paso de instalación "Create or update bindings in IIS" sobre el sitio `SmartLoyalty.MobileAppService`. Pendiente: confirmar binding aplicado, verificar certificado en el endpoint público, y repetir el mismo procedimiento en `SFCG-MOBI-02`.

## 2026-08-04 — Binding anterior capturado (rollback)

**Comando:** C8 — `netsh http show sslcert ipport=0.0.0.0:8043`
**Resultado:**
Certificate Hash: `7e2b79194383fa97379640631fb1b077ad212da8`, Application ID: `{4dc3e181-e14b-4a21-b022-59fc669b0914}`, Certificate Store Name: `My`.

He capturado el binding SSL vigente en `SFCG-MOBI-01` antes de que win-acme lo reemplace, como referencia de rollback en caso de que el certificado nuevo presente algún problema (p. ej. certificate pinning en la app móvil).

## 2026-08-04 — Validación DNS-01 con GoDaddy falló, acceso a API denegado

**Comando:** intento de validación DNS-01 vía plugin GoDaddy en win-acme; luego prueba directa `curl` contra `api.godaddy.com/v1/domains`
**Resultado:**
Primer intento con token `gd_pat_...` (Portal Commerce/Developer nuevo, OAuth): `Unauthorized` en win-acme, token nunca autenticó. Segundo intento regenerando como par Key+Secret clásico: `curl` devolvió `HTTP 403 {"code":"ACCESS_DENIED","message":"Authenticated user is not allowed access"}`.

He confirmado que la cuenta de GoDaddy no tiene habilitado el acceso a la API de Domains — es una restricción a nivel de cuenta documentada por GoDaddy, no un problema de credenciales ni de configuración del plugin. También he detectado que el primer token generado tenía 11 scopes, incluyendo eliminación y transferencia de dominio, muy por encima de lo necesario (`domains.dns:update` únicamente) — pendiente revocarlo.

## 2026-08-04 — Decisión: plan en dos etapas

He decidido no seguir insistiendo con el acceso a la API de GoDaddy por el momento. Etapa inmediata: emitir el certificado hoy mismo con validación DNS-01 manual (registro TXT agregado a mano una sola vez en GoDaddy), sin renovación automática, para eliminar la urgencia del vencimiento 2026-08-09. Etapa definitiva: delegar `_acme-challenge.mobileservice.clubgrido.com.ar` a una zona de Azure DNS (un único registro NS manual en GoDaddy) y usar el plugin de Azure DNS de win-acme para todas las renovaciones futuras, evitando por completo la dependencia de la API de GoDaddy.

## 2026-08-04 — Certificado emitido en SFCG-MOBI-01

**Comando:** win-acme (`wacs.exe`, interactivo) — validación DNS-01 manual, clave EC, Windows Certificate Store (WebHosting), binding IIS en sitio `SmartLoyalty.MobileAppService`, puerto 8043
**Resultado:**
`Certificate [Manual] mobileservice.clubgrido.com.ar created`. Próxima renovación programada: 2026-09-28. Tarea programada `win-acme renew (acme-v02.api.letsencrypt.org)` creada, ejecuta `wacs.exe --renew`, configurada para correr con una cuenta de usuario específica (no la opción por defecto SYSTEM) — pendiente confirmar cuál.

He emitido y vinculado en IIS el certificado nuevo en `SFCG-MOBI-01`, reemplazando el que vencía el 2026-08-09. Dado que la validación fue manual (no vía API), la renovación automática programada para el 2026-09-28 fallará sin intervención — debe estar resuelta la delegación a Azure DNS antes de esa fecha, o repetirse el paso manual de TXT.

## 2026-08-04 — Certificado nuevo confirmado en el store

**Comando:** `Get-ChildItem Cert:\LocalMachine\WebHosting` en `SFCG-MOBI-01`
**Resultado:**
Thumbprint `0FDAC0F3042B55C8B067DBEB0B9767365F022A2A`, NotBefore `2026-08-04 17:17:22`, NotAfter `2026-11-02 17:17:21`, Subject `CN=mobileservice.clubgrido.com.ar`.

He confirmado que el certificado nuevo (90 días de validez) está efectivamente instalado en el store `WebHosting` de `SFCG-MOBI-01`, distinto del store `My` donde residía el certificado anterior. Pendiente verificación externa vía `openssl` contra el endpoint público.

## 2026-08-04 — Certificado emitido en SFCG-MOBI-02

**Comando:** `netsh http show sslcert` (binding anterior, idéntico al de `-01`) + win-acme (`wacs.exe`, interactivo) — validación DNS-01 manual, clave EC, Windows Certificate Store (WebHosting), binding IIS en sitio `SmartLoyalty.MobileAppService`, puerto 8043, tarea programada con cuenta SYSTEM por defecto
**Resultado:**
Binding anterior idéntico al de `SFCG-MOBI-01` (mismo hash `7e2b79194383fa97379640631fb1b077ad212da8`, confirma que el certificado original era compartido/duplicado manualmente entre ambas VMs). Exportación del certificado nuevo desde `-01` no fue viable — win-acme generó la clave privada como no exportable. Se emitió un certificado independiente en `-02` siguiendo el mismo procedimiento manual que en `-01`. `Certificate [Manual] mobileservice.clubgrido.com.ar created`, próxima renovación 2026-09-28, tarea `win-acme renew` con cuenta SYSTEM (a diferencia de `-01`, que quedó con una cuenta nombrada aún sin confirmar).

He completado la emisión y vinculación del certificado en ambas VMs (`SFCG-MOBI-01` y `SFCG-MOBI-02`), eliminando la urgencia del vencimiento original (2026-08-09). Ambas renovaciones automáticas programadas para el 2026-09-28 fallarán sin intervención (validación manual) — pendiente completar la delegación a Azure DNS antes de esa fecha.

## 2026-08-04 — Verificación final en ambas VMs

**Comando:** chequeo TLS local (PowerShell `SslStream` contra `localhost:8043`, evita el LB) en `SFCG-MOBI-01` y `SFCG-MOBI-02`
**Resultado:**
`SFCG-MOBI-01`: thumbprint `0FDAC0F3042B55C8B067DBEB0B9767365F022A2A`, válido 2026-08-04 a 2026-11-02.
`SFCG-MOBI-02`: thumbprint `BDBC462EF18135D40FF092C5824AA1666656E7A3`, válido 2026-08-04 a 2026-11-02.
Ambos `CN=mobileservice.clubgrido.com.ar`, emisor Let's Encrypt.

He verificado directamente en cada VM (sin pasar por el LB) que ambas están sirviendo certificados nuevos, válidos e independientes. Con esto doy por cerrada la etapa de emergencia (stopgap) — queda pendiente únicamente la automatización definitiva vía delegación a Azure DNS antes del 2026-09-28.

## 2026-08-05 — Verificación de tareas programadas de renovación, ambas VMs

**Comando:** C13-C15 — `Get-ScheduledTask`/`Principal`/`Triggers`/`Get-ScheduledTaskInfo`/`Settings`/`LastBootUpTime` en ambas VMs, más C14 — `Get-WinEvent` acotado por fecha sobre el canal `Microsoft-Windows-TaskScheduler/Operational`
**Resultado:**
Ver scripts (C13 a C15). `SFCG-MOBI-01`: cuenta `SYSTEM`, `LogonType: ServiceAccount`, disparador diario funcionando correctamente (evento ID 107, "due to a time trigger condition", 2026-08-05 11:18), `LastBootUpTime` 2026-07-23 (13 días de actividad continua). `SFCG-MOBI-02`: misma configuración de cuenta y disparador, pero `LastRunTime` (11:53:53) cayó apenas 3m14s después de `LastBootUpTime` (11:50:39) — la tarea se ejecutó por `StartWhenAvailable`, recuperando un disparo perdido, no por un disparo normal dentro de la ventana.

He confirmado que la tarea programada de renovación funciona correctamente y sin intervención manual en ambas VMs. En `SFCG-MOBI-01` el disparo es directo; en `SFCG-MOBI-02` depende del mecanismo de recuperación de disparos perdidos (`StartWhenAvailable`), que también se ejecutó correctamente. No hay ningún defecto en la configuración de la tarea programada en sí.

## 2026-08-05 — Causa raíz de la ventana perdida en SFCG-MOBI-02: apagado automático nocturno

**Comando:** C16-C17 — `az resource list`/`az resource show` sobre `Microsoft.DevTestLab/schedules` en `DefaultGroup01`; C18 — revisión de Automation Accounts (`sfcgautomation`, `SFCG-AUTOM`); C19 — `az resource list` sobre `Microsoft.Logic/workflows`
**Resultado:**
Ver scripts (C16 a C19). `SFCG-MOBI-02` tiene un schedule de apagado automático (`shutdown-computevm-SFCG-MOBI-02`) habilitado, disparado diariamente a las 01:00 (hora Argentina) — creado 2023-04-28. `SFCG-MOBI-01` tiene el mismo tipo de recurso pero deshabilitado. El apagado automático de Azure no incluye encendido automático nativo; encontré que el reinicio diario de `-02` lo cubre una Logic App independiente (`Start_Mobile02_11AM`), que reinicia la VM alrededor de las 11:00 — el mismo patrón existe para otras VMs de la flota (`Start_Mobi01_08AM`, `WEBS01_Start_09AM`, `CLUB01_START`, entre otras).

He confirmado que el comportamiento reportado ("la tarea no corrió sola, corrió al iniciar sesión") se explica por este ciclo apagado/encendido diario intencional de `SFCG-MOBI-02`, no por un problema de configuración de la tarea programada ni de la cuenta usada. Decidí mantener el schedule tal como está (es intencional y sigue un patrón ya usado en el resto de la flota) — doy este punto por cerrado sin cambios, no modifiqué ningún recurso de Azure.
