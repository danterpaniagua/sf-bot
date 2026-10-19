# GITIN-2250 — cuanto cuestan en cada servidor las dos consultas WMI que Zabbix hace cada minuto. SOLO LECTURA (3 ejecuciones de cada consulta, igual de pesadas que las de Zabbix).
if ($env:COMPUTERNAME -notlike 'SFCG-WEBS-*') { "HOST INESPERADO: $env:COMPUTERNAME"; return }
"host: $env:COMPUTERNAME  $(Get-Date -Format 'MM-dd HH:mm:ss zzz')  nucleos: $([Environment]::ProcessorCount)  adaptadores (Get-NetAdapter): $((Get-NetAdapter -IncludeHidden -ErrorAction SilentlyContinue | Measure-Object).Count)"
$cpu = { (Get-Process WmiPrvSE -ErrorAction SilentlyContinue | Measure-Object CPU -Sum).Sum }
$queries = [ordered]@{
  'cores'    = 'Select NumberOfLogicalProcessors from Win32_ComputerSystem'
  'adapters' = 'select Name,Description,NetConnectionID,Speed,AdapterTypeId,NetConnectionStatus,GUID from win32_networkadapter where PhysicalAdapter=True and NetConnectionStatus>0'
}
foreach ($k in $queries.Keys) {
  1..3 | ForEach-Object {
    $b = & $cpu; $sw = [Diagnostics.Stopwatch]::StartNew()
    try { $n = @(Get-CimInstance -Namespace root/cimv2 -Query $queries[$k] -ErrorAction Stop).Count } catch { $n = "ERR" }
    $ms = $sw.ElapsedMilliseconds; $a = & $cpu
    "{0} #{1}: {2} ms, filas={3}, WmiPrvSE CPU +{4:N2} s" -f $k, $_, $ms, $n, ($a - $b)
  }
}
