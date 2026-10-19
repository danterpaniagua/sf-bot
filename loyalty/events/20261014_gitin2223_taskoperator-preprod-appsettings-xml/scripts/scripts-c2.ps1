# Event: 20261014_gitin2223_taskoperator-preprod-appsettings-xml
# C2 - Solo lectura, en el servidor PREPROD de TaskOperator. No modifica nada.
#      a) host y fecha; b) si Config\AppSettings.config se puede parsear como XML hoy (el primer error era un comentario invalido en la linea 132);
#      c) archivos .config del servicio con fecha de modificacion; d) lineas con cadenas de conexion (Data Source / Server=) con la contrasena enmascarada;
#      e) para cada servidor distinto: resolucion DNS y prueba del puerto 1433 (una instancia con nombre usa un puerto dinamico via SQL Browser, UDP 1434; esa parte no se prueba aca).
#      Las lineas se leen como texto, no como XML, para que funcione aunque el XML siga roto. Contrasenas (Password=, Pwd=) se enmascaran antes de imprimir.
$dir = 'E:\SmartFran\PREPROD\SmartLoyalty.TaskOperatorService'
$out = 'C:\Temp\c2-taskoperator-sql.txt'
New-Item -ItemType Directory -Force -Path 'C:\Temp' | Out-Null
& {
  "host: $env:COMPUTERNAME | $(Get-Date -Format s)"
  "== b) parseo XML de Config\AppSettings.config"
  try { [void][xml](Get-Content "$dir\Config\AppSettings.config" -Raw -ErrorAction Stop); "XML valido" } catch { "XML con error: " + $_.Exception.Message }
  "== c) archivos .config"
  Get-ChildItem $dir -Recurse -Include *.config -ErrorAction SilentlyContinue | Select-Object FullName, Length, LastWriteTime | Format-Table -AutoSize | Out-String -Width 250
  "== d) cadenas de conexion (contrasena enmascarada)"
  $hosts = @()
  Get-ChildItem $dir -Recurse -Include *.config -ErrorAction SilentlyContinue | ForEach-Object {
    $f = $_.FullName
    Select-String -Path $f -Pattern 'Data Source|Server\s*=|connectionString|initial catalog|database\s*=' | ForEach-Object {
      $l = ($_.Line.Trim() -replace '(?i)(password|pwd)\s*=\s*(''[^'']*''|"[^"]*"|[^;"'']+)', '$1=***')
      "{0}:{1}: {2}" -f ($f -replace [regex]::Escape($dir), '.'), $_.LineNumber, ($l -replace '^(.{300}).*', '$1')
      foreach ($m in [regex]::Matches($_.Line, '(?i)(data source|server)\s*=\s*([^;"'']+)')) { $hosts += $m.Groups[2].Value.Trim() }
    }
  }
  "== e) servidores distintos: DNS y puerto 1433"
  $hosts | Sort-Object -Unique | ForEach-Object {
    $h = ($_ -replace '^(tcp:)', '' -replace '\\.*$', '' -replace ',.*$', '')
    $inst = if ($_ -match '\\') { 'instancia con nombre' } else { 'sin instancia' }
    $dns = try { (Resolve-DnsName $h -ErrorAction Stop | Where-Object IPAddress | Select-Object -First 1 -ExpandProperty IPAddress) } catch { 'NO RESUELVE' }
    $tcp = try { (Test-NetConnection $h -Port 1433 -WarningAction SilentlyContinue).TcpTestSucceeded } catch { 'error' }
    "{0} | {1} | dns={2} | tcp1433={3}" -f $_, $inst, $dns, $tcp
  }
  "listo"
} *> $out
Get-Content $out
