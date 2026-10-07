# Eventos — 20260910_dependency_best_practices_policy

## 2026-09-10 — Apertura del ticket (GITIN-2026)

He abierto este evento a partir de un pedido proactivo (sin incidente disparador): redactar un email de buenas prácticas para selección de librerías (npm, NuGet, .NET), con ejemplos reales tomados de los repositorios propios en lugar de recomendaciones genéricas.

## 2026-09-10 — Relevamiento de dependencias reales en los tres proyectos

**Comando:** C1-C4 — localización y extracción de manifiestos de dependencias
**Resultado:**
90 dependencias npm directas entre `backOffice`, `platformsService` y `concentradorService` de SmartPedidos; 261 paquetes NuGet únicos en SmartLoyalty; 237 paquetes NuGet únicos en SmartFran Cloud.

He confirmado, revisando los tres conjuntos, la presencia de paquetes pre-1.0 (`querystring@~0.2.1`, `regenerator-runtime@^0.13.3`, `xlsx@~0.15.3`, `MudBlazor.Markdown@0.1.0`) y de un paquete marcado end-of-life por su propio mantenedor (`iTextSharp`).

## 2026-09-10 — Confirmación de ausencia de validación de dependencias en CI/CD

**Comando:** C5 — grep sobre workflows de GitHub Actions y Jenkinsfiles
**Resultado:**
Cero coincidencias para Trivy, Snyk, Socket o Dependabot en ningún pipeline de los tres proyectos, y ningún `dependabot.yml`/`renovate.json` en ningún repositorio.

He confirmado que se trata de un gap real y no de una suposición — ningún proyecto valida hoy versión mínima, licencia ni vulnerabilidades conocidas antes de incorporar una dependencia.

## 2026-09-10 — Verificación de licencias y estado de mantenimiento contra fuentes públicas

**Comando:** C6 — consulta a registry de npm y verificación de fuentes públicas
**Resultado:**
Confirmado vía la propia página de licenciamiento de iText: `iTextSharp` es AGPLv3/comercial dual. Confirmado vía el FAQ de licencia de EPPlus: `EPPlus 5+` es Polyform Noncommercial/comercial dual. Confirmado vía los anuncios propios de Jimmy Bogard (2025): `AutoMapper` es comercial desde la v15.0, y la versión fijada en SmartFran Cloud (16.2.0) cae dentro de ese rango. Confirmado vía el registry de npm: `querystring` está deprecado (mensaje del propio paquete) y `xlsx@0.15.3` está muy por detrás de la última versión publicada (0.18.5), con versiones deprecadas del mismo paquete redirigiendo a un CDN propio en lugar de npm.

He evitado dejar cualquiera de estas afirmaciones de licencia sin verificar antes de incluirlas en el ticket, dado el impacto de cumplimiento que implican.

## 2026-09-10 — Redacción de la política y del email

He redactado `ops.md` con los hallazgos consolidados y `email_ops.md` con el email final a Operaciones, cubriendo los cuatro criterios solicitados (versión mínima, salud/SCM, tamaño y dependencias, licencia) más la validación en CI/CD, cada uno ilustrado con un ejemplo real y verificado.

## 2026-09-11 — Corrección de hallazgos de CI/CD y ejecución del chequeo completo de cumplimiento npm

He corregido los hallazgos sobre versión de Node y validación en CI/CD de SmartPedidos, que estaban basados en Jenkinsfiles obsoletos dentro de cada repo de aplicación en lugar del pipeline real. He confirmado, leyendo la documentación real del pipeline y los eventos ya documentados en `smartpedidos/events/`, que `concentradorService` corre sobre Node 20 (no Node 14 — esa lectura vino de la rama `stg`, no de `develop`) y que Trivy ya corre activamente en los tres servicios. He creado `smartpedidos/docs/cicd.md` como referencia separada para no repetir esta reconstrucción en el futuro.

He creado la skill `/sp-npm-compliance` y la he ejecutado contra los tres proyectos de SmartPedidos, sobre `develop` actualizado (he hecho fetch y fast-forward de `platformsService`, que estaba 2 commits atrás, sin impacto en dependencias). He encontrado y he corregido dos bugs reales en el script de chequeo antes de confiar en sus resultados: el registry de npm omite el campo `readme` para paquetes de alto tráfico (lo cual habría marcado incorrectamente a `express`/`@angular/core` como sin documentación), y el cálculo de "última versión compatible con el Dockerfile" no excluía versiones prerelease, inflando el resultado para 5 paquetes. Resultado final: 90 dependencias revisadas, reporte completo en `data/npm_compliance_report.md`.

## 2026-09-14 — Ampliación de la explicación de severidad CVE en el email a SmartPedidos

He agregado a `email_ops_smartpedidos.md` una explicación en criollo de qué separa cada nivel de severidad (CRITICAL/HIGH/MODERATE/LOW), apoyada en el caso real del authorization bypass de `express-jwt` ya citado en el email, más enlaces a la especificación oficial de CVSS (FIRST.org) y al resumen de NVD para quien quiera el detalle completo. He enviado el email con estos cambios incluidos.
