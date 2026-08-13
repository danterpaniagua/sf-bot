# Runbook — Rotación de contraseña de la cuenta `itservices` (identidad IIS transversal SmartLoyalty)

> Origen: evento `20260723_itservices_bloqueo_password`. Ver también `20260610_kerberos_rc4_aadds` (AADDS123) para el detalle completo de por qué esta cuenta es un punto único de dependencia crítico.

## 1. Objetivo

Procedimiento para rotar de forma segura la contraseña de la cuenta Azure AD DS `itservices` (UPN `grupo.servicesit@smartfran.com`, objeto `CN=appaccess,OU=AADDC Users,DC=smartit,DC=azure`) sin provocar el bloqueo de la cuenta por `badPwdCount` excedido.

## 2. Por qué esto no es una rotación de servidor individual

`itservices` es la identidad de App Pool IIS **compartida** por los 12 servidores de producción de SmartLoyalty:

| Servidor | Servicio |
|---|---|
| SFCG-WEBS-01, 02, 03 | SmartLoyalty WebService |
| SFCG-WSV2-01, 02 | SmartLoyalty WebServiceV2 |
| SFCG-WSIT-01 | SmartLoyalty Website |
| SFCG-MOBI-01, 02 | Mobile service |
| SFCG-WSCG-01 | CG web service |
| SFCG-CLUB-01, 02 | Club Grido website |
| SFCG-TO-01 | TaskOperatorService |

Si se actualiza la contraseña en un solo servidor, el resto sigue autenticando con la credencial anterior. Cada intento fallido incrementa `badPwdCount` **de forma local en el DC que lo atiende** (no se replica entre réplicas), pero al superar el umbral de bloqueo del dominio, `lockoutTime` sí se replica de inmediato a todas las réplicas — bloqueando la cuenta para **toda** la flota simultáneamente, incluidos los servidores ya actualizados correctamente.

**Regla de oro: nunca actualizar `itservices` en un solo servidor sin ventana de mantenimiento para completar el resto en el mismo intervalo.**

## 3. Prerrequisitos

- Ventana de mantenimiento coordinada — actualizar los 12 servidores en el mismo intervalo, minimizando el tiempo en que coexisten contraseñas distintas en la flota.
- Cuenta con permisos delegados sobre `smartit.azure` (grupo `AAD DC Administrators` en Entra ID) para poder desbloquear/consultar el objeto vía LDAP desde cualquier servidor de la flota.
- Acceso RDP/PowerShell a cada uno de los 12 servidores.
- IPs de los controladores de dominio AADDS: `192.168.40.4`, `192.168.40.5` (subred `192.168.40.0/24`, RG `DefaultGroup01`, suscripción Smart IT - Grido `0190fa7d-4ccf-4e3d-beb1-323b5780bfc8`).
- **IIS detenido en cada VM antes de actualizar la identidad** — detener el servicio IIS (`iisreset /stop` o el servicio `W3SVC`) en cada uno de los 12 servidores antes de tocar el App Pool. Evita que un pool arranque o recicle a mitad de la actualización con una credencial a medio configurar, generando otro intento fallido de logon adicional al recuento de `badPwdCount`.

## 4. Procedimiento

### 4.1 Reset de contraseña en Entra ID

Realizar el cambio de contraseña una única vez, en Entra ID (portal o `az ad user update`), y documentar el valor exacto en el gestor de secretos correspondiente antes de tocar cualquier servidor. No reescribir la contraseña manualmente en cada servidor a partir de memoria — copiar siempre desde el secreto documentado.

### 4.2 Verificar sincronización del hash hacia AADDS

Desde cualquier servidor unido al dominio, confirmar que `pwdLastSet` refleja el cambio reciente **en ambas réplicas** antes de continuar:

```powershell
foreach ($dc in "192.168.40.4","192.168.40.5") {
    $root = New-Object DirectoryServices.DirectoryEntry("LDAP://$dc/CN=appaccess,OU=AADDC Users,DC=smartit,DC=azure")
    $searcher = New-Object DirectoryServices.DirectorySearcher($root)
    $searcher.SearchScope = "Base"
    $searcher.PropertiesToLoad.AddRange(@("pwdLastSet"))
    $result = $searcher.FindOne()
    $pwdLastSet = [Int64]$result.Properties["pwdlastset"][0]
    "$dc -> PwdLastSet: " + [DateTime]::FromFileTime($pwdLastSet)
}
```

Si ambos DC no muestran el mismo timestamp reciente, esperar unos minutos y repetir antes de avanzar — la sincronización hacia AADDS es asíncrona.

### 4.3 Rollout coordinado

Actualizar la identidad de App Pool en los 12 servidores dentro de la misma ventana, en el orden que resulte operativamente más simple (no hay dependencia de orden entre ellos). Por cada servidor:

1. IIS Manager → Application Pools → seleccionar el pool → Advanced Settings → Identity → Custom account → ingresar `smartit\itservices` (o `grupo.servicesit@smartfran.com`) y la nueva contraseña (copiada del secreto documentado, no retipeada).
2. Recycle del App Pool para validar el nuevo logon inmediatamente.
3. Confirmar que el sitio responde (no queda en estado "stopped" por fallo de logon).

### 4.4 Verificación final

Repetir el chequeo de `badPwdCount`/`lockoutTime` en ambos DC tras completar el rollout — debe permanecer estable (sin incrementos) una vez que todos los servidores quedaron alineados:

```powershell
foreach ($dc in "192.168.40.4","192.168.40.5") {
    $root = New-Object DirectoryServices.DirectoryEntry("LDAP://$dc/CN=appaccess,OU=AADDC Users,DC=smartit,DC=azure")
    $searcher = New-Object DirectoryServices.DirectorySearcher($root)
    $searcher.SearchScope = "Base"
    $searcher.PropertiesToLoad.AddRange(@("lockoutTime","badPwdCount"))
    $result = $searcher.FindOne()
    $lockoutTime = if ($result.Properties["lockouttime"].Count -gt 0) { [Int64]$result.Properties["lockouttime"][0] } else { 0 }
    "$dc -> badPwdCount: " + $result.Properties["badpwdcount"][0]
    if ($lockoutTime -ne 0) {
        "$dc -> LOCKED since: " + [DateTime]::FromFileTime($lockoutTime)
    } else {
        "$dc -> not locked"
    }
}
```

Complementar con el mapa de Zabbix que muestra el estado de todos los servicios de la flota: http://sf-monitoreo.smartfran.com:8080/zabbix.php?action=map.view&sysmapid=2 — confirmar que los 12 servicios IIS aparecen en verde antes de dar el rollout por cerrado.

## 5. Diagnóstico — scripts reutilizables

Todos estos scripts corren en cualquier servidor unido al dominio `smartit.azure`, sin necesidad del módulo RSAT `ActiveDirectory` (usan `System.DirectoryServices` directamente).

### 5.1 Localizar el objeto por UPN/mail (cuando el sAMAccountName no coincide con el UPN)

```powershell
$searcher = New-Object DirectoryServices.DirectorySearcher
$searcher.Filter = "(|(userPrincipalName=grupo.servicesit@smartfran.com)(mail=grupo.servicesit@smartfran.com)(proxyAddresses=smtp:grupo.servicesit@smartfran.com)(proxyAddresses=SMTP:grupo.servicesit@smartfran.com))"
$searcher.PropertiesToLoad.AddRange(@("distinguishedName","objectClass","sAMAccountName","userPrincipalName","pwdLastSet","whenChanged"))
$searcher.FindAll() | ForEach-Object {
    "DN: "   + $_.Properties["distinguishedname"]
    "Class: "+ $_.Properties["objectclass"]
    "sAM: "  + $_.Properties["samaccountname"]
    "UPN: "  + $_.Properties["userprincipalname"]
}
```

> No usar una búsqueda ANR (`anr=<término>`) como primer intento: ANR solo indexa `displayName`, `sAMAccountName`, `sn`, `givenName`, `legacyExchangeDN` y `proxyAddresses` — si el término buscado no aparece en ninguno de esos atributos, la búsqueda devuelve vacío sin error, dando una falsa impresión de que el objeto no existe.

### 5.2 Verificar bloqueo y `badPwdCount` por DC

```powershell
foreach ($dc in "192.168.40.4","192.168.40.5") {
    $root = New-Object DirectoryServices.DirectoryEntry("LDAP://$dc/CN=appaccess,OU=AADDC Users,DC=smartit,DC=azure")
    $searcher = New-Object DirectoryServices.DirectorySearcher($root)
    $searcher.SearchScope = "Base"
    $searcher.PropertiesToLoad.AddRange(@("lockoutTime","badPwdCount"))
    $result = $searcher.FindOne()
    $lockoutTime = if ($result.Properties["lockouttime"].Count -gt 0) { [Int64]$result.Properties["lockouttime"][0] } else { 0 }
    "$dc -> badPwdCount: " + $result.Properties["badpwdcount"][0]
    if ($lockoutTime -ne 0) {
        "$dc -> LOCKED since: " + [DateTime]::FromFileTime($lockoutTime)
    } else {
        "$dc -> not locked"
    }
}
```

> **No usar `[ADSI]"LDAP://..."` directo para leer `lockoutTime`.** Ese atributo es un `IADsLargeInteger` (objeto COM) cuando se accede vía `DirectoryEntry`/`[ADSI]`, y `[Int64]$de.Properties["lockoutTime"].Value` falla con `Cannot convert the "System.__ComObject" value...`. `DirectorySearcher` marshala el valor correctamente a un entero nativo — usar siempre esa vía para atributos de 64 bits.

### 5.3 Desbloquear la cuenta

```powershell
try {
    $de = New-Object DirectoryServices.DirectoryEntry("LDAP://192.168.40.4/CN=appaccess,OU=AADDC Users,DC=smartit,DC=azure")
    $de.Properties["lockoutTime"].Value = 0
    $de.CommitChanges()
    "Unlock succeeded"
} catch {
    "Unlock FAILED: " + $_.Exception.Message
}
```

Requiere permisos delegados de escritura sobre el objeto (grupo `AAD DC Administrators`). Un error aquí normalmente indica falta de ese permiso, no un problema técnico del script.

### 5.4 Probar la credencial de forma aislada (sin tocar IIS)

Antes de aplicar un cambio en IIS Manager, validar la credencial de forma aislada. Esto evita gastar intentos de logon (y por lo tanto `badPwdCount`) reconfigurando y recargando pools repetidamente:

```powershell
Start-Process cmd -Credential (Get-Credential smartit\itservices)
```

Escribir la contraseña una sola vez, a mano (no pegar) — descarta problemas de layout de teclado en caracteres especiales. Evitar `runas` para esta prueba: si existe una credencial cacheada en Credential Manager (`cmdkey /list`) para esa cuenta, `runas` la reutiliza en silencio sin volver a pedir contraseña, lo que puede llevar a conclusiones erróneas sobre si la contraseña nueva es correcta.

## 6. Errores conocidos y su lectura correcta

| Síntoma | Causa real | Cómo confirmarlo |
|---|---|---|
| IIS: "The specified password is invalid" | Frecuentemente **cuenta bloqueada**, no contraseña incorrecta — IIS no distingue ambos casos con claridad | Sección 5.2 |
| `runas` no pide contraseña | Credencial cacheada en Credential Manager reutilizada en silencio | `cmdkey /list` / usar `Start-Process -Credential` en su lugar |
| `net user <cuenta> /domain` → "user name could not be found" | `net user` requiere `sAMAccountName` exacto, no acepta UPN ni un valor supuesto incorrecto | Sección 5.1 para confirmar el `sAMAccountName` real |
| `badPwdCount` distinto entre los dos DC | Comportamiento esperado — este atributo no se replica entre réplicas | No es un hallazgo por sí solo; mirar `lockoutTime` (sí replicado) |
| Cuenta se vuelve a bloquear minutos después de desbloquearla | Otro servidor de la flota sigue autenticando con la contraseña anterior | Confirmar que los 12 servidores de la sección 2 estén alineados antes de dar el rollout por completado |

## 7. Referencias

- `operations/events/20260723_itservices_bloqueo_password/` — evento que originó este runbook.
- `operations/events/20260610_kerberos_rc4_aadds/` — AADDS123, dependencia crítica de `itservices` sobre cifrado Kerberos.
- `operations/events/20260710_sfdev_acceso_dc_azure/` — IPs y topología de los DC de AADDS.
- Mapa Zabbix — estado de todos los servicios: http://sf-monitoreo.smartfran.com:8080/zabbix.php?action=map.view&sysmapid=2
