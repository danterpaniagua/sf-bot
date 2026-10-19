# Event: 20261014_gitin2223_taskoperator-preprod-appsettings-xml
# C5 - Solo lectura, en SFDEV02. No modifica nada. Busca la version anterior de la linea 132 de AppSettings.config (comentario XML invalido del primer error).
#      a) en todos los entornos de E:\SmartFran, lineas de AppSettings.config que contienen un comentario con "v1" o con "--" (texto crudo, con numero de linea);
#      b) copias o respaldos AppSettings.config* en E:\SmartFran con fecha y tamano;
#      c) si Windows conserva versiones anteriores (copias VSS) de la unidad E: (solo lista; no las lee).
#      Ninguna linea impresa pasa por claves: solo se imprimen lineas que contienen "<!--", y se enmascara Password=/Pwd= por si acaso.
$root = 'E:\SmartFran'
$out = 'C:\Temp\c5-line132.txt'
New-Item -ItemType Directory -Force -Path 'C:\Temp' | Out-Null
function Mask($t) { $t -replace '(?i)(password|pwd)\s*=\s*(''[^'']*''|"[^"]*"|[^;"'']+)', '$1=***' }
& {
  "host: $env:COMPUTERNAME | $(Get-Date -Format s)"
  "== a) comentarios con version o con '--' en AppSettings.config de cada entorno"
  Get-ChildItem $root -Recurse -Filter 'AppSettings.config' -ErrorAction SilentlyContinue | ForEach-Object {
    $f = $_.FullName
    "-- $f ($($_.LastWriteTime))"
    Select-String -Path $f -Pattern '<!--.*(v\d|--.*--)' | ForEach-Object { "{0}: {1}" -f $_.LineNumber, (Mask ($_.Line -replace '^(.{200}).*', '$1')) }
  }
  "== b) copias y respaldos de AppSettings.config*"
  Get-ChildItem $root -Recurse -Filter 'AppSettings.config*' -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne 'AppSettings.config' } | Select-Object FullName, Length, LastWriteTime | Format-Table -AutoSize | Out-String -Width 250
  "== c) copias VSS de la unidad E:"
  (vssadmin list shadows /for=E: 2>&1 | Select-String 'Creation Time|Shadow Copy Volume|No items') | ForEach-Object { $_.Line.Trim() }
  "listo"
} *> $out
Get-Content $out
