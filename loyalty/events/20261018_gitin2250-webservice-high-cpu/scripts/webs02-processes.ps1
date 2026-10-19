# GITIN-2250 — lista de todos los procesos de SFCG-WEBS-02. SOLO LECTURA. Ejecutar en PowerShell DENTRO de SFCG-WEBS-02; pegar el resultado en el chat.
# No se muestran las lineas de comando completas (pueden contener cadenas de conexion o credenciales): solo el nombre del app pool de cada w3wp.
if ($env:COMPUTERNAME -ne 'SFCG-WEBS-02') { throw "Host equivocado: $env:COMPUTERNAME (se esperaba SFCG-WEBS-02)" }
"== host =="; $env:COMPUTERNAME; Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz'
"LogicalProcessors: $((Get-CimInstance Win32_ComputerSystem).NumberOfLogicalProcessors)"
"CPU total %: $((Get-CimInstance Win32_PerfFormattedData_PerfOS_Processor -Filter "Name='_Total'").PercentProcessorTime)"
$perf = @{}
Get-CimInstance Win32_PerfFormattedData_PerfProc_Process | ForEach-Object { if ($_.IDProcess -ne 0) { $perf[[int]$_.IDProcess] = [int]$_.PercentProcessorTime } }
$cim = @{}
Get-CimInstance Win32_Process | ForEach-Object { $cim[[int]$_.ProcessId] = $_ }
"== todos los procesos (CPU_pct: 100 = un nucleo completo; ordenados por CPU_pct) =="
$rows = Get-Process | ForEach-Object {
  $c = $cim[$_.Id]
  $pool = ''
  if ($_.ProcessName -eq 'w3wp' -and $c -and $c.CommandLine -match '-ap\s+"([^"]+)"') { $pool = $matches[1] }
  $owner = ''
  try { if ($c) { $o = Invoke-CimMethod -InputObject $c -MethodName GetOwner -ErrorAction Stop; $owner = "$($o.Domain)\$($o.User)" } } catch {}
  $start = ''
  try { $start = $_.StartTime.ToString('MM-dd HH:mm') } catch {}
  [pscustomobject]@{
    PID = $_.Id; Name = $_.ProcessName; CPU_pct = $perf[$_.Id]; CPU_s = [int]$_.CPU; WS_MB = [int]($_.WorkingSet64 / 1MB)
    Threads = $_.Threads.Count; Handles = $_.HandleCount; Start = $start; Owner = $owner; AppPool = $pool
  }
}
$rows | Sort-Object CPU_pct -Descending | Format-Table -AutoSize | Out-String -Width 250
"Total procesos: $($rows.Count)"
