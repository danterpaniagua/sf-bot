# Event: 20261016_unity-config-consistencia-zabbix. SOLO LECTURA. Se ejecuta en el servidor via "az vm run-command invoke" (cuenta SYSTEM).
# Para cada carpeta de aplicacion SmartLoyalty.* en C:\SmartFran, D:\ y E:\ muestra (una linea por carpeta, separada por tabuladores):
#   servidor | carpeta | Config\Unity.config existe | tamano | ultima escritura UTC | MD5 | healthcheck.ashx existe | MD5 del healthcheck.ashx (en la raiz de la carpeta)
# MD5 porque es lo que calcula el agente de Zabbix con vfs.file.md5sum (asi los valores se pueden comparar directamente). No imprime contenido de ningun archivo.
"HOST: $env:COMPUTERNAME"
$roots = @('C:\SmartFran', 'D:\', 'E:\')
$rows = foreach ($r in $roots) {
  if (-not (Test-Path -LiteralPath $r)) { continue }
  Get-ChildItem -LiteralPath $r -Directory -Filter 'SmartLoyalty.*' -ErrorAction SilentlyContinue | ForEach-Object {
    $dir  = $_.FullName
    $unity = Join-Path $dir 'Config\Unity.config'
    $hc    = Join-Path $dir 'healthcheck.ashx'
    $u = Get-Item -LiteralPath $unity -ErrorAction SilentlyContinue
    $h = Get-Item -LiteralPath $hc -ErrorAction SilentlyContinue
    $others = @(Get-ChildItem -LiteralPath (Join-Path $dir 'Config') -Filter 'Unity*.config' -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne 'Unity.config' } | ForEach-Object { $_.Name }) -join ','
    [pscustomobject]@{
      Servidor = $env:COMPUTERNAME
      Carpeta  = $dir
      Unity    = [bool]$u
      Tamano   = if ($u) { $u.Length } else { '' }
      Escrito  = if ($u) { $u.LastWriteTimeUtc.ToString('yyyy-MM-ddTHH:mm:ssZ') } else { '' }
      UnityMD5 = if ($u) { (Get-FileHash -LiteralPath $unity -Algorithm MD5).Hash } else { '' }
      Hc       = [bool]$h
      HcMD5    = if ($h) { (Get-FileHash -LiteralPath $hc -Algorithm MD5).Hash } else { '' }
      OtrosUnity = $others
    }
  }
}
if (-not $rows) { "sin carpetas SmartLoyalty.* en C:\SmartFran, D:\ ni E:\"; return }
"Servidor`tCarpeta`tUnity.config`tTamano`tEscrito(UTC)`tUnityMD5`thealthcheck.ashx`tHcMD5`tOtrosUnity*.config"
foreach ($x in $rows) { "{0}`t{1}`t{2}`t{3}`t{4}`t{5}`t{6}`t{7}`t{8}" -f $x.Servidor, $x.Carpeta, $x.Unity, $x.Tamano, $x.Escrito, $x.UnityMD5, $x.Hc, $x.HcMD5, $x.OtrosUnity }
