#!/bin/bash
# GITIN-1637 -- comandos de validacion local ejecutados contra la rama `ope` de
# cloud/repo/SmartFran.Cloud/. Local-only, nunca para pushear -- emulan
# .github/workflows/SmartFran.Cloud.Sales.PRO_win.yml (restore/build/test), no reemplazan
# el pipeline real (que publica desde un runner windows-latest via azure/webapps-deploy).
#
# Requiere: Dockerfile y .dockerignore en la raiz de cloud/repo/SmartFran.Cloud/ (agregados
# como parte de este ticket, ver investigation.md).

# 1. Build-check de Sales.API (restore + build + test contra el proyecto de la API en si).
cd /home/dpaniagua/Documentos/git/bots/cloud/repo/SmartFran.Cloud
docker build -t sales-api-build-check:ope .

# 2. Build-check de la suite de tests unitarios (Sales.Application.Tests, incluye
#    Source/Services/Sales/SmartFran.Cloud.Sales.Application.Tests/HealthCheck/).
docker build --build-arg WORKING_DIRECTORY="Source/Services/Sales/SmartFran.Cloud.Sales.Application.Tests" \
  -t sales-tests-build-check:ope .

# --- Resultados historicos (ver investigation.md y data/ para el detalle completo) ---
# Primer intento (antes del fix de WorstOf): dotnet build fallo, CS0103 'WorstOf' undefined.
# Segundo intento: dotnet build 0 Error(s), dotnet test 30/30 OK.
# Tercer intento (tras remover REDIS del body): dotnet test 19/19 OK (se borraron los tests de
#   DependencyStatusExtensions junto con la clase, ya sin caller).
# Estado actual (2026-09-23): REDIS volvio al body (a nivel raiz, no por tenant) y se agrego
#   GENERAL_STATUS -- StatusController.cs/Program.cs NO fueron re-alineados a esta ultima forma
#   todavia (por instruccion explicita: "leave code an docker test by now"). Los comandos de
#   arriba estan listos para re-ejecutar una vez que se retome el codigo.

# --- Intento de boot completo del contenedor (abandonado, ver investigation.md) ---
# Llego hasta MapControllers() antes de toparse con una dependencia real de infraestructura
# (IRelationServicesProvider, datos de permisos en Azure App Configuration que un ambiente
# dev efimero no tiene poblados) -- no es algo resoluble con mas variables de entorno.
# export AZURE_APP_CONFIG_CONNECTION="<no persistir el valor real -- ver CLAUDE.md>"
# export SIGNALR_CONNECTION="Endpoint=https://placeholder.service.signalr.net;AccessKey=aaaa...;Version=1.0;"
# docker run --rm -p 127.0.0.1:5000:8080 \
#   -e ASPNETCORE_URLS=http://+:8080 \
#   -e "SmartFran_Cloud_Providers_AzureApplicationSettingsService_Setting__Connection=$AZURE_APP_CONFIG_CONNECTION" \
#   -e "SignalRAzureUrl=$SIGNALR_CONNECTION" \
#   sales-api-build-check:ope \
#   dotnet Source/Services/Sales/SmartFran.Cloud.Sales.API/bin/Release/net10.0/SmartFran.Cloud.Sales.API.dll
