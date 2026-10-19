# Event: 20261014_gitin2223_taskoperator-preprod-appsettings-xml
# C3 - Solo lectura, en el servidor PREPROD de TaskOperator (SFDEV02). No modifica nada.
#      Objetivo: saber que cadena de conexion usa el proceso ETL que fallo con "error 26" y si el servidor/instancia existe.
#      a) AppSettings.config lineas 98-110 (claves SmlConnString/DwConnString y el comentario que las rodea) con contrasenas enmascaradas;
#      b) nombres de las cadenas de ConnectionStrings.config (solo el atributo name, no la cadena);
#      c) lineas de Unity.config que mencionan Etl (maximo 40), enmascaradas;
#      d) servicios SQL Server y SQL Browser de este host;
#      e) bases de datos de la instancia local por sqlcmd con autenticacion de Windows (solo nombres), si sqlcmd existe.
#      Toda linea impresa pasa por el enmascarado de Password=/Pwd= (con comillas simples, dobles o sin comillas).
$dir = 'E:\SmartFran\PREPROD\SmartLoyalty.TaskOperatorService'
$out = 'C:\Temp\c3-taskoperator-etl.txt'
New-Item -ItemType Directory -Force -Path 'C:\Temp' | Out-Null
function Mask($t) { $t -replace '(?i)(password|pwd)\s*=\s*(''[^'']*''|"[^"]*"|[^;"'']+)', '$1=***' }
& {
  "host: $env:COMPUTERNAME | $(Get-Date -Format s)"
  "== a) AppSettings.config lineas 98-110"
  $l = Get-Content "$dir\Config\AppSettings.config"
  98..110 | ForEach-Object { "{0}: {1}" -f $_, (Mask ($l[$_ - 1] -replace '^(.{260}).*', '$1')) }
  "== b) nombres de cadenas en ConnectionStrings.config"
  Select-String -Path "$dir\Config\ConnectionStrings.config" -Pattern 'name\s*=' | ForEach-Object { "{0}: {1}" -f $_.LineNumber, ([regex]::Match($_.Line, 'name\s*=\s*"[^"]*"').Value) }
  "== c) Unity.config lineas con Etl (max 40)"
  Select-String -Path "$dir\Config\Unity.config" -Pattern 'Etl' | Select-Object -First 40 | ForEach-Object { "{0}: {1}" -f $_.LineNumber, (Mask ($_.Line.Trim() -replace '^(.{250}).*', '$1')) }
  "== d) servicios SQL"
  Get-Service -Name 'MSSQL*', 'SQLBrowser', 'SQLAgent*' -ErrorAction SilentlyContinue | Select-Object Name, Status, StartType | Format-Table -AutoSize | Out-String
  "== e) bases de datos de la instancia local"
  if (Get-Command sqlcmd -ErrorAction SilentlyContinue) { sqlcmd -E -S localhost -W -h -1 -Q "SET NOCOUNT ON; SELECT @@SERVERNAME, CAST(SERVERPROPERTY('InstanceName') AS varchar(100)); SELECT name FROM sys.databases ORDER BY name" 2>&1 } else { "sqlcmd no esta instalado en este host" }
  "listo"
} *> $out
Get-Content $out
