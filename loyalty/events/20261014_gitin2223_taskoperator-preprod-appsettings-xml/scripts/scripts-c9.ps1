# Event: 20261014_gitin2223_taskoperator-preprod-appsettings-xml (GITIN-2223)
# C9 - Solo lectura, en SFDEV02. No imprime contrasenas ni las compara por hash: solo muestra servidor/catalogo/usuario y resultados si/no.
#      a) hora de inicio del proceso de cada servicio TaskOperator (Win32_Process.CreationDate; Get-Process.StartTime devolvio vacio en C8):
#         sirve para saber si PREPROD se reinicio despues del cambio de ConnectionStrings.config (14:16:28);
#      b) la entrada EtlContext de PREPROD y la de TEST02: nombres de atributos, providerName, servidor, catalogo, usuario y flags de la cadena;
#      c) si la cadena de EtlContext de PREPROD es igual a la de SpecContext del mismo archivo (si/no) y si el atributo providerName coincide con TEST02 (si/no).
$etl = 'SmartFran.Business.Etl.Data.Context.EtlContext'
$spec = 'SmartFran.Business.Spec.Data.Context.SpecContext'
$out = 'C:\Temp\c9-etl-entry.txt'
New-Item -ItemType Directory -Force -Path 'C:\Temp' | Out-Null
function Describe($path, $label) {
  $x = New-Object System.Xml.XmlDocument; $x.Load($path)
  $n = $x.SelectSingleNode("/connectionStrings/add[@name='$etl']")
  if (-not $n) { "$label : sin entrada de EtlContext"; return }
  $cs = $n.GetAttribute('connectionString')
  $get = { param($k) [regex]::Match($cs, "(?i)$k\s*=\s*'?([^;']+)").Groups[1].Value }
  "{0} : atributos={1} | providerName={2} | server={3} | catalog={4} | user={5} | otras claves de la cadena={6}" -f $label, (($n.Attributes | ForEach-Object { $_.Name }) -join ','), $n.GetAttribute('providerName'), (& $get 'server'), (& $get 'initial catalog'), (& $get 'user id'),
    ((($cs -split ';') | ForEach-Object { ($_ -split '=')[0].Trim() } | Where-Object { $_ -and $_ -notmatch '(?i)^(password|pwd)$' }) -join ',')
}
& {
  "host: $env:COMPUTERNAME | $(Get-Date -Format s)"
  "== a) servicios: estado y hora de inicio del proceso"
  Get-CimInstance Win32_Service | Where-Object { $_.Name -like 'SmartLoyalty.TaskOperator*' } | ForEach-Object {
    $p = if ($_.ProcessId) { (Get-CimInstance Win32_Process -Filter "ProcessId=$($_.ProcessId)").CreationDate } else { $null }
    "{0} | {1} | proceso iniciado {2}" -f $_.Name, $_.State, $p
  }
  "referencia: ConnectionStrings.config de PREPROD escrito " + (Get-Item 'E:\SmartFran\PREPROD\SmartLoyalty.TaskOperatorService\Config\ConnectionStrings.config').LastWriteTime
  "== b) entrada EtlContext por entorno"
  Describe 'E:\SmartFran\PREPROD\SmartLoyalty.TaskOperatorService\Config\ConnectionStrings.config' 'PREPROD'
  Describe 'E:\SmartFran\TEST02\SmartLoyalty.TaskOperatorService\Config\ConnectionStrings.config' 'TEST02'
  "== c) comparaciones (si/no, sin mostrar valores)"
  $xp = New-Object System.Xml.XmlDocument; $xp.Load('E:\SmartFran\PREPROD\SmartLoyalty.TaskOperatorService\Config\ConnectionStrings.config')
  $xt = New-Object System.Xml.XmlDocument; $xt.Load('E:\SmartFran\TEST02\SmartLoyalty.TaskOperatorService\Config\ConnectionStrings.config')
  $pe = $xp.SelectSingleNode("/connectionStrings/add[@name='$etl']"); $ps = $xp.SelectSingleNode("/connectionStrings/add[@name='$spec']"); $te = $xt.SelectSingleNode("/connectionStrings/add[@name='$etl']")
  if ($pe -and $ps) { "cadena de EtlContext igual a la de SpecContext en PREPROD: " + $(if ($pe.GetAttribute('connectionString') -ceq $ps.GetAttribute('connectionString')) { 'si' } else { 'no' }) }
  if ($pe -and $te) { "providerName de EtlContext igual entre PREPROD y TEST02: " + $(if ($pe.GetAttribute('providerName') -eq $te.GetAttribute('providerName')) { 'si' } else { 'no' }) }
  "listo"
} *> $out
Get-Content $out
