# GITIN-2250 — triage de CPU en SFCG-WEBS-02 antes del reinicio. SOLO LECTURA: no escribe archivos ni cambia nada en el servidor.
# Ejecutar en una sesion de PowerShell DENTRO de SFCG-WEBS-02; el resultado se pega en el chat (se guarda en data/).
if ($env:COMPUTERNAME -ne 'SFCG-WEBS-02') { throw "Host equivocado: $env:COMPUTERNAME (se esperaba SFCG-WEBS-02)" }
"== host ==";  $env:COMPUTERNAME; Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz'
$os = Get-CimInstance Win32_OperatingSystem
"== arranque / nucleos =="; "LastBootUpTime: $($os.LastBootUpTime)"; "LogicalProcessors: $((Get-CimInstance Win32_ComputerSystem).NumberOfLogicalProcessors)"

"== CPU total y top 12 procesos (PercentProcessorTime es por nucleo: 100 = un nucleo completo) =="
(Get-CimInstance Win32_PerfFormattedData_PerfOS_Processor -Filter "Name='_Total'").PercentProcessorTime
Get-CimInstance Win32_PerfFormattedData_PerfProc_Process | Where-Object { $_.Name -notin '_Total','Idle' } |
  Sort-Object PercentProcessorTime -Descending | Select-Object -First 12 Name, IDProcess, PercentProcessorTime, @{n='WS_MB';e={[int]($_.WorkingSet/1MB)}}, ThreadCount |
  Format-Table -AutoSize | Out-String -Width 200

$appcmd = "$env:windir\system32\inetsrv\appcmd.exe"
if (Test-Path $appcmd) {
  "== w3wp -> app pool =="; & $appcmd list wp
  "== peticiones en curso (total) =="; @(& $appcmd list requests).Count
  "== peticiones con mas de 3 s en curso =="; & $appcmd list requests /elapsed:3000
}

"== conexiones TCP por estado =="
Get-NetTCPConnection | Group-Object State | Sort-Object Count -Descending | Select-Object Count, Name | Format-Table -AutoSize | Out-String -Width 200

"== eventos System/WAS y Application (nivel error o critico) de las ultimas 6 h =="
try {
  Get-WinEvent -FilterHashtable @{ LogName = 'System','Application'; Level = 1,2; StartTime = (Get-Date).AddHours(-6) } -MaxEvents 25 -ErrorAction Stop |
    Select-Object TimeCreated, ProviderName, Id, @{n='Msg';e={ ($_.Message -replace '\s+',' ').Substring(0, [Math]::Min(200, $_.Message.Length)) }} |
    Format-Table -AutoSize -Wrap | Out-String -Width 250
} catch { "sin eventos o error: $($_.Exception.Message)" }
