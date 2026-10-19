# GITIN-2250 — compara procesos w3wp, configuracion del app pool y CPU por proceso en un servidor WEBS (se ejecuta con "az vm run-command invoke"; salida corta). SOLO LECTURA.
# La CPU por proceso se mide con Get-Process (dos muestras de 10 s), SIN consultas WMI, para no cargar WmiPrvSE.
if ($env:COMPUTERNAME -notlike 'SFCG-WEBS-*') { "HOST INESPERADO: $env:COMPUTERNAME"; return }
$cores = [Environment]::ProcessorCount
"host: $env:COMPUTERNAME  $(Get-Date -Format 'MM-dd HH:mm:ss zzz')  nucleos: $cores  arranque: $((Get-Process -Id 4 -ErrorAction SilentlyContinue).StartTime.ToString('MM-dd HH:mm'))"
$a = @{}; Get-Process | ForEach-Object { $a[$_.Id] = @($_.ProcessName, $_.CPU) }
Start-Sleep -Seconds 10
"-- top 8 procesos por CPU en 10 s (100 = un nucleo) --"
Get-Process | ForEach-Object { if ($a.ContainsKey($_.Id)) { [pscustomobject]@{ N = $_.ProcessName; P = $_.Id; C = [math]::Round((($_.CPU - $a[$_.Id][1]) / 10) * 100); WS = [int]($_.WorkingSet64 / 1MB); T = $_.Threads.Count } } } |
  Sort-Object C -Descending | Select-Object -First 8 | ForEach-Object { '{0,-14} pid={1,-6} cpu={2,-4} ws={3,-5}MB thr={4}' -f $_.N, $_.P, $_.C, $_.WS, $_.T }
$appcmd = "$env:windir\system32\inetsrv\appcmd.exe"
if (Test-Path $appcmd) {
  "-- worker processes (appcmd list wp) --"; & $appcmd list wp | ForEach-Object { $_ -replace '\s+',' ' }
  "-- app pool SmartLoyalty.WebService --"
  foreach ($p in 'processModel.maxProcesses','processModel.idleTimeout','recycling.periodicRestart.time','recycling.periodicRestart.privateMemory','recycling.disallowOverlappingRotation','startMode','queueLength') {
    "{0} = {1}" -f $p, ((& $appcmd list apppool 'SmartLoyalty.WebService' "/text:$p") -join ',')
  }
}
