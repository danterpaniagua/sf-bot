# Event: 20261014_gitin2223_taskoperator-preprod-appsettings-xml
# C6 - Solo lectura, en SFDEV02. Lista los nombres de las bases de datos de la instancia local con el login SQL del entorno (sltest01),
#      porque la cuenta de Windows con la que se corrio C3 no tiene acceso a la instancia ("Login failed for user SMARTIT\dantep").
#      sqlcmd pide la contrasena por consola (-U sin -P); no se escribe en ningun archivo. Salida: C:\Temp\c6-databases.txt (solo nombres).
New-Item -ItemType Directory -Force -Path 'C:\Temp' | Out-Null
"host: $env:COMPUTERNAME | $(Get-Date -Format s)" | Out-File 'C:\Temp\c6-databases.txt'
sqlcmd -S SFDEV02 -U sltest01 -W -h -1 -Q "SET NOCOUNT ON; SELECT @@SERVERNAME, CAST(SERVERPROPERTY('InstanceName') AS varchar(100)); SELECT name FROM sys.databases ORDER BY name" 2>&1 | Out-File -Append 'C:\Temp\c6-databases.txt'
Get-Content 'C:\Temp\c6-databases.txt'
