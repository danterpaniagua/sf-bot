# Event: 20261026_gitin2316-sml-spikes-webservice (GITIN-2316)
# C4 - PRUEBA de la regla Dynamic IP Restrictions (modo solo registro) de SFCG-WEBS-01. Ver el bloque de aplicacion en data/dynip-apply-webs01-20261026.txt.
#      Parte 1 (en OTRO equipo de la red 192.168.50.0/24, no en WEBS-01): envia 400 GET casi simultaneos a una ruta inexistente de WEBS-01 (192.168.50.101:8080, IP por el nombre de la NIC
#      segun loyalty/docs/infrastructure.md; se confirma en la parte 2). En modo solo registro todas deben responder 404 (no se bloquea nada).
#      Parte 2 (en SFCG-WEBS-01, solo lectura): busca en el log del dia las lineas de la IP de prueba y busca donde IIS registro la deteccion.
#      La ruta /gitin2316-test-404 no existe a proposito; no modifica datos.

# --- Parte 1: en el equipo de prueba ---
Add-Type -AssemblyName System.Net.Http
[System.Net.ServicePointManager]::DefaultConnectionLimit = 400
$h = New-Object System.Net.Http.HttpClient; $h.Timeout = [TimeSpan]::FromSeconds(20)
"EQUIPO DE PRUEBA: $env:COMPUTERNAME  inicio $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') (hora local)"
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$t = 1..400 | ForEach-Object { $h.GetAsync('http://192.168.50.101:8080/gitin2316-test-404') }
[System.Threading.Tasks.Task]::WaitAll([System.Threading.Tasks.Task[]]$t)
$sw.Stop()
"400 pedidos en $([math]::Round($sw.Elapsed.TotalSeconds,2)) s = $([math]::Round(400 / $sw.Elapsed.TotalSeconds,0)) req/s"
$t | ForEach-Object { [int]$_.Result.StatusCode } | Group-Object | ForEach-Object { "estado $($_.Name): $($_.Count)" }
"fin $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') (hora local)"

# --- Parte 2: en SFCG-WEBS-01 (solo lectura). Reemplazar IP_DEL_EQUIPO_DE_PRUEBA por la IP del equipo de la parte 1 ---
# "HOST: $env:COMPUTERNAME"; $ip='IP_DEL_EQUIPO_DE_PRUEBA'; $f='D:\SmartFran\inetpub\W3SVC2\u_ex261027.log'; $h=((Get-Content $f -TotalCount 10 | Where-Object { $_ -like '#Fields:*' } | Select-Object -First 1).Substring(9)).Split(' '); $r=@(Get-Content $f | Where-Object { $_ -and $_[0] -ne '#' -and $_.Contains(" $ip ") } | ConvertFrom-Csv -Delimiter ' ' -Header $h); "Lineas de la IP de prueba: $($r.Count)"; $r | Group-Object 'sc-status','sc-substatus' | ForEach-Object { "$($_.Name)`t$($_.Count)" }; "`n== registros de eventos de IIS con datos"; Get-WinEvent -ListLog * -ErrorAction SilentlyContinue | Where-Object { $_.LogName -like '*IIS*' -and $_.RecordCount -gt 0 } | ForEach-Object { "$($_.LogName)`t$($_.RecordCount)" }
