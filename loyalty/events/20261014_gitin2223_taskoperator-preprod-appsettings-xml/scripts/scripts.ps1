# Event: 20261014_gitin2223_taskoperator-preprod-appsettings-xml
# C1 - Solo lectura, en el servidor PREPROD. No modifica nada.
#      Muestra host, fecha de modificacion del archivo, estado del servicio, la linea 132 y las lineas
#      que tienen un comentario XML con "--" adentro (o que termina en "-" antes de "-->").
#      Las lineas se recortan a 160 caracteres. Si alguna trae una clave o contrasena, enmascararla antes de pegar.
$f = 'E:\SmartFran\PREPROD\SmartLoyalty.TaskOperatorService\Config\AppSettings.config'
$out = 'C:\Temp\c1-taskoperator-appsettings.txt'
New-Item -ItemType Directory -Force -Path 'C:\Temp' | Out-Null
& {
  "host: $env:COMPUTERNAME | $(Get-Date -Format s)"
  Get-Item $f | Select-Object FullName, Length, LastWriteTime | Format-List | Out-String
  Get-CimInstance Win32_Service | Where-Object { $_.PathName -like '*SmartLoyalty.TaskOperatorService*' } | Select-Object Name, State, StartMode | Format-Table -AutoSize | Out-String
  $lines = Get-Content $f
  "lineas totales: $($lines.Count)"
  "== linea 132"
  "{0}: {1}" -f 132, ($lines[131] -replace '^(.{160}).*', '$1')
  "== lineas con comentario XML invalido (contiene '--' dentro o termina en '-' antes de '-->')"
  for ($i = 0; $i -lt $lines.Count; $i++) {
    foreach ($m in [regex]::Matches($lines[$i], '<!--(.*?)-->')) {
      if ($m.Groups[1].Value -match '--' -or $m.Groups[1].Value -match '-$') { "{0}: {1}" -f ($i + 1), ($lines[$i] -replace '^(.{160}).*', '$1'); break }
    }
  }
  "== comentarios sin cierre en la misma linea (revisar a mano)"
  for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '<!--' -and $lines[$i] -notmatch '-->') { "{0}: {1}" -f ($i + 1), ($lines[$i] -replace '^(.{160}).*', '$1') } }
  "listo"
} *> $out
Get-Content $out
