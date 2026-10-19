# GITIN-2250 — que proveedor WMI carga WmiPrvSE y que actividad WMI se registra (se ejecuta con "az vm run-command invoke"; salida corta). SOLO LECTURA.
if ($env:COMPUTERNAME -notlike 'SFCG-WEBS-*') { "HOST INESPERADO: $env:COMPUTERNAME"; return }
"host: $env:COMPUTERNAME  $(Get-Date -Format 'MM-dd HH:mm:ss zzz')"
"-- WmiPrvSE: proceso, CPU acumulada, inicio, modulos de proveedor --"
Get-Process WmiPrvSE -ErrorAction SilentlyContinue | ForEach-Object {
  $m = ($_.Modules | ForEach-Object { $_.ModuleName } | Where-Object { $_ -match 'prov|perf|cimwin|hiperf|wmi' } | Select-Object -Unique) -join ','
  $st = ''; try { $st = $_.StartTime.ToString('MM-dd HH:mm:ss') } catch {}
  "pid=$($_.Id) cpu_s=$([int]$_.CPU) inicio=$st mods=$($m.Substring(0, [Math]::Min(150, $m.Length)))"
}
"-- WMI-Activity/Operational: ultimos 12 eventos --"
try {
  Get-WinEvent -LogName 'Microsoft-Windows-WMI-Activity/Operational' -MaxEvents 12 -ErrorAction Stop | ForEach-Object {
    $t = ($_.Message -replace '\s+',' '); "{0} id={1} {2}" -f $_.TimeCreated.ToString('HH:mm:ss'), $_.Id, $t.Substring(0, [Math]::Min(170, $t.Length))
  }
} catch { "sin eventos o error: $($_.Exception.Message)" }
