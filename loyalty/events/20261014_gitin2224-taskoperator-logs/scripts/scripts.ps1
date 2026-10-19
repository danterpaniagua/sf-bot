# Event: 20261014_gitin2224-taskoperator-logs (GITIN-2224)
# C1 - Solo lectura, en SFDEV02. Donde escribe hoy el TaskOperator de PREPROD: sus archivos de log, su configuracion de diagnostico y el Registro de eventos de Windows.
#      a) SystemDiagnostics.config de PREPROD (contrasenas enmascaradas); b) archivos .txt/.log de la carpeta del servicio con fecha y tamano (solo nombres, no contenido);
#      c) eventos de la bitacora Application de las ultimas 24 h que mencionan TaskOperator o "Service cannot be started" (mensaje cortado a 300 caracteres);
#      d) servicios TaskOperator y su cuenta. Salida: C:\Temp\c1-taskoperator-logs.txt
$dir = 'E:\SmartFran\PREPROD\SmartLoyalty.TaskOperatorService'
$out = 'C:\Temp\c1-taskoperator-logs.txt'
New-Item -ItemType Directory -Force -Path 'C:\Temp' | Out-Null
function Mask($t) { $t -replace '(?i)(password|pwd)\s*=\s*(''[^'']*''|"[^"]*"|[^;"'']+)', '$1=***' }
& {
  "host: $env:COMPUTERNAME | $(Get-Date -Format s)"
  "== a) Config\SystemDiagnostics.config"
  Get-Content "$dir\Config\SystemDiagnostics.config" | ForEach-Object { Mask $_ }
  "== b) archivos de log en la carpeta del servicio (nombre, tamano, fecha)"
  Get-ChildItem $dir -Recurse -Include *.log, *.txt -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 20 FullName, Length, LastWriteTime | Format-Table -AutoSize | Out-String -Width 250
  "== c) Registro de eventos Application, ultimas 24 h, que mencionan TaskOperator o Service cannot be started"
  Get-WinEvent -FilterHashtable @{ LogName = 'Application'; StartTime = (Get-Date).AddHours(-24) } -ErrorAction SilentlyContinue |
    Where-Object { $_.Message -match 'TaskOperator|Service cannot be started' -or $_.ProviderName -match 'TaskOperator' } | Select-Object -First 20 |
    ForEach-Object { "{0} | {1} | id {2} | {3}" -f $_.TimeCreated, $_.ProviderName, $_.Id, (Mask (($_.Message -replace '\s+', ' ') -replace '^(.{300}).*', '$1')) }
  "== d) servicios"
  Get-CimInstance Win32_Service | Where-Object { $_.Name -like 'SmartLoyalty.TaskOperator*' } | Select-Object Name, State, StartName | Format-Table -AutoSize | Out-String
  "listo"
} *> $out
Get-Content $out
