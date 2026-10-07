**Asunto:** Propuesta de buenas prácticas para selección de librerías (npm, NuGet, .NET) — GITIN-2026

Hola equipo,

Les escribo para proponer un conjunto de criterios al elegir una librería externa (npm, NuGet, cualquier dependencia .NET), a partir de un relevamiento que hice sobre las dependencias reales que ya usamos en SmartPedidos, SmartLoyalty y SmartFran Cloud. No es una lista de recomendaciones genéricas — cada punto está ilustrado con un caso real que encontré en nuestros propios repositorios, para que se vea por qué importa cada criterio.

**1. Versión mínima 1.0.0**

Propongo evitar fijar dependencias en versiones pre-1.0 (0.x), salvo excepción justificada — son versiones que el propio proyecto todavía considera inestables o en desarrollo. Hoy tenemos varios casos: `querystring` (0.2.1, en el backOffice de SmartPedidos) está además marcado deprecado por su propio mantenedor, que recomienda usar la API nativa `URLSearchParams` en su lugar — es una dependencia externa para algo que Node.js ya resuelve. También `regenerator-runtime` (0.13.x, en platformsService y concentradorService) y `MudBlazor.Markdown` (0.1.0, en Cloud) están en 0.x.

**2. Salud del paquete (actividad en su repositorio)**

Antes de sumar una librería, conviene mirar su repositorio: ¿tiene commits recientes?, ¿el propio mantenedor la sigue soportando? Un caso concreto que tenemos: `iTextSharp` (SmartLoyalty) está marcado explícitamente `[DEPRECATED]` en su propio repositorio de GitHub — el mantenedor dice textualmente que solo va a recibir fixes de seguridad y que el reemplazo es iText 7. Lo seguimos usando en producción.

**3. Documentación y adopción de la comunidad**

Este punto lo sumo aparte porque me parece más importante de lo que parece a primera vista: una librería con buena documentación (README completo, ejemplos, changelog) no solo nos ayuda a nosotros — también le permite a un asistente LLM (Claude, Copilot, lo que sea) ayudarnos a resolver un incidente futuro sin tener que leer el código fuente completo de la dependencia. Una librería mal documentada nos deja mucho más solos el día que falla en producción. La cantidad de descargas semanales/mensuales en npm es una señal complementaria útil — no determinante, pero una librería con poca adopción y sin documentación acumula las dos señales de riesgo al mismo tiempo.

**4. Tamaño y dependencias transitivas**

Acá conviene distinguir el tipo de servicio, porque la métrica que importa cambia:

- En `platformsService` y `concentradorService`, que corren como contenedores en ECS/Fargate, lo que más pesa no es el peso de transferencia al navegador sino el tamaño de la imagen (afecta tiempo de pull y espacio). En ambos servicios, la dependencia más pesada es `swagger-ui-dist` (la trae `swagger-ui-express`): 11.77MB sin comprimir, muy por encima de `mongoose` (~2.17MB) o `core-js` (~1.36MB). Es la interfaz visual completa de Swagger empaquetada en cada imagen de producción — vale la pregunta de si hace falta en el contenedor que corre en producción o si alcanza con tenerla solo en un entorno de documentación/desarrollo.
- En `backOffice` (Angular, sí se transfiere al navegador), ahí sí aplica bundlephobia.com directamente: `apexcharts` es la dependencia más pesada de las que revisé, con 920KB minificado / 260KB gzip, contra ~412KB/140KB de `xlsx` o ~89KB/22KB de `@fortawesome/fontawesome-free`.
- En SmartFran Cloud (.NET), el equivalente de NuGet es simplemente el tamaño del paquete (`nuget.org` lo expone directo): `SkiaSharp` pesa 7.14MB, y su dependencia transitiva `SkiaSharp.NativeAssets.Linux` suma otros 15.62MB — ~22.8MB entre las dos, por los binarios nativos que empaqueta para cada plataforma soportada.
- Aparte de estos casos puntuales, tenemos `moment` en los tres servicios de SmartPedidos y `Moment.js` en SmartLoyalty — su propio equipo lo declaró en modo mantenimiento desde 2020, recomendando alternativas como Day.js (~2KB) para proyectos nuevos. No hace falta migrar lo existente de un día para el otro, pero sí evitar sumarlo en código nuevo.

**5. Revisión de la licencia**

Este es el punto que más me preocupa de lo que encontré, porque no es solo una cuestión de calidad sino de cumplimiento legal. Tenemos al menos tres librerías cuya licencia exige pagar para uso comercial en un producto cerrado como los nuestros:

- `iTextSharp` (SmartLoyalty): licencia dual AGPL/comercial. Usarlo en un producto cerrado sin publicar el código propio bajo AGPL requiere licencia comercial paga, según la propia página de licenciamiento de iText.
- `EPPlus` (SmartLoyalty, versión 5+): licencia dual Polyform Noncommercial/comercial. El uso comercial requiere configurar explícitamente el modo comercial y tener una licencia paga.
- `AutoMapper` (SmartFran Cloud, versión 16.2.0): desde julio de 2025 (v15.0 en adelante) pasó a ser un producto comercial con licencia paga por equipo. La versión que tenemos fijada en Cloud ya cae dentro de ese rango.

No sé si alguna de estas tres ya tiene licencia comercial comprada — eso lo dejo para quien maneje licenciamiento/compras, pero me parece importante que quede visible antes de que aparezca en una auditoría.

**6. Validación automática en CI/CD**

El panorama real es distinto por proyecto: SmartPedidos ya corre Trivy y SonarQube (además de una revisión de código) en su pipeline real — más completo de lo que parecía a primera vista revisando solo lo que quedó committeado en cada repo de aplicación. SmartFran Cloud corre en GitHub Actions, y ahí no encontré ninguna herramienta de escaneo de vulnerabilidades configurada. SmartLoyalty corre en Jenkins, pero solo para compilación y SonarQube — tampoco con escaneo de vulnerabilidades.

Gap real en los tres: ninguno cubre licencias específicamente, y no encontré `dependabot.yml`/`renovate.json` en ningún repositorio. Para SmartPedidos puntualmente, ya existe un script propio que revisa paquetes deprecados o sin publicar hace más de 2 años — armado pero no conectado al pipeline, y hoy no podría correr porque ningún proyecto tiene `package-lock.json` commiteado. Me parece más valioso terminar de conectar esa herramienta que ya existe que armar una nueva desde cero.

**7. CVEs de la librería**

Lo separo de "salud del paquete" a propósito: una librería activamente mantenida puede tener igual vulnerabilidades conocidas en la versión específica que tenemos instalada. Corrí una consulta en vivo contra OSV.dev (la misma base que usa Trivy) contra la versión instalada de cada dependencia — no solo contra la última versión disponible — tanto en npm (SmartPedidos) como en NuGet (SmartFran Cloud):

- `axios@1.13.6` (platformsService y concentradorService): 10 CVEs HIGH — coincide exactamente con lo ya encontrado por Trivy en GITIN-2000.
- `xlsx@0.15.6` (backOffice): 5 HIGH. `moment@2.24.0` (backOffice): 2 HIGH. `express-jwt@5.3.3` y `jsonwebtoken@8.5.1` (platformsService): 1 y 3 HIGH respectivamente.
- `AutoMapper@12.0.1`/`@13.0.1` (Cloud): 1 HIGH cada uno — denegación de servicio por recursión no controlada. La versión más nueva (16.2.0, la comercial) no está afectada — otro costo concreto de la deriva de versiones ya mencionada arriba.
- `System.Text.Json@8.0.0` (Cloud): 1 HIGH (CVE-2024-43485, denegación de servicio).

Propongo como regla: no compliant si la versión instalada tiene algún CVE de severidad HIGH o superior. ¿Por qué ese corte?

- Solo CRITICAL sería insuficiente: bajo CVSS, ese nivel queda reservado para el peor extremo. El authorization bypass de `express-jwt` de arriba, por ejemplo, es HIGH, no CRITICAL — cortar solo en CRITICAL lo dejaría pasar como "compliant".
- Incluir MODERATE/LOW sería demasiado ruidoso: son comunes y de bajo impacto práctico en su mayoría (solo `axios` trae 17 MODERATE además de las 10 HIGH) — tratar cualquier CVE como bloqueante generaría fatiga de alertas.
- No es un corte inventado: coincide con lo que ya usa nuestro propio pipeline de Trivy en SmartPedidos (`trivy image --severity CRITICAL,HIGH`). El axioma solo aplica, al elegir/mantener una librería, el mismo criterio que ya aplicamos al escanear la imagen ya construida.

Les propongo que evaluemos estos siete puntos como criterio a futuro para nuevas dependencias, y que decidamos aparte qué hacemos con los tres casos de licencia comercial que ya están en producción. Más detalle de todo esto (incluyendo la lista completa de paquetes relevados) está en GITIN-2026.

Saludos,
Dante
