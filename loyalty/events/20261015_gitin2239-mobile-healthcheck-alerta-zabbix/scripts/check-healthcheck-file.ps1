# Event: 20261015_gitin2239-mobile-healthcheck-alerta-zabbix (GITIN-2239). SOLO LECTURA. Se ejecuta en el servidor via "az vm run-command invoke" (cuenta SYSTEM).
# Muestra: nombre del servidor, servicio de Zabbix y su cuenta, si el archivo existe en cada ruta candidata (Test-Path) y lo que responde el propio agente a vfs.file.exists, y las lineas AllowKey/DenyKey de su configuracion.
"HOST: $env:COMPUTERNAME"
"--- servicio Zabbix"
Get-CimInstance Win32_Service | Where-Object { $_.Name -like 'Zabbix*' } | Select-Object Name, StartName, State | Format-List | Out-String
$p = (Get-Process zabbix_agent* -ErrorAction SilentlyContinue | Select-Object -First 1).Path
"proceso del agente: $p"
$paths = @('D:\SmartLoyalty.MobileAppService\healthcheck.ashx','D:\SmartLoyalty.WebServiceV2\healthcheck.ashx','E:\SmartLoyalty.WebServiceV2\healthcheck.ashx')
"--- Test-Path (como SYSTEM)"
foreach ($f in $paths) { "{0} -> {1}" -f $f, (Test-Path -LiteralPath $f) }
if ($p) {
  $conf = Join-Path (Split-Path $p) 'zabbix_agent2.conf'
  "--- configuracion: $conf existe: $(Test-Path $conf)"
  if (Test-Path $conf) { Select-String -Path $conf -Pattern '^\s*(AllowKey|DenyKey|EnableRemoteCommands|LogRemoteCommands)' | ForEach-Object { $_.Line } }
  "--- respuesta del agente (-t) con la ruta literal"
  foreach ($f in $paths) { "{0}" -f $f; & $p -t ("vfs.file.exists[{0}]" -f $f) -c $conf 2>&1 | Out-String }
}
