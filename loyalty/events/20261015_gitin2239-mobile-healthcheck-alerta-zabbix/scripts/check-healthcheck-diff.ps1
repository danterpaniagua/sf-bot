# Event: 20261015_gitin2239-mobile-healthcheck-alerta-zabbix (GITIN-2239). SOLO LECTURA. Se ejecuta en el servidor via "az vm run-command invoke" (cuenta SYSTEM).
# Compara sin imprimir el contenido: para C:\SmartFran\SmartLoyalty.WebService\healthcheck.ashx muestra tamano, ultima escritura UTC, MD5, si empieza con BOM UTF-8, cantidad de CRLF y de LF solos,
# MD5 del contenido normalizado (sin BOM, con saltos de linea LF, sin espacios al final de cada linea) y, por linea, el largo y los primeros 8 caracteres del MD5 de la linea (para comparar linea a linea entre servidores).
# Tambien lista, solo con nombre/tamano/fecha, los archivos healthcheck*.ashx de esa carpeta.
"HOST: $env:COMPUTERNAME"
$dir = 'C:\SmartFran\SmartLoyalty.WebService'
"--- archivos healthcheck*.ashx en $dir"
Get-ChildItem -LiteralPath $dir -Filter 'healthcheck*.ashx' -File -ErrorAction SilentlyContinue | ForEach-Object { "{0}`t{1}`t{2}" -f $_.Name, $_.Length, $_.LastWriteTimeUtc.ToString('yyyy-MM-ddTHH:mm:ssZ') }
$f = Join-Path $dir 'healthcheck.ashx'
if (-not (Test-Path -LiteralPath $f)) { "NO EXISTE $f"; return }
$b = [System.IO.File]::ReadAllBytes($f)
$md5 = [System.Security.Cryptography.MD5]::Create()
function Hex([byte[]]$x) { ($x | ForEach-Object { $_.ToString('X2') }) -join '' }
$bom = ($b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF)
$crlf = 0; $lf = 0
for ($i = 0; $i -lt $b.Length; $i++) { if ($b[$i] -eq 10) { if ($i -gt 0 -and $b[$i-1] -eq 13) { $crlf++ } else { $lf++ } } }
"--- resumen"
"BYTES={0} MD5={1} BOM={2} CRLF={3} LF_solo={4}" -f $b.Length, (Hex $md5.ComputeHash($b)), $bom, $crlf, $lf
$text = [System.Text.Encoding]::UTF8.GetString($b).TrimStart([char]0xFEFF)
$lines = $text -replace "`r`n", "`n" -split "`n"
$norm = (($lines | ForEach-Object { $_.TrimEnd() }) -join "`n").TrimEnd("`n")
"MD5_normalizado={0}" -f (Hex $md5.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($norm)))
"--- por linea (n | largo | md5 de la linea, 8 caracteres)"
for ($n = 0; $n -lt $lines.Count; $n++) { "{0}`t{1}`t{2}" -f ($n + 1), $lines[$n].Length, (Hex $md5.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($lines[$n]))).Substring(0, 8) }
