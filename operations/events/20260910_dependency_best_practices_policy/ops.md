# GITIN-2026 — Buenas prácticas para selección de librerías/dependencias (npm, NuGet, .NET)

**Tags:** `Operaciones`

## Resumen

Ninguno de los pipelines de CI/CD relevados (los workflows de despliegue de SmartFran Cloud en GitHub Actions ni los Jenkinsfiles de SmartPedidos) valida versión mínima, licencia, salud del proyecto o vulnerabilidades conocidas al incorporar una dependencia externa — ni existe un `dependabot.yml`/`renovate.json` en ningún repositorio. Como consecuencia, hay dependencias en uso hoy en producción que violan cada uno de los criterios que se proponen formalizar: versiones pre-1.0, un paquete marcado end-of-life por su propio mantenedor, y al menos tres paquetes cuya licencia exige una licencia comercial paga para uso en un producto cerrado como los nuestros. Se propone comunicar un conjunto de criterios de selección de librerías (versión mínima, salud/SCM, tamaño y dependencias transitivas, licencia, validación en CI/CD) y enviarlos por correo a Operaciones, con ejemplos reales tomados de SmartPedidos (npm), SmartLoyalty y SmartFran Cloud (NuGet).

## Tabla resumen

| Campo | Valor |
|---|---|
| Ticket Jira | [GITIN-2026](https://smartit-ar.atlassian.net/browse/GITIN-2026) |
| ID alerta | N/A — trabajo proactivo, sin alerta disparadora |
| Sistema | SmartPedidos (npm), SmartLoyalty (NuGet/.NET Framework), SmartFran Cloud (NuGet/.NET) |
| Severidad | Media — sin incidente activo; riesgo de cumplimiento de licencias y de mantenibilidad a futuro |
| Detectado | 2026-09-10 (relevamiento proactivo, sin incidente) |
| Resuelto | 2026-09-10 (email redactado; adopción de la política queda pendiente de decisión del equipo) |
| Responsable | Dante Paniagua |

## Causa raíz

No existe hoy un criterio formal de selección de librerías ni una etapa de validación automática en ningún pipeline de CI/CD de los tres proyectos relevados. La incorporación de una dependencia queda librada al criterio individual de quien la agrega, sin un chequeo de versión mínima, licencia, actividad de mantenimiento o vulnerabilidades conocidas antes de mergear. Esto permitió que se acumularan, sin que nadie lo marcara como problema en su momento, paquetes pre-1.0, un paquete end-of-life, y paquetes con licencias que exigen pago para uso comercial.

## Hallazgos

| # | Hallazgo | Riesgo |
|---|---|---|
| H1 | `iTextSharp 5.5.13.2` (SmartLoyalty) — licencia dual AGPLv3/comercial; según la propia página de licenciamiento de iText, distribuirlo en un producto cerrado sin publicar el código fuente propio bajo AGPL exige comprar licencia comercial. Además marcado `[DEPRECATED]` por su mantenedor (reemplazado por iText 7) | Alto |
| H2 | `EPPlus 5.4.1`/`5.5.2` (SmartLoyalty) — licencia dual Polyform Noncommercial/Comercial desde la v5; uso comercial requiere `LicenseContext.Commercial` y licencia paga | Alto |
| H3 | `AutoMapper 16.2.0` (SmartFran Cloud) — desde la v15.0 (julio 2025) es un producto comercial (dual RPL-1.5/licencia paga por equipo); la versión fijada en Cloud cae dentro del rango con licenciamiento comercial | Alto |
| H4 | **CORREGIDO** — el hallazgo original ("cero validación automática de dependencias") era incorrecto para SmartPedidos: Trivy sí corre activamente contra los tres servicios (`trivy image` para concentrador/platform, `trivy fs --scanners vuln,secret` para backOffice), vía el pipeline real, no visible desde los Jenkinsfiles ahora mayormente obsoletos que quedaron en cada repo de aplicación. El hallazgo original sí se sostiene para Cloud (GitHub Actions, sin herramienta de escaneo configurada) y SmartLoyalty (Jenkins, solo compilación y SonarQube). Lo que sigue siendo cierto en los tres: ninguno cubre licencias específicamente, y no existe `dependabot.yml`/`renovate.json` en ningún repositorio | Medio |
| H5 | Paquetes pre-1.0 en uso: `querystring@~0.2.1` (deprecado, backOffice), `regenerator-runtime@^0.13.3` (platformsService/concentradorService), `xlsx@~0.15.3` (backOffice), `MudBlazor.Markdown@0.1.0` (Cloud) | Medio |
| H6 | `moment`/`Moment.js` en uso en los tres proyectos SmartPedidos y en SmartLoyalty — en modo mantenimiento desde 2020 según su propio mantenedor, ~72KB min+gzip vs. ~2KB de la alternativa recomendada (Day.js) | Bajo |
| H7 | `swagger-ui-dist` (dependencia transitiva de `swagger-ui-express`, presente en `platformsService` y `concentradorService`, ambos corriendo en contenedores ECS/Fargate): 11.77 MB sin comprimir — la dependencia más pesada de ambos servicios, muy por encima de `mongoose` (~2.17 MB) o `core-js` (~1.36 MB) | Bajo |
| H8 | `apexcharts` (backOffice, Angular): 920 KB minificado / 260 KB gzip — la dependencia más pesada del bundle de navegador entre las revisadas (`xlsx` ~412KB/140KB, `@fortawesome/fontawesome-free` ~89KB/22KB) | Bajo |
| H9 | `SkiaSharp` + `SkiaSharp.NativeAssets.Linux` (SmartFran Cloud): ~7.14 MB + ~15.62 MB = ~22.8 MB combinados de una sola cadena de dependencia, por los binarios nativos empaquetados | Bajo |
| H10 | **RETRACTADO Y CORREGIDO DOS VECES** — el hallazgo original decía que `concentradorService` corría sobre Node 14 (EOL); esa lectura vino de la rama `stg` (no productiva), no de `develop`. Confirmado en `develop` (rama productiva real): `concentradorService` corre sobre **Node 20.20-alpine**, versión vigente. No hay riesgo de runtime EOL en este servicio | Informativo (hallazgo original descartado) |
| H10b | `backOffice` **no** corre como proceso Node en producción — se despliega como archivos estáticos a S3+CloudFront, confirmado independientemente en `smartpedidos/events/20260910_backoffice-jenkins-sonarqube-onboarding/`. El `Dockerfile` del repo (`FROM node:10-alpine`) no es el que realmente usa ningún pipeline | Informativo (no es un riesgo confirmado) |
| H11 | Ninguno de los tres proyectos SmartPedidos tiene `package-lock.json` commiteado — sin instalación reproducible/pinneada. Esto además bloquea una herramienta propia ya existente (no conectada al pipeline), que requiere `package-lock.json` para poder ejecutarse | Medio |
| H12 | Existe una herramienta propia sin conectar que ya implementa el eje de "salud del paquete" (deprecación + antigüedad de publicación >2 años) cruzado con hallazgos de Trivy — no es necesario construir esto desde cero | Informativo (oportunidad, no riesgo) |
| H13 | Consulta en vivo a OSV.dev (versión instalada específica, no solo "última disponible") sobre las 90 dependencias npm de SmartPedidos: `axios@1.13.6` (platformsService y concentradorService) — 10 CVEs HIGH, 17 MODERATE, 1 LOW; `xlsx@0.15.6` (backOffice) — 5 CVEs HIGH; `moment@2.24.0` (backOffice) — 2 CVEs HIGH; `express-jwt@5.3.3` (platformsService) — 1 CVE HIGH; `jsonwebtoken@8.5.1` (platformsService) — 3 CVEs HIGH. El hallazgo de `axios` coincide exactamente con el ya confirmado por Trivy en GITIN-2000 | Alto |
| H14 | Mismo chequeo (`/cloud-nuget-compliance`) aplicado a las 238 dependencias NuGet de SmartFran Cloud, sobre `main` real (el clon local estaba en `dev` y 156 commits atrás — corregido antes de relevar). CVEs confirmados: `AutoMapper@12.0.1`/`@13.0.1` (DoS por recursión no controlada, `GHSA-rvv3-g6hj-g44x` — la versión más nueva, 16.2.0, no está afectada) y `System.Text.Json@8.0.0` (DoS, CVE-2024-43485) | Alto |
| H15 | `Microsoft.Extensions.Configuration.Binder@8.5.0`, declarado en un `.csproj` de Cloud, **nunca fue publicado** en NuGet (la versión 8.x más alta real es 8.0.2) — no puede resolver en un `dotnet restore` limpio | Alto |

## Recursos afectados

| Recurso | Detalle |
|---|---|
| SmartPedidos — `backOffice`, `platformsService`, `concentradorService` | npm, 90 dependencias directas relevadas en conjunto |
| SmartLoyalty — solución completa | NuGet/.NET Framework, 261 paquetes únicos relevados |
| SmartFran Cloud — solución completa | NuGet/.NET moderno, 237 paquetes únicos relevados |

## Comandos ejecutados

Historial completo en `scripts.sh`. Comandos centrales:

| # | Comando / Script | Propósito |
|---|---|---|
| C1 | `find ... -iname "package.json"/"*.csproj"/"packages.config"` | Ubicar todos los manifiestos de dependencias en los tres proyectos |
| C2 | Extracción de `dependencies` de cada `package.json` (Python) | Listar paquetes npm y versiones por servicio de SmartPedidos |
| C3 | Extracción de paquetes de `packages.config` (grep/sed) | Listar paquetes NuGet y versiones en SmartLoyalty |
| C4 | Extracción de `PackageReference` de `.csproj` (grep/sed) | Listar paquetes NuGet y versiones en SmartFran Cloud |
| C5 | `grep` sobre workflows de GitHub Actions y Jenkinsfiles | Confirmar ausencia de Trivy/Snyk/Socket/Dependabot en CI/CD |
| C6 | Consulta a registry de npm + verificación de fuentes públicas | Confirmar licencia/deprecación/estado de mantenimiento de los paquetes citados en los hallazgos |

## Acciones propuestas

1. (Realizado) Se relevaron las dependencias reales de los tres proyectos y se confirmó la ausencia de validación de dependencias en CI/CD.
2. (Realizado) Se redactó el email a Operaciones (`email_ops.md`) con los criterios propuestos y ejemplos reales de cada proyecto.
3. (Pendiente) Enviar el email a Operaciones y acordar si los criterios se adoptan como política formal.
4. (Pendiente) Resolver la exposición de licencia comercial de `iTextSharp`, `EPPlus` y `AutoMapper` — confirmar con quien gestione compras/licenciamiento si ya existe licencia comercial vigente para alguno de los tres, y decidir por caso: comprar licencia, migrar a una alternativa con licencia permisiva, o fijar la versión a la última release previa al cambio de licencia (aplica a AutoMapper).
5. (Pendiente, si se adopta la política) Incorporar una herramienta de validación de dependencias (Trivy, Snyk, Socket o Dependabot) en al menos un pipeline como piloto antes de extenderlo a los demás.
6. (Realizado) Se creó `/sp-npm-compliance` y `/cloud-nuget-compliance`, y se corrió contra las 90 dependencias npm de SmartPedidos y las 238 de SmartFran Cloud.
7. (Pendiente) Actualizar `AutoMapper` (Cloud), `System.Text.Json` (Cloud), `axios`/`xlsx`/`moment`/`express-jwt`/`jsonwebtoken` (SmartPedidos) — todas con CVEs de severidad HIGH confirmados en la versión actualmente instalada.
8. (Pendiente) Corregir o confirmar `Microsoft.Extensions.Configuration.Binder@8.5.0` en el `.csproj` de Cloud que lo referencia — esa versión nunca fue publicada en NuGet.

## Hallazgos secundarios

- Deriva de versiones del mismo paquete entre proyectos sin coordinación aparente: `bootstrap` 3.4.1/4.6.0/5.2.3, `jQuery` 3.5.1/3.7.0 (SmartLoyalty); `Azure.Identity` en 5 versiones distintas (1.11.4 a 1.21.0), `AutoMapper` 12.0.1/13.0.1/16.2.0, `Microsoft.EntityFrameworkCore` 7.0.5/7.0.12/7.0.13 (SmartFran Cloud). No es uno de los cuatro criterios solicitados originalmente, pero refuerza la necesidad de un proceso más consistente de actualización de dependencias.
- Se encontró un rango de versión flotante (`System.ServiceModel.*` fijado a `4.10.*` en SmartFran Cloud) en lugar de una versión fija — permite que `dotnet restore` traiga una versión nueva sin un commit que lo refleje.
