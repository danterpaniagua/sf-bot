# Eventos — 20260810_sales-serilog-console-logs

## 2026-08-10 — Apertura de investigación

He abierto GITIN-1811 tras el reporte de que Sales no envía mensajes JSON de Serilog a stdout, a diferencia de Business. He definido el enfoque: cruzar código del repo, configuración de Azure y datos de Graylog. He empezado por el repo — he leído `Program.cs` de Sales y Business y he confirmado que ambos llaman al mismo `SerilogBootstrap.Configure()` compartido, con el mismo sink único (`WriteTo.Console` con `ExpressionTemplate` CLEF) — he descartado diferencias de código de aplicación entre los dos servicios.

## 2026-08-10 — Hipótesis de trabajo: stdoutLogEnabled en Windows

He encontrado que Sales es Windows (IIS/ANCM) y Business es Linux — confirmado por la tabla de apps de `cloud-graylog/CLAUDE.md` y por la referencia a `Microsoft.AspNetCore.AzureAppServices.HostingStartup` (paquete Windows-only) en el `.csproj` de Sales, ausente en el de Business. No he encontrado ningún `web.config` versionado en el proyecto de Sales. He formulado la hipótesis: en Windows, IIS/ANCM no captura stdout por defecto (`stdoutLogEnabled="false"` es el default del SDK de .NET) a menos que se habilite explícitamente — a diferencia de Linux, donde el runtime de contenedor captura stdout nativamente sin configuración adicional. He documentado la hipótesis en `investigation.md` y he entregado comandos de solo lectura (Azure CLI + lectura de `web.config` vía Kudu con token AAD, evitando exponer credenciales de publicación) para confirmarla o descartarla.

## 2026-08-10 — Hipótesis confirmada

He recibido el resultado de los cuatro comandos. La lectura del `web.config` real de Sales vía Kudu confirmó `stdoutLogEnabled="false"` — causa raíz confirmada, ya no es solo una hipótesis. He encontrado además que `applicationLogs.fileSystem.level` de Sales también está en `"Off"` (segundo gate cerrado), y que Business tiene todos esos toggles en `Off`/`false` también pero sus logs de consola sí llegan a Graylog — confirma que Linux no depende de ninguno de estos ajustes Windows-específicos. No he encontrado ningún override de `ANCM_stdoutLogEnabled` en los App Settings. He actualizado `investigation.md` con la confirmación y he escrito `ops.md` con Causa raíz, Hallazgos (H1–H7) y Acciones propuestas — incluyendo una nota de seguimiento sobre `Pos` (también Windows, mismo gap probable, fuera de alcance de este ticket).

## 2026-08-10 — He entregado el comando de edición vía Kudu y he aclarado el ciclo de vida de web.config

He dado el comando `curl` con banner de comando destructivo para escribir el `web.config` corregido vía Kudu VFS (stopgap inmediato) y he explicado que es temporal — se regenera desde los defaults del SDK en el próximo publish, salvo que se agregue un `web.config` versionado al proyecto (fix durable, acción de desarrollo). He explicado también cuándo se genera realmente el archivo (en el publish, no en el build ni en runtime).

## 2026-08-10 — "Funciona en mi máquina" explicado

He recibido que el desarrollador probó localmente en Windows vía Visual Studio y le funciona — he confirmado que esto es consistente con la causa raíz, no una contradicción: Visual Studio se adjunta directo al proceso y captura `Console.Out` sin pasar por la redirección de stdout de IIS/ANCM, que solo aplica al App Service real desplegado. He agregado esta aclaración a `ops.md` (Causa raíz) para anticipar la objeción natural del equipo de desarrollo, y he documentado el hallazgo como conocimiento reutilizable en `cloud/docs/infrastructure.md` (nueva sección "Logging (GSFC-LOG-1)") y en el skill `cloud-azure.md` (nueva sección de diagnóstico), para que la próxima investigación de este tipo (por ejemplo, si `Pos` tiene el mismo problema) no tenga que repartir todo el análisis desde cero.

## 2026-08-11 — Segundo blocker: la carpeta logs no se crea sola

He confirmado que ANCM no crea automáticamente el directorio de destino de `stdoutLogFile` — si no existe, falla en silencio, sin log ni error. He encontrado que el `.csproj` de Sales ya excluye `logs\**` de compilación y de publish (`Content Remove`), evidencia adicional de que la carpeta no llega al deploy actual. He propuesto dos soluciones: creación manual vía Kudu VFS (stopgap, con banner de comando destructivo) o un target MSBuild (`MakeDir` con `AfterTargets="Publish"`) en el `.csproj` para el fix durable, sin necesitar un archivo placeholder versionado.

## 2026-08-11 — Workflow de CI/CD de Sales-DEV revisado

He recibido el archivo del workflow de GitHub Actions que compila/despliega `Sales-DEV` (`Compile/Deploy Sales API (WIN) to DEV environment`). He confirmado que ningún paso genera ni transforma `web.config` — corre `dotnet publish --no-build` directo a `azure/webapps-deploy@v2`, coherente con la causa raíz ya confirmada. He verificado que `--no-build` no afecta el fix propuesto (el target `Publish` y sus hooks corren igual, `--no-build` solo omite `Build`). He identificado una implicancia cruzada con GITIN-1794: `Sales-DEV` se construye del mismo proyecto sin ningún override — muy probablemente tiene el mismo gap, y `Pos-DEV` también por ser Windows. No he reabierto GITIN-1794 (ya cerrado, fuera de su alcance) — he documentado la nota en `cloud/docs/infrastructure.md` y he agregado el paso 5 a Acciones propuestas de este ticket.

## 2026-08-11 — He corregido la ruta de stdoutLogFile: fuera de wwwroot

He recomendado mover `stdoutLogFile` de `.\logs\stdout` (dentro de wwwroot) a `\\?\%home%\LogFiles\stdout` — la convención documentada de Azure para App Service Windows, directorio administrado por la plataforma en vez de un path arbitrario. He señalado que el target `MakeDir` propuesto antes solo aplica al path relativo a wwwroot, ya que `%home%` es una variable de entorno que solo existe en runtime en el App Service, no durante el build en el runner de GitHub Actions — para el nuevo path, la creación de carpeta (si hiciera falta) tendría que ir en `Program.cs`, no en el `.csproj`.

## 2026-08-11 — Confirmado: C:\home\LogFiles ya existe

He recibido la confirmación de que `C:\home\LogFiles\` ya existe en el App Service (verificado vía consola Kudu). Esto elimina la necesidad de cualquier código o target de creación de carpeta, tanto el `MakeDir` del `.csproj` como el `Directory.CreateDirectory` de `Program.cs` propuestos antes. He actualizado Acciones propuestas en `ops.md` con la versión final del fix: solo el `web.config` con el path corregido, más habilitar H4 (`applicationLogs.fileSystem`, hoy `Off`) por separado.

## 2026-08-11 — Fix entregado al equipo de desarrollo

He entregado el `web.config` completo (versión final, con `stdoutLogEnabled="true"` y `stdoutLogFile` apuntando a `%home%\LogFiles`) para agregar al proyecto `SmartFran.Cloud.Sales.API`, destinado al equipo de desarrollo para incorporarlo al repo real. He actualizado el estado del ticket a "entregado, pendiente implementación" en `ops.md` — GITIN-1811 queda a la espera de que el equipo de desarrollo aplique el cambio y de la validación posterior en Graylog (paso 3 de Acciones propuestas).

## 2026-08-11 — Corrección: siempre fue Sales-DEV, no Sales-PRO

He asumido sin confirmar, desde la apertura de este ticket, que el App Service investigado era `SmartFran-Cloud-Sales-PRO` (RG `SmartFran.Cloud.PRO`, subscripción `SmartIT Cloud`). He preguntado directamente y he recibido la confirmación de que todos los comandos (C1–C4) se corrieron en realidad contra `SmartFran-Cloud-Sales-DEV` (RG `SmartFran.Cloud`, subscripción `Smart IT - Grido`) desde el principio — la misma app onboardada a Graylog en GITIN-1794. He corregido `investigation.md` (nota de corrección, sin reescribir el análisis histórico), `ops.md` (Tabla resumen, Causa raíz, Hallazgos H3/H4/H7/H8, Recursos afectados, Comandos ejecutados, Acciones propuestas), `scripts.sh` (subscripción/RG/hostname Kudu), `cloud/docs/infrastructure.md` y el skill `cloud-azure.md` (ambos decían "confirmado para Sales-PRO", invertido). He reformulado la relación con GITIN-1794: ya no es una sospecha sobre `Sales-DEV`, es la confirmación directa de que esa app específica tiene el problema; `Sales-PRO`/`Pos-PRO` quedan como estado separado y sin verificar en ninguna dirección.

## 2026-08-11 — web.config corregido, aplicado en vivo vía FTP

He recibido la confirmación de que el `web.config` corregido se aplicó directamente vía FTP contra Sales-DEV. He pedido re-leer el archivo vía Kudu VFS para confirmar el cambio, y he recibido el contenido: `stdoutLogEnabled="true"`, `stdoutLogFile="\\?\%home%\LogFiles\stdout"` — exactamente el fix esperado. He documentado como H9. He actualizado el estado del ticket y he marcado la primera parte de Acciones propuestas #1 como aplicada, dejando pendiente que el mismo cambio se sume al repo real (esta aplicación fue manual, no sobrevive a un futuro deploy de CI/CD sin eso). He recordado que sigue pendiente H4/H8 (`applicationLogs.fileSystem` en `Off`) antes de que esto efectivamente llegue a Graylog.

## 2026-08-11 — H4 y H8 resueltos en la misma llamada

He recibido el resultado de `az webapp log config --application-logging filesystem --level information` (C5) sobre Sales-DEV: `applicationLogs.fileSystem.level` pasó a `"Information"` (resuelve H4) y `applicationLogs.azureBlobStorage.level` quedó en `"Off"` (resuelve H8) — la misma llamada limpió ambos, sin config residual ni paso adicional. He actualizado H4, H8, la tabla de comandos (C5) y Acciones propuestas en `ops.md` — los tres gates de plataforma (`web.config`, `fileSystem`, `azureBlobStorage`) quedan cerrados correctamente. Único paso pendiente: confirmar en Graylog que `AppServiceConsoleLogs`/`AppServiceAppLogs` de Sales-DEV ya muestran datos reales, y sumar el `web.config` al repo real para que el fix sobreviva al próximo deploy.

## 2026-08-11 — Búsqueda vacía persistente: he ido hop por hop

Ante dos búsquedas seguidas en cero (incluso pegándole al endpoint `/api/v1/Status`, que loguea explícitamente y no requiere auth — encontrado revisando `StatusController.cs`, distinto del `/Health` que no loguea nada), he dejado de asumir y he empezado a verificar cada salto de la cadena por separado. He listado `C:\home\LogFiles\` directo vía Kudu VFS: he encontrado `stdout_20260811123558_9664.log` creado a las 12:36 (coincide con el restart del proceso tras el cambio de `web.config`) pero en 0 bytes. He identificado esto como un problema de buffering conocido en la redirección de stdout de ANCM bajo `hostingModel="inprocess"`, distinto de todo lo confirmado hasta ahora. He sugerido un `az webapp restart` como primer intento, con banner de comando destructivo.

## 2026-08-11 — Confirmado: el restart resolvió el buffering, JSON real capturado

He recibido contenido real del archivo stdout post-restart: JSON CLEF válido de Serilog, incluyendo logs de `Microsoft.AspNetCore.Hosting.Diagnostics` a nivel Information. He documentado como H10 (resuelto) con un ejemplo real en `ops.md`. He retractado explícitamente una hipótesis anterior (H11) — había asumido que `MinimumLevel.Override("Microsoft", Warning)` iba a suprimir el logging propio de ASP.NET Core, y esta evidencia la contradice directamente; no afecta la causa raíz ya confirmada, pero he corregido la explicación específica. He dado el siguiente comando de verificación en Graylog para confirmar que este contenido ya llegó end-to-end.

## 2026-08-11 — Búsqueda amplia: 30 min sin contenido Console/CLEF en Graylog

He recibido dos veces el mismo resultado (la misma query con category:AppServiceConsoleLogs, sin cambios) — he señalado que parecía ser el comando anterior repetido, no el nuevo sin filtro de category, y he pedido específicamente ese. He recibido el resultado correcto: 33 mensajes en 30 minutos, todos `AppServiceHTTPLogs` salvo un `AppServiceAppLogs` aislado (`"Thread was being aborted."`) que he atribuido a la captura de Windows Event Log, no al pipeline GSFC-LOG-1. He documentado como H12: ningún contenido con forma de Console/CLEF llegó a Graylog en absoluto, pese a que el archivo stdout ya tiene contenido real confirmado (H10). No he asumido que sea solo latencia sin más base — he dejado la conclusión abierta explícitamente en vez de forzar un cierre. También he notado como H13 que `/api/v1/Status` devolvió 403 (nunca ejecutó el controller, pese a `[Authorize]` comentado) — tangencial, no afecta la conclusión principal ya que los logs genéricos de hosting de `/` y `/Health` alcanzan para probar que ANCM captura stdout.

## 2026-08-11 — Log Stream reveló una excepción real de AzureBlobTraceListener

He recibido un error real capturado desde el Log Stream de Sales: `AzureBlobTraceListener` deshabilitado por falta de SAS URL. He confirmado que esto refuerza H2 con evidencia concreta — el paquete `Microsoft.AspNetCore.AzureAppServices.HostingStartup` sigue activo e intenta wirear un listener de Blob Storage roto (`applicationLogs.azureBlobStorage.level: "Verbose"`, `sasUrl: null`), sin relación con el pipeline GSFC-LOG-1. He documentado como H8. He dado el comando de solo lectura para reconfirmar el estado actual y el comando de escritura (`az webapp log config --application-logging filesystem`) para resolver H4 y H8 en la misma llamada — con banner de comando destructivo, pendiente de que se corra y se confirme con un `az webapp log show` posterior que `azureBlobStorage` quedó desactivado, no solo `fileSystem` agregado en paralelo.

## 2026-08-11 — Corrección de tiempo verbal en todo el archivo

He recibido la observación de que este archivo completo usaba pretérito indefinido en vez del pretérito perfecto compuesto que exige la convención de voz de este proyecto — mismo problema encontrado y corregido en `cloud/events/20260810_dev-environment-onboarding/ops-events.md`. He reescrito el archivo completo con el tiempo verbal correcto.

## 2026-08-11 — Búsqueda amplia tras una hora: sigue vacío pese a tráfico de negocio real

He recibido el resultado de una búsqueda de una hora completa: 135 mensajes, incluyendo tráfico de negocio real (`Sale/Create`, `Sale/Close`, `WsFeAr/CaeRequest`) — todo `AppServiceHTTPLogs` salvo tres repeticiones más del mismo `"Thread was being aborted."` (`AppServiceAppLogs`). He descartado latencia como explicación dado el tiempo transcurrido y el tráfico real involucrado. He verificado directamente contra Azure en vez de seguir especulando: `az monitor diagnostic-settings categories list`/`list` sobre el recurso real confirmaron que `AppServiceConsoleLogs` existe como categoría, está `enabled: true`, y apunta al Event Hub correcto — la configuración está 100% verificada como correcta.

## 2026-08-11 — Causa raíz final: limitación de plataforma, no de configuración

He buscado en la web ante la posibilidad de un problema conocido y he confirmado, vía documentación de Microsoft, que `AppServiceConsoleLogs` no está soportada para aplicaciones .NET en Windows — solo JavaSE/Tomcat. Ningún ajuste de configuración puede resolver esto. He verificado además el mecanismo alternativo documentado (`AppServiceAppLogs` vía `AzureMonitorTraceListener` + `System.Diagnostics.Trace`), marcado explícitamente como no soportado para ASP.NET Core en la fuente encontrada. He documentado como H14 — cierra la investigación técnica de SRE. He reescrito Resumen, Estado, Causa raíz y Acciones propuestas en `ops.md` para reflejar que la resolución requiere una decisión de arquitectura del equipo de desarrollo (sink GELF directo, el camino Trace-based sin confirmar, u otra alternativa), no un ajuste adicional de SRE. He actualizado `investigation.md`, `cloud/docs/infrastructure.md` y el skill `cloud-azure.md` para reflejar la conclusión final en vez de la guía de "fix" incompleta que tenían antes.
