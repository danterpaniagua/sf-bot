# Event: 20261014_gitin2223_taskoperator-preprod-appsettings-xml
# C4 - Solo lectura, en el servidor SFDEV02. No modifica nada. No imprime contrasenas: toda linea impresa pasa por Mask() y de las cadenas de conexion solo se extraen Server, Initial Catalog y User Id.
#      a) servicios SmartLoyalty.TaskOperator*: estado, cuenta que los ejecuta y ruta del ejecutable (a que carpeta de entorno apunta cada uno);
#      b) carpetas de entorno de E:\SmartFran y cuales tienen SmartLoyalty.TaskOperatorService;
#      c) por entorno: version y fecha del .exe, y de cada archivo de Config\ fecha de modificacion y hash SHA256 (8 primeros caracteres) para comparar entre entornos;
#      c2) por entorno: nombres de las cadenas de ConnectionStrings.config (solo el atributo name) y las 12 lineas de Unity.config desde el registro de EtlContext;
#      d) por entorno: servidor / catalogo / usuario de las cadenas de conexion (se lee como texto, por lo que tambien aparecen las lineas dentro de comentarios XML).
$root = 'E:\SmartFran'
$out = 'C:\Temp\c4-env-compare.txt'
New-Item -ItemType Directory -Force -Path 'C:\Temp' | Out-Null
function Mask($t) { $t -replace '(?i)(password|pwd)\s*=\s*(''[^'']*''|"[^"]*"|[^;"'']+)', '$1=***' }
& {
  "host: $env:COMPUTERNAME | $(Get-Date -Format s)"
  "== a) servicios TaskOperator"
  Get-CimInstance Win32_Service | Where-Object { $_.Name -like 'SmartLoyalty.TaskOperator*' } | Select-Object Name, State, StartName, PathName | Format-List | Out-String -Width 250
  "== b) carpetas de entorno en $root"
  Get-ChildItem $root -Directory | ForEach-Object { "{0} | TaskOperatorService: {1}" -f $_.Name, (Test-Path (Join-Path $_.FullName 'SmartLoyalty.TaskOperatorService')) }
  $envs = Get-ChildItem $root -Directory | Where-Object { Test-Path (Join-Path $_.FullName 'SmartLoyalty.TaskOperatorService') }
  foreach ($e in $envs) {
    $svc = Join-Path $e.FullName 'SmartLoyalty.TaskOperatorService'
    "== c) $($e.Name): .exe y Config"
    $exe = Join-Path $svc 'SmartFran.Front.TaskOperatorService.exe'
    if (-not (Test-Path $exe)) { $exe = (Get-ChildItem $svc -Filter '*TaskOperatorService.exe' | Select-Object -First 1).FullName }
    if ($exe) { $i = Get-Item $exe; "{0} | version {1} | {2}" -f $i.Name, $i.VersionInfo.FileVersion, $i.LastWriteTime }
    Get-ChildItem (Join-Path $svc 'Config') -Filter *.config -ErrorAction SilentlyContinue | ForEach-Object { "{0} | {1} | {2} | {3}" -f $_.Name, $_.Length, $_.LastWriteTime, (Get-FileHash $_.FullName -Algorithm SHA256).Hash.Substring(0, 8) }
    "== c2) $($e.Name): nombres de ConnectionStrings.config y registro de EtlContext en Unity.config"
    Select-String -Path (Join-Path $svc 'Config\ConnectionStrings.config') -Pattern 'name\s*=' -ErrorAction SilentlyContinue | ForEach-Object { "{0}: {1}" -f $_.LineNumber, ([regex]::Match($_.Line, 'name\s*=\s*"[^"]*"').Value) }
    $u = Join-Path $svc 'Config\Unity.config'
    if (Test-Path $u) {
      $ul = Get-Content $u
      $m = $ul | Select-String -SimpleMatch 'mapTo="EtlContext"' | Select-Object -First 1
      if ($m) {
        $n = $m.LineNumber
        $n..($n + 11) | ForEach-Object { "{0}: {1}" -f $_, (Mask ($ul[$_ - 1].Trim() -replace '^(.{220}).*', '$1')) }
      } else { "Unity.config: no se encontro el registro de EtlContext" }
    }
    "== d) $($e.Name): servidor / catalogo / usuario de las cadenas de conexion (sin contrasena)"
    Get-ChildItem (Join-Path $svc 'Config') -Filter *.config -ErrorAction SilentlyContinue | ForEach-Object {
      $f = $_.Name
      Select-String -Path $_.FullName -Pattern '(?i)(server|data source)\s*=' | ForEach-Object {
        $t = $_.Line
        $srv = [regex]::Match($t, '(?i)(server|data source)\s*=\s*([^;"'']+)').Groups[2].Value
        $cat = [regex]::Match($t, '(?i)initial catalog\s*=\s*([^;"'']+)').Groups[1].Value
        $usr = [regex]::Match($t, '(?i)user id\s*=\s*''?([^;"'']+)').Groups[1].Value
        "{0}:{1} | server={2} | catalog={3} | user={4}" -f $f, $_.LineNumber, $srv, $cat, $usr
      }
    }
  }
  "listo"
} *> $out
Get-Content $out
