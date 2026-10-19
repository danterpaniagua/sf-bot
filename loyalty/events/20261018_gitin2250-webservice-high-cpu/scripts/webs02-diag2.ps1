# GITIN-2250 — que hace w3wp en SFCG-WEBS-02. SOLO LECTURA. Salida compacta (< 4 KB: az vm run-command devuelve solo los ultimos ~4096 bytes).
# No imprime query strings ni IPs de cliente: solo cs-uri-stem.
if ($env:COMPUTERNAME -ne 'SFCG-WEBS-02') { throw "Host equivocado: $env:COMPUTERNAME" }
"host=$env:COMPUTERNAME ahora=$(Get-Date -Format 's') CPU_total%=$((Get-CimInstance Win32_PerfFormattedData_PerfOS_Processor -Filter "Name='_Total'").PercentProcessorTime)"
$pidTop = (Get-CimInstance Win32_PerfFormattedData_PerfProc_Process | Where-Object { $_.Name -like 'w3wp*' } | Sort-Object PercentProcessorTime -Descending | Select-Object -First 1).IDProcess
"== hilos de w3wp pid=$pidTop (delta CPU en 3 s, top 6; ms de CPU) =="
$a = @{}; (Get-Process -Id $pidTop).Threads | ForEach-Object { $a[$_.Id] = $_.TotalProcessorTime.TotalMilliseconds }
Start-Sleep -Seconds 3
(Get-Process -Id $pidTop).Threads | ForEach-Object { [pscustomobject]@{ Tid = $_.Id; Ms = [int]($_.TotalProcessorTime.TotalMilliseconds - $a[$_.Id]); State = $_.ThreadState } } |
  Sort-Object Ms -Descending | Select-Object -First 6 | ForEach-Object { '  tid={0} ms={1} {2}' -f $_.Tid, $_.Ms, $_.State }
"== contadores .NET / ASP.NET =="
$ctr = '\.NET CLR Memory(w3wp*)\Process ID','\.NET CLR Memory(w3wp*)\% Time in GC','\.NET CLR Memory(w3wp*)\# Gen 2 Collections','\.NET CLR Exceptions(w3wp*)\# of Exceps Thrown / sec','\.NET CLR LocksAndThreads(w3wp*)\Contention Rate / sec','\ASP.NET Applications(__Total__)\Requests Executing','\ASP.NET\Requests Queued'
try { (Get-Counter -Counter $ctr -ErrorAction SilentlyContinue).CounterSamples | ForEach-Object { '  {0} = {1:N1}' -f ($_.Path -replace '^\\\\[^\\]+',''), $_.CookedValue } } catch { "Get-Counter fallo: $($_.Exception.Message)" }
"== IIS log, ultimos 5 min =="
$f = Get-ChildItem 'C:\inetpub\logs\LogFiles' -Recurse -Filter *.log -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $f) { 'sin logs en C:\inetpub\logs\LogFiles' } else {
  $lines = Get-Content $f.FullName -Tail 6000
  $fields = (($lines | Where-Object { $_ -like '#Fields:*' } | Select-Object -Last 1) -replace '^#Fields: ','') -split ' '
  $iT = $fields.IndexOf('time'); $iU = $fields.IndexOf('cs-uri-stem'); $iS = $fields.IndexOf('sc-status'); $iM = $fields.IndexOf('time-taken')
  $min = (Get-Date).ToUniversalTime().AddMinutes(-5).ToString('HH:mm:ss')
  $rows = $lines | Where-Object { $_ -notlike '#*' } | ForEach-Object { $p = $_ -split ' '; if ($p.Count -gt $iM -and $p[$iT] -ge $min) { [pscustomobject]@{ U = $p[$iU]; S = $p[$iS]; M = [int]$p[$iM] } } }
  "archivo=$($f.Name) filas_5min=$(@($rows).Count)"
  "-- por tiempo total (ms) --"
  $rows | Group-Object U | ForEach-Object { [pscustomobject]@{ U = $_.Name; N = $_.Count; Sum = ($_.Group | Measure-Object M -Sum).Sum; Max = ($_.Group | Measure-Object M -Maximum).Maximum } } |
    Sort-Object Sum -Descending | Select-Object -First 8 | ForEach-Object { '  n={0} sum={1} max={2} {3}' -f $_.N, $_.Sum, $_.Max, $_.U.Substring(0, [Math]::Min(70, $_.U.Length)) }
  "-- status --"
  $rows | Group-Object S | ForEach-Object { '  {0}={1}' -f $_.Name, $_.Count }
}
