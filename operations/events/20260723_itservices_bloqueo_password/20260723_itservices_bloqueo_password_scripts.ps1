# itservices — Bloqueo recurrente por rotación de contraseña no coordinada en flota IIS
# Fecha: 2026-07-23
# Dominio: Azure AD DS smartit.azure — DC 192.168.40.4 / 192.168.40.5

# CX-01 — Búsqueda ANR (sin resultados)
$searcher = New-Object DirectoryServices.DirectorySearcher
$searcher.Filter = "(anr=servicesit)"
$searcher.PropertiesToLoad.AddRange(@("distinguishedName","objectClass","sAMAccountName","userPrincipalName","pwdLastSet","whenChanged","lastLogonTimestamp"))
$searcher.FindAll() | ForEach-Object {
    "DN: "   + $_.Properties["distinguishedname"]
    "Class: "+ $_.Properties["objectclass"]
    "sAM: "  + $_.Properties["samaccountname"]
    "UPN: "  + $_.Properties["userprincipalname"]
    if ($_.Properties["pwdlastset"].Count -gt 0) {
        "PwdLastSet: " + [DateTime]::FromFileTime([Int64]$_.Properties["pwdlastset"][0])
    }
    "WhenChanged: " + $_.Properties["whenchanged"]
    "-----"
}
# OUTPUT (2026-07-23):
# (sin resultados — ningún atributo indexado por ANR contiene "servicesit")

# CX-02 — Búsqueda dirigida por UPN/mail/proxyAddresses (objeto localizado)
$searcher = New-Object DirectoryServices.DirectorySearcher
$searcher.Filter = "(|(userPrincipalName=grupo.servicesit@smartfran.com)(mail=grupo.servicesit@smartfran.com)(proxyAddresses=smtp:grupo.servicesit@smartfran.com)(proxyAddresses=SMTP:grupo.servicesit@smartfran.com))"
$searcher.PropertiesToLoad.AddRange(@("distinguishedName","objectClass","sAMAccountName","userPrincipalName","pwdLastSet","whenChanged"))
$searcher.FindAll() | ForEach-Object {
    "DN: "   + $_.Properties["distinguishedname"]
    "Class: "+ $_.Properties["objectclass"]
    "sAM: "  + $_.Properties["samaccountname"]
    "UPN: "  + $_.Properties["userprincipalname"]
    if ($_.Properties["pwdlastset"].Count -gt 0) {
        "PwdLastSet: " + [DateTime]::FromFileTime([Int64]$_.Properties["pwdlastset"][0])
    }
    "WhenChanged: " + $_.Properties["whenchanged"]
    "-----"
}
# OUTPUT (2026-07-23):
# DN: CN=appaccess,OU=AADDC Users,DC=smartit,DC=azure
# Class: top person organizationalPerson user
# sAM: itservices
# UPN: grupo.servicesit@smartfran.com
# PwdLastSet: 07/23/2026 10:42:29
# WhenChanged: 07/23/2026 10:49:48

# CX-03 — Intento net user con UPN (fallo de sintaxis)
net user grupo.servicesit@smartfran.com /domain
# OUTPUT (2026-07-23):
# net : The syntax of this command is:
# NET USER [username [password | *] [options]] [/DOMAIN] ...
# (net user no acepta UPN, requiere sAMAccountName)

# CX-04 — Intento net user con sAMAccountName supuesto (incorrecto en ese momento)
net user grupo.servicesit /domain
# OUTPUT (2026-07-23):
# net : The user name could not be found.

# CX-05 — Verificación de credenciales cacheadas (descartar causa de runas silencioso)
cmdkey /list
# OUTPUT (2026-07-23):
# Target: MicrosoftAccount:target=SSO_POP_Device (User: 02hlrfolybogbaxy)
# Target: WindowsLive:target=virtualapp/didlogical (User: 02hlrfolybogbaxy)
# Target: Domain:target=strgsqlbkp.file.core.windows.net (User: localhost\strgsqlbkp)
# (ninguna entrada relacionada con itservices)

# CX-06 — Prueba de credencial aislada (primer hallazgo del bloqueo real)
Start-Process cmd -Credential (Get-Credential smartit\itservices)
# OUTPUT (2026-07-23):
# Start-Process : This command cannot be run due to the error: The referenced
# account is currently locked out and may not be logged on to.

# CX-07 — Verificación lockoutTime/badPwdCount por DC (script con bug de casteo COM)
foreach ($dc in "192.168.40.4","192.168.40.5") {
    $de = New-Object DirectoryServices.DirectoryEntry("LDAP://$dc/CN=appaccess,OU=AADDC Users,DC=smartit,DC=azure")
    $lockoutTime = [Int64]$de.Properties["lockoutTime"].Value
    $badPwd = $de.Properties["badPwdCount"].Value
    "$dc -> lockoutTime: $lockoutTime  badPwdCount: $badPwd"
    if ($lockoutTime -ne 0) {
        "$dc -> Locked since: " + [DateTime]::FromFileTime($lockoutTime)
    }
}
# OUTPUT (2026-07-23):
# Cannot convert the "System.__ComObject" value of type "System.__ComObject" to type "System.Int64".
# (bug: [ADSI]/DirectoryEntry expone lockoutTime como IADsLargeInteger COM, no castea directo)
# 192.168.40.4 -> lockoutTime:   badPwdCount: 5
# 192.168.40.4 -> Locked since: 01/01/1601 00:00:00  (valor corrupto por el bug de arriba)
# 192.168.40.5 -> lockoutTime:   badPwdCount: 0
# 192.168.40.5 -> Locked since: 01/01/1601 00:00:00  (valor corrupto por el bug de arriba)

# CX-08 — Verificación corregida (DirectorySearcher marshaling correcto)
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
# OUTPUT (2026-07-23):
# 192.168.40.4 -> badPwdCount: 5
# 192.168.40.4 -> LOCKED since: 07/23/2026 11:04:21
# 192.168.40.5 -> badPwdCount: 0
# 192.168.40.5 -> LOCKED since: 07/23/2026 11:04:21
# (lockoutTime idéntico en ambas réplicas: replicación urgente correcta;
#  badPwdCount diverge porque no se replica entre DCs — comportamiento nativo de AD)

# CX-09 — Desbloqueo de cuenta sobre 192.168.40.4
try {
    $de = New-Object DirectoryServices.DirectoryEntry("LDAP://192.168.40.4/CN=appaccess,OU=AADDC Users,DC=smartit,DC=azure")
    $de.Properties["lockoutTime"].Value = 0
    $de.CommitChanges()
    "Unlock succeeded"
} catch {
    "Unlock FAILED: " + $_.Exception.Message
}
# OUTPUT (2026-07-23):
# Unlock succeeded

# CX-10 — Reverificación post-desbloqueo (mismo script que CX-08)
# OUTPUT (2026-07-23):
# 192.168.40.4 -> badPwdCount: 2
# 192.168.40.4 -> not locked
# 192.168.40.5 -> badPwdCount: 0
# 192.168.40.5 -> not locked
# (badPwdCount ya en 2 sin intervención manual adicional -> reintentos automáticos
#  activos desde servidores de la flota aún configurados con la contraseña anterior)

# Resultado reportado por el operador: la cuenta volvió a bloquearse minutos después
# de CX-10, confirmando que otros servidores de la flota siguen autenticando con la
# contraseña previa. Resuelto de forma puntual tras un nuevo desbloqueo (no se
# registró un script adicional para ese paso dentro de esta sesión).
