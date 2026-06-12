# Evento: 20260610_kerberos_rc4_aadds
# Plan de pruebas — Windows Server 2019 / IIS (ejecutar en SFCG-DEVO-TEST)
# Prerequisito: T1-T4 completados y svc-aestest con msDS-SupportedEncryptionTypes: 24 confirmado
# ⚠️ Los comandos de acción están marcados con ACTION

# === PRUEBA IIS — crear app pool con identidad AES-only ===

# T5 — Crear y arrancar app pool de prueba con identidad svc-aestest
# ⚠️ ACTION — crea e inicia un nuevo application pool en IIS de SFCG-DEVO-TEST
Import-Module WebAdministration
New-WebAppPool -Name "AESTestPool"
Set-ItemProperty "IIS:\AppPools\AESTestPool" -Name processModel.userName    -Value "SMARTIT\svc-aestest"
Set-ItemProperty "IIS:\AppPools\AESTestPool" -Name processModel.password     -Value "Aes@Test2026!"
Set-ItemProperty "IIS:\AppPools\AESTestPool" -Name processModel.identityType -Value 3
Start-WebAppPool -Name "AESTestPool"
Get-WebAppPoolState -Name "AESTestPool"
# Resultado esperado: State : Started

# === VERIFICACIÓN — tipo de cifrado del ticket Kerberos ===

# T6 — Mostrar tickets Kerberos activos en la máquina
# Buscar: Encryption type AES-256-CTS-HMAC-SHA1-96 (0x12) o AES-128-CTS-HMAC-SHA1-96 (0x11)
# Resultado NO aceptable: RSADSI RC4-HMAC(NT) (0x17)
klist

# T7 — Consultar el log de seguridad del DC por tickets emitidos a svc-aestest
# Event 4769 = solicitud de service ticket (Kerberos ST)
# Ticket Encryption Type: 0x12 = AES-256 ✓ | 0x11 = AES-128 ✓ | 0x17 = RC4 ✗
Get-WinEvent -LogName Security -FilterHashtable @{Id=4769; StartTime=(Get-Date).AddHours(-1)} |
  Where-Object { $_.Message -match "svc-aestest" } |
  Select-Object TimeCreated,
    @{N="TicketEncryptionType";E={ ($_.Message -split "`n" | Select-String "Ticket Encryption Type").Line.Trim() }},
    @{N="ServiceName";E={          ($_.Message -split "`n" | Select-String "Service Name").Line.Trim() }},
    @{N="ClientName";E={           ($_.Message -split "`n" | Select-String "Account Name").Line.Trim() }} |
  Format-Table -AutoSize

# === CRITERIOS DE APROBACIÓN ===
# T5: Get-WebAppPoolState devuelve "Started" sin error de credenciales
# T6: klist muestra etype 0x12 o 0x11 — NO debe aparecer 0x17
# T7: Event 4769 para svc-aestest muestra Ticket Encryption Type 0x12 o 0x11

# === LIMPIEZA — ejecutar solo después de confirmar T5-T7 ===

# T8b — Eliminar app pool de prueba de IIS
# ⚠️ ACTION — detiene y elimina AESTestPool
Stop-WebAppPool  -Name "AESTestPool"
Remove-WebAppPool -Name "AESTestPool"
