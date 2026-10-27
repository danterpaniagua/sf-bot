# Event: 20261026_gitin2316-sml-spikes-webservice (GITIN-2316)
# C3 - SOLO LECTURA. Se ejecuta en el servidor SFCG-WEBS-01 (PowerShell). Lee el/los log(s) de IIS de la ventana del pico GET y cuenta
#      requests GET por IP de cliente, por ruta (cs-uri-stem, SIN query string) y por codigo de estado. No modifica nada.
#      Ventana: 21:20 a 21:29 hora local UTC-3 del 2026-10-26 = 00:20:00 a 00:29:00 UTC del 2026-10-27 (los logs de IIS estan en UTC por defecto;
#      el 2026-10-27 UTC es el archivo u_ex261027.log).
#      Ruta por defecto de los logs: C:\inetpub\logs\LogFiles\W3SVC<id>\ ; si la ruta del sitio es otra, ajustar $LogRoot.
#      Las IP de clientes y las rutas quedan en la salida: no pegarla fuera del evento.

$ErrorActionPreference = 'Stop'
"HOST: $env:COMPUTERNAME   (debe decir SFCG-WEBS-01; si no, detenerse)"
if ($env:COMPUTERNAME -ne 'SFCG-WEBS-01') { throw "Host equivocado: $env:COMPUTERNAME" }

$LogRoot = 'D:\SmartFran\inetpub'   # carpeta de logs del sitio segun loyalty/docs/infrastructure.md (leida el 2026-10-18 en los WEBS); si no existe, se ve con Get-Website
$FileName = 'u_ex261027.log'
$From = [datetime]'00:20:00'
$To   = [datetime]'00:29:00'

$files = Get-ChildItem -Path $LogRoot -Recurse -Filter $FileName -ErrorAction SilentlyContinue
if (-not $files) { throw "No se encontro $FileName bajo $LogRoot" }
"Archivos: " + (($files | ForEach-Object { "$($_.FullName) ($($_.Length) bytes, modificado $($_.LastWriteTime))" }) -join '; ')

$rows = foreach ($f in $files) {
    $fields = $null
    # El log del dia lo tiene abierto IIS para escribir: ReadLines falla ("being used by another process"); se abre con FileShare.ReadWrite.
    $fs = [System.IO.File]::Open($f.FullName, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
    $sr = New-Object System.IO.StreamReader($fs)
    while ($null -ne ($line = $sr.ReadLine())) {
        if ($line.StartsWith('#Fields:')) { $fields = $line.Substring(9).Split(' '); continue }
        if ($line.StartsWith('#') -or -not $fields) { continue }
        $p = $line.Split(' ')
        if ($p.Count -ne $fields.Count) { continue }
        $t = [datetime]$p[[array]::IndexOf($fields, 'time')]
        if ($t -lt $From -or $t -ge $To) { continue }
        [pscustomobject]@{
            Site   = $f.Directory.Name
            Minute = $t.ToString('HH:mm')
            Method = $p[[array]::IndexOf($fields, 'cs-method')]
            Stem   = $p[[array]::IndexOf($fields, 'cs-uri-stem')]
            Client = $p[[array]::IndexOf($fields, 'c-ip')]
            Status = $p[[array]::IndexOf($fields, 'sc-status')]
            TimeMs = [int]$p[[array]::IndexOf($fields, 'time-taken')]
        }
    }
    $sr.Close(); $fs.Close()
}
"Filas en la ventana (todas las metodos): $(@($rows).Count)"
$get = @($rows | Where-Object Method -eq 'GET')
"Filas GET: $($get.Count)"
"`n== GET por minuto UTC (minuto | requests)";        $get | Group-Object Minute | Sort-Object Name | ForEach-Object { "$($_.Name)`t$($_.Count)" }
"`n== GET por IP de cliente (top 15)";                 $get | Group-Object Client | Sort-Object Count -Descending | Select-Object -First 15 | ForEach-Object { "$($_.Name)`t$($_.Count)" }
"`n== GET por ruta sin query (top 15)";                $get | Group-Object Stem | Sort-Object Count -Descending | Select-Object -First 15 | ForEach-Object { "$($_.Name)`t$($_.Count)" }
"`n== GET por codigo de estado";                       $get | Group-Object Status | Sort-Object Count -Descending | ForEach-Object { "$($_.Name)`t$($_.Count)" }
"`n== GET por sitio (carpeta W3SVC)";                  $get | Group-Object Site | Sort-Object Count -Descending | ForEach-Object { "$($_.Name)`t$($_.Count)" }
"`n== tiempo de respuesta GET (ms): promedio y maximo"; if ($get.Count) { $m = $get | Measure-Object TimeMs -Average -Maximum; "$([math]::Round($m.Average,1))`t$($m.Maximum)" }
"`n== top 10 combinaciones IP + ruta";                 $get | Group-Object Client, Stem | Sort-Object Count -Descending | Select-Object -First 10 | ForEach-Object { "$($_.Name)`t$($_.Count)" }
