# GITIN-2250 — muestreo de 3 min (cada 5 s) en SFCG-WEBS-02. SOLO LECTURA, sin escribir archivos en el host. Salida < 4 KB.
# Una linea por muestra: CPU total, CPU por proceso w3wp (100 = un nucleo; 2 nucleos), solicitudes ejecutando / en cola.
if ($env:COMPUTERNAME -ne 'SFCG-WEBS-02') { throw "Host equivocado: $env:COMPUTERNAME" }
"host=$env:COMPUTERNAME inicio=$(Get-Date -Format 's')"
"== directorio de logs de IIS por sitio =="
try { Import-Module WebAdministration -ErrorAction Stop; Get-Website | ForEach-Object { '  {0}: {1}' -f $_.Name, $_.logFile.directory } } catch { "Get-Website fallo: $($_.Exception.Message)" }
"== muestras (hora CPU_total | pid:cpu ... | exec/cola) =="
$pidName = @{}
1..36 | ForEach-Object {
  $p = Get-CimInstance Win32_PerfFormattedData_PerfProc_Process -Filter "Name LIKE 'w3wp%'"
  $tot = (Get-CimInstance Win32_PerfFormattedData_PerfOS_Processor -Filter "Name='_Total'").PercentProcessorTime
  $ex = (Get-Counter '\ASP.NET Applications(__Total__)\Requests Executing','\ASP.NET\Requests Queued' -ErrorAction SilentlyContinue).CounterSamples.CookedValue
  '{0} {1,3} | {2} | {3}/{4}' -f (Get-Date -Format 'HH:mm:ss'), $tot, (($p | Sort-Object IDProcess | ForEach-Object { '{0}:{1}' -f $_.IDProcess, $_.PercentProcessorTime }) -join ' '), $ex[0], $ex[1]
  Start-Sleep -Seconds 3
}
