# GITIN-2250 — compact triage de SFCG-WEBS-02 (< 4 KB de salida: az vm run-command solo devuelve los ultimos ~4096 bytes). SOLO LECTURA.
if ($env:COMPUTERNAME -ne 'SFCG-WEBS-02') { throw "Host equivocado: $env:COMPUTERNAME" }
"host=$env:COMPUTERNAME ahora=$(Get-Date -Format 's') CPU_total%=$((Get-CimInstance Win32_PerfFormattedData_PerfOS_Processor -Filter "Name='_Total'").PercentProcessorTime)"
"== top 10 procesos por CPU_pct (100 = un nucleo; 2 nucleos) =="
$cim = @{}
Get-CimInstance Win32_Process | ForEach-Object { $cim[[int]$_.ProcessId] = $_ }
Get-CimInstance Win32_PerfFormattedData_PerfProc_Process | Where-Object { $_.IDProcess -ne 0 -and $_.Name -ne '_Total' -and $_.Name -ne 'Idle' } |
  Sort-Object PercentProcessorTime -Descending | Select-Object -First 10 | ForEach-Object {
    $c = $cim[[int]$_.IDProcess]; $pool = ''
    if ($c -and $c.CommandLine -match '-ap\s+"([^"]+)"') { $pool = $matches[1] }
    '{0,6} {1,-14} cpu={2,3} ws={3,4}MB thr={4,3} {5}' -f $_.IDProcess, $_.Name, $_.PercentProcessorTime, [int]($_.WorkingSetPrivate/1MB), $_.ThreadCount, $pool
  }
"== w3wp: pool, pid, solicitudes en vuelo por proceso (appcmd list wp) =="
& "$env:windir\system32\inetsrv\appcmd.exe" list wp
"== solicitudes en ejecucion (WebAdministration Get-WebRequest) =="
try { Import-Module WebAdministration -ErrorAction Stop; Get-WebRequest | Select-Object -First 12 | ForEach-Object { '{0} {1}ms {2} {3}' -f $_.processId, $_.timeElapsed, $_.verb, $_.url } } catch { "Get-WebRequest fallo: $($_.Exception.Message)" }
