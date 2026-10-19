# GITIN-2250 — compara la respuesta de healthcheck.ashx en un servidor WEBS (se ejecuta con "az vm run-command invoke"; salida corta). SOLO LECTURA.
if ($env:COMPUTERNAME -notlike 'SFCG-WEBS-*') { "HOST INESPERADO: $env:COMPUTERNAME"; return }
$ip = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -like '192.168.50.*' } | Select-Object -First 1).IPAddress
"host: $env:COMPUTERNAME  ip: $ip  $(Get-Date -Format 'MM-dd HH:mm:ss zzz')  CPU %: $((Get-CimInstance Win32_PerfFormattedData_PerfOS_Processor -Filter "Name='_Total'").PercentProcessorTime)  nucleos: $((Get-CimInstance Win32_ComputerSystem).NumberOfLogicalProcessors)"
foreach ($u in "http://localhost:8080/healthcheck.ashx", "http://127.0.0.1:8080/healthcheck.ashx", "http://${ip}:8080/healthcheck.ashx", "http://${ip}:8080/healthcheck.ashx?x=1") {
  $sw = [Diagnostics.Stopwatch]::StartNew(); $out = ''
  try { $r = Invoke-WebRequest -Uri $u -UseBasicParsing -TimeoutSec 40; $out = "HTTP $($r.StatusCode) $($r.Content.Length)B" }
  catch { $resp = $_.Exception.Response; if ($resp) { $out = "HTTP $([int]$resp.StatusCode)" } else { $out = "ERROR $($_.Exception.Message)" } }
  "{0} -> {1} en {2} ms" -f $u, $out, $sw.ElapsedMilliseconds
}
$appcmd = "$env:windir\system32\inetsrv\appcmd.exe"
if (Test-Path $appcmd) { "-- bindings --"; & $appcmd list site | ForEach-Object { $_ -replace '\s+',' ' } }
"-- archivo healthcheck.ashx --"
Get-ChildItem C:\SmartFran -Recurse -Depth 3 -Filter healthcheck.ashx -ErrorAction SilentlyContinue | Select-Object -First 2 | ForEach-Object {
  "$($_.FullName)  $($_.Length) B  $($_.LastWriteTime.ToString('yyyy-MM-dd HH:mm'))"
  (Get-Content $_.FullName -TotalCount 40) -replace '(?i)(password|pwd|secret|token|apikey|key)\s*=\s*[^;"''\s]+','$1=***' | ForEach-Object { $_.Substring(0, [Math]::Min(160, $_.Length)) }
}
