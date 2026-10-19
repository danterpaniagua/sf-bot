# Event: 20261014_gitin2223_taskoperator-preprod-appsettings-xml (GITIN-2223)
# C7 - Agrega a Config\ConnectionStrings.config de PREPROD la entrada de EtlContext que tienen DEV y TEST02 y PREPROD no tiene.
#      La entrada se crea CLONANDO la entrada SpecContext del mismo archivo (mismo servidor, catalogo, usuario y contrasena de PREPROD)
#      y cambiando solo el atributo name; asi la contrasena nunca se imprime ni se escribe en otro lado.
#      Modos (parametro -Mode):
#        dry       (por defecto) NO escribe nada: muestra que se agregaria, con la contrasena enmascarada, y corre las guardas.
#        apply     respalda el archivo (ConnectionStrings.config.bak-GITIN-2223-<fecha>), agrega la entrada, valida que el XML parsea y que quedan 8 entradas;
#                  si algo falla, restaura el respaldo. NO reinicia el servicio (la configuracion se lee al iniciar; el reinicio es un paso aparte).
#        rollback  restaura el respaldo mas reciente.
#      Guardas: host SFDEV02, el archivo tiene exactamente 7 entradas, no existe ya una de EtlContext y existe la de SpecContext.
param([ValidateSet('dry', 'apply', 'rollback')][string]$Mode = 'dry')
$ErrorActionPreference = 'Stop'
$f = 'E:\SmartFran\PREPROD\SmartLoyalty.TaskOperatorService\Config\ConnectionStrings.config'
$etl = 'SmartFran.Business.Etl.Data.Context.EtlContext'
$tpl = 'SmartFran.Business.Spec.Data.Context.SpecContext'
$out = "C:\Temp\c7-$Mode.txt"
New-Item -ItemType Directory -Force -Path 'C:\Temp' | Out-Null
function Mask($t) { $t -replace '(?i)(password|pwd)\s*=\s*(''[^'']*''|"[^"]*"|[^;"'']+)', '$1=***' }
& {
  "host: $env:COMPUTERNAME | $(Get-Date -Format s) | modo: $Mode"
  if ($env:COMPUTERNAME -ne 'SFDEV02') { throw "GUARDA: este script es para SFDEV02, el host es $env:COMPUTERNAME" }
  if ($Mode -eq 'rollback') {
    $b = Get-ChildItem "$f.bak-GITIN-2223-*" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $b) { throw 'no hay respaldo' }
    Copy-Item $b.FullName $f -Force; "restaurado desde $($b.Name)"; return
  }
  $xml = New-Object System.Xml.XmlDocument; $xml.PreserveWhitespace = $true; $xml.Load($f)
  $adds = $xml.SelectNodes('/connectionStrings/add')
  "entradas actuales: $($adds.Count)"
  if ($adds.Count -ne 7) { throw "GUARDA: se esperaban 7 entradas, hay $($adds.Count)" }
  if ($xml.SelectSingleNode("/connectionStrings/add[@name='$etl']")) { throw 'GUARDA: ya existe la entrada de EtlContext' }
  $src = $xml.SelectSingleNode("/connectionStrings/add[@name='$tpl']")
  if (-not $src) { throw "GUARDA: no existe la entrada $tpl" }
  $new = $src.CloneNode($true); $new.SetAttribute('name', $etl)
  "se agregaria (contrasena enmascarada):"
  "  name=$($new.GetAttribute('name'))"
  "  connectionString=$(Mask $new.GetAttribute('connectionString'))"
  "  providerName=$($new.GetAttribute('providerName'))"
  if ($Mode -eq 'dry') { "simulacion: no se escribio nada"; return }
  $bak = "$f.bak-GITIN-2223-$(Get-Date -Format yyyyMMdd-HHmmss)"
  Copy-Item $f $bak; "respaldo: $bak"
  try {
    $ws = $xml.CreateWhitespace("`r`n    ")
    [void]$src.ParentNode.InsertAfter($ws, $adds[$adds.Count - 1])
    [void]$src.ParentNode.InsertAfter($new, $ws)
    $xml.Save($f)
    $chk = New-Object System.Xml.XmlDocument; $chk.Load($f)
    $n = $chk.SelectNodes('/connectionStrings/add').Count
    if ($n -ne 8 -or -not $chk.SelectSingleNode("/connectionStrings/add[@name='$etl']")) { throw "validacion fallo: $n entradas" }
    "aplicado: $n entradas, XML valido. Falta reiniciar el servicio SmartLoyalty.TaskOperator.Service.Preprod (paso aparte)."
  } catch { Copy-Item $bak $f -Force; "FALLO: $($_.Exception.Message); se restauro el respaldo" }
} *> $out
Get-Content $out
