**Asunto:** Propuesta de buenas prácticas para dependencias npm — SmartPedidos (backOffice, platformsService, concentradorService) — GITIN-2026

Hola equipo,

Les escribo para proponer un conjunto de criterios al elegir una librería npm, a partir de un relevamiento sobre las dependencias reales de los tres servicios de SmartPedidos (`backOffice`, `platformsService`, `concentradorService`). Cada punto está ilustrado con un caso real encontrado en nuestros propios repositorios.

**1. Versión mínima 1.0.0**

Propongo evitar fijar dependencias en versiones pre-1.0 (0.x), salvo excepción justificada. Casos actuales: `querystring` (0.2.1, backOffice) está además marcado deprecado por su propio mantenedor, que recomienda `URLSearchParams` nativo de Node en su lugar. `regenerator-runtime` (0.13.x, platformsService y concentradorService) también está en 0.x.

**2. Salud del paquete**

Un caso a tener en cuenta: `xlsx` (SheetJS, backOffice) — las versiones más viejas de este paquete en npm traen su propio mensaje de deprecación redirigiendo a un CDN propio (`cdn.sheetjs.com`) en lugar de npm para versiones actuales. Que el mantenedor haya movido su canal principal de distribución fuera de npm es una señal de salud a tener en cuenta, más allá de que el paquete en sí siga técnicamente soportado.

**3. Documentación y adopción de la comunidad**

Este punto lo sumo aparte porque me parece más importante de lo que parece a primera vista: una librería con buena documentación (README completo, ejemplos, changelog) no solo nos ayuda a nosotros — también le permite a un asistente LLM ayudarnos a resolver un incidente futuro sin tener que leer el código fuente completo de la dependencia. Una librería mal documentada nos deja mucho más solos el día que falla en producción. La cantidad de descargas semanales/mensuales en npm es una señal complementaria útil.

**4. Tamaño y dependencias transitivas**

Acá conviene distinguir por tipo de servicio:

- `platformsService` y `concentradorService` corren como contenedores en ECS/Fargate — ahí lo que pesa es el tamaño de la imagen, no el peso de transferencia al navegador. En ambos, la dependencia más pesada es `swagger-ui-dist` (la trae `swagger-ui-express`): 11.77MB sin comprimir, muy por encima de `mongoose` (~2.17MB) o `core-js` (~1.36MB). Es la interfaz visual completa de Swagger empaquetada en cada imagen de producción — vale la pregunta de si hace falta ahí o alcanza con tenerla solo en un entorno de documentación.
- `backOffice` sí se transfiere al navegador — ahí aplica bundlephobia.com directamente: `apexcharts` es la dependencia más pesada revisada, con 920KB minificado / 260KB gzip, contra ~412KB/140KB de `xlsx` o ~89KB/22KB de `@fortawesome/fontawesome-free`.
- Los tres servicios usan `moment` — su propio equipo lo declaró en modo mantenimiento desde 2020, recomendando alternativas como Day.js (~2KB) para código nuevo.

**5. Revisión de la licencia**

A diferencia de lo que encontré en SmartLoyalty y SmartFran Cloud, no encontré ninguna dependencia npm de SmartPedidos con una licencia que exija pago por uso comercial — la gran mayoría son MIT, con algunas Apache-2.0/ISC. No es un hallazgo de riesgo, pero lo dejo asentado como parte de la revisión.

**6. Validación automática en CI/CD**

Acá el panorama es mejor de lo que parece a primera vista revisando solo lo que quedó committeado en cada repo de aplicación: el pipeline real de los tres servicios ya corre Trivy — `trivy image` para concentrador/platform (confirmado, con hallazgos reales ya usados en GITIN-2000), `trivy fs` para backOffice (armado el 2026-09-10, reportado como funcionando pero todavía sin un log de build exitoso confirmado de forma independiente). Lo que falta: ese escaneo no cubre licencias específicamente (es de vulnerabilidades/secretos), y no hay `dependabot.yml`/`renovate.json` en ningún repositorio. Además, ya existe un script propio sin conectar que revisa paquetes deprecados o sin publicar hace más de 2 años — hoy no podría correr porque ningún proyecto tiene `package-lock.json` commiteado. Me parece más valioso terminar de conectar esa herramienta que ya tenemos que armar una nueva.

**7. CVEs de la librería**

Este punto lo separé de "salud del paquete" a propósito: una librería puede estar activamente mantenida y aun así tener vulnerabilidades conocidas en la versión específica que tenemos instalada — no alcanza con mirar si el proyecto sigue vivo. Corrí una consulta en vivo contra OSV.dev (la misma base de datos que usa Trivy) para las 90 dependencias de los tres proyectos, específicamente contra la versión instalada de cada una, y encontré casos concretos:

- `axios@1.13.6` (platformsService **y** concentradorService): 10 CVEs de severidad HIGH, 17 MODERATE, 1 LOW. Coincide exactamente con lo que ya habíamos encontrado con Trivy en GITIN-2000.
- `xlsx@0.15.6` (backOffice): 5 CVEs HIGH, incluyendo un prototype pollution.
- `moment@2.24.0` (backOffice): 2 CVEs HIGH, incluyendo un path traversal.
- `express-jwt@5.3.3` (platformsService): 1 CVE HIGH — authorization bypass.
- `jsonwebtoken@8.5.1` (platformsService): 3 CVEs HIGH relacionadas al manejo de keys legacy.

Propongo como regla: no compliant si la versión instalada tiene algún CVE de severidad HIGH o superior. ¿Por qué ese corte y no otro?

- Solo CRITICAL sería insuficiente: bajo CVSS, ese nivel queda reservado para el peor extremo (ej. ejecución remota de código sin autenticación). Cosas genuinamente peligrosas como el authorization bypass de `express-jwt` de arriba se clasifican HIGH, no CRITICAL — cortar solo en CRITICAL las dejaría pasar como "compliant".
- Incluir MODERATE/LOW sería demasiado ruidoso: son comunes y en su mayoría de bajo impacto práctico (solo `axios` trae 17 MODERATE además de las 10 HIGH) — tratar cualquier CVE como bloqueante generaría fatiga de alertas y el equipo terminaría ignorando el chequeo.
- No es un corte que inventé: coincide exactamente con lo que ya usa nuestro propio pipeline de Trivy en producción (`trivy image --severity CRITICAL,HIGH`). Este axioma solo aplica, al momento de elegir/mantener una librería, el mismo criterio que ya aplicamos al escanear la imagen ya construida.

Para quien no esté familiarizado, en criollo qué separa un nivel del otro:

- **CRITICAL** (CVSS 9.0-10.0): el peor caso — normalmente explotable de forma remota, sin necesitar credenciales ni interacción del usuario, con compromiso total (ej. ejecución remota de código). Es el nivel que uno imagina cuando piensa "alguien en internet toma el servidor sin esfuerzo".
- **HIGH** (7.0-8.9): impacto igual de serio, pero con alguna precondición — requiere cierto nivel de acceso previo, una configuración particular, o algo de interacción. El authorization bypass de `express-jwt` es un buen ejemplo real de esta lista: no es "cualquiera en internet sin hacer nada", pero sí es alguien saltándose el control de autorización una vez que llega al endpoint.
- **MODERATE/MEDIUM** (4.0-6.9): impacto limitado en la práctica — afecta parcialmente confidencialidad/disponibilidad, o necesita condiciones más específicas para explotarse. Es el motivo por el que no las tomo como bloqueantes en la regla propuesta.
- **LOW** (0.1-3.9): impacto menor incluso si se logra explotar, o muy difícil de explotar en la práctica.

Para el detalle completo (los rangos de puntaje CVSS exactos y cómo se calculan): especificación oficial de CVSS (FIRST.org) — https://www.first.org/cvss/specification-document — y el resumen de NVD — https://nvd.nist.gov/vuln-metrics/cvss.

Les propongo evaluar estos puntos como criterio a futuro para nuevas dependencias, y como paso previo, sumar `package-lock.json` a los tres proyectos para poder aprovechar la herramienta de salud de paquetes que ya existe. Más detalle (incluyendo la lista completa de paquetes relevados y sus CVEs) está en GITIN-2026.

Saludos,
Dante
