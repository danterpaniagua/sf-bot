# GITIN-2250 — triage remoto de SFCG-WEBS-02 (se ejecuta con "az vm run-command invoke"; devuelve como maximo ~4 KB, por eso la salida es corta). SOLO LECTURA.
if ($env:COMPUTERNAME -ne 'SFCG-WEBS-02') { "HOST EQUIVOCADO: $env:COMPUTERNAME"; return }
"host: $env:COMPUTERNAME  $(Get-Date -Format 'MM-dd HH:mm:ss zzz')  arranque: $((Get-CimInstance Win32_OperatingSystem).LastBootUpTime.ToString('MM-dd HH:mm'))"
"nucleos: $((Get-CimInstance Win32_ComputerSystem).NumberOfLogicalProcessors)  CPU total %: $((Get-CimInstance Win32_PerfFormattedData_PerfOS_Processor -Filter "Name='_Total'").PercentProcessorTime)"
$cim = @{}; Get-CimInstance Win32_Process | ForEach-Object { $cim[[int]$_.ProcessId] = $_.CommandLine }
"-- top 12 procesos por CPU % (100 = un nucleo) --"
Get-CimInstance Win32_PerfFormattedData_PerfProc_Process | Where-Object { $_.Name -notin '_Total','Idle' } | Sort-Object PercentProcessorTime -Descending | Select-Object -First 12 | ForEach-Object {
  $pool = ''; if ($_.Name -like 'w3wp*' -and $cim[[int]$_.IDProcess] -match '-ap\s+"([^"]+)"') { $pool = $matches[1] }
  '{0,-18} pid={1,-6} cpu={2,-4} ws={3,-5}MB thr={4,-4} {5}' -f $_.Name, $_.IDProcess, $_.PercentProcessorTime, [int]($_.WorkingSet/1MB), $_.ThreadCount, $pool
}
"-- cola de CPU --"; (Get-CimInstance Win32_PerfFormattedData_PerfOS_System).ProcessorQueueLength
"-- healthcheck local (lo que hace el sondeo del balanceador) --"
$sw = [Diagnostics.Stopwatch]::StartNew()
try { $r = Invoke-WebRequest -Uri 'http://localhost:8080/healthcheck.ashx' -UseBasicParsing -TimeoutSec 40; "HTTP $($r.StatusCode) en $($sw.ElapsedMilliseconds) ms" } catch { "ERROR tras $($sw.ElapsedMilliseconds) ms: $($_.Exception.Message)" }
$appcmd = "$env:windir\system32\inetsrv\appcmd.exe"
if (Test-Path $appcmd) {
  "-- peticiones IIS en curso --"
  $req = @(& $appcmd list requests); "total: $($req.Count)"
  # solo metodo, ruta (sin query string) y tiempo; sin IP de cliente
  $req | Select-Object -First 8 | ForEach-Object { if ($_ -match 'url:(\w+) ([^\s?,)]+).*?time:(\d+)') { "{0} {1} {2} ms" -f $matches[1], $matches[2], $matches[3] } }
}
