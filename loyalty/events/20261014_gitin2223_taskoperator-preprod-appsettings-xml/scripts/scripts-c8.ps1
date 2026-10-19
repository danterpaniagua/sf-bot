# Event: 20261014_gitin2223_taskoperator-preprod-appsettings-xml (GITIN-2223)
# C8 - Solo lectura, en SFDEV02. La guarda de C7 encontro 8 entradas en PREPROD\Config\ConnectionStrings.config (C4 habia mostrado 7).
#      Muestra: fecha y tamano actuales del archivo, nombres de las entradas, si existe la de EtlContext, respaldos/copias en la carpeta Config,
#      y desde cuando corre cada servicio TaskOperator (para ver si se reinicio despues del cambio del archivo). No imprime cadenas de conexion.
$cfg = 'E:\SmartFran\PREPROD\SmartLoyalty.TaskOperatorService\Config'
$out = 'C:\Temp\c8-connstrings-state.txt'
New-Item -ItemType Directory -Force -Path 'C:\Temp' | Out-Null
& {
  "host: $env:COMPUTERNAME | $(Get-Date -Format s)"
  "== archivo"
  Get-Item "$cfg\ConnectionStrings.config" | ForEach-Object { "{0} | {1} bytes | escrito {2} | sha256 {3}" -f $_.Name, $_.Length, $_.LastWriteTime, (Get-FileHash $_.FullName -Algorithm SHA256).Hash.Substring(0, 8) }
  "== entradas (solo name)"
  Select-String -Path "$cfg\ConnectionStrings.config" -Pattern 'name\s*=' | ForEach-Object { "{0}: {1}" -f $_.LineNumber, ([regex]::Match($_.Line, 'name\s*=\s*"[^"]*"').Value) }
  "== archivos en Config (nombre, tamano, fecha)"
  Get-ChildItem $cfg | Sort-Object LastWriteTime -Descending | Select-Object Name, Length, LastWriteTime | Format-Table -AutoSize | Out-String -Width 200
  "== servicios TaskOperator: proceso y hora de inicio"
  Get-CimInstance Win32_Service | Where-Object { $_.Name -like 'SmartLoyalty.TaskOperator*' } | ForEach-Object {
    $p = if ($_.ProcessId) { (Get-Process -Id $_.ProcessId -ErrorAction SilentlyContinue).StartTime } else { $null }
    "{0} | {1} | proceso iniciado {2}" -f $_.Name, $_.State, $p
  }
  "listo"
} *> $out
Get-Content $out
