**Asunto:** Vulnerabilidades de Node.js (release del 21/10): SmartPedidos usa Node 20, que no recibe corrección

Hola equipo,

Les resumo el release de seguridad de Node.js del 21/10 y cómo nos toca, en [GITIN-2310](https://smartit-ar.atlassian.net/browse/GITIN-2310).

**Qué pasó**
El 21/10 el proyecto Node.js publicó correcciones para diez vulnerabilidades (cuatro altas, tres medias y tres bajas) en las líneas 26, 24 y 22. Las versiones corregidas son 26.12.1, 24.22.1 y 22.23.4 ([aviso oficial](https://nodejs.org/en/blog/vulnerability/october-2026-security-releases)). Las cuatro altas son:
- **Brotli (CVE-2026-111497):** el decodificador escribe fuera de su buffer al descomprimir datos Brotli inválidos. Puede causar caída, lectura de memoria o ejecución remota de código. Aplica si la aplicación descomprime con `node:zlib` datos que no controla.
- **DNS (CVE-2026-105482):** `dns.resolve*()` corta los nombres en un byte nulo, lo que permite saltear una validación de nombre previa.
- **TLS, dígitos de ancho completo (CVE-2026-105483):** `tls.checkServerIdentity()` no reconoce como IP un host escrito con esos dígitos y lo compara contra los nombres DNS del certificado, por lo que puede aceptar un certificado emitido para otro nombre. Afecta solo a las líneas 26 y 24.
- **TLS, IPv4 con ceros a la izquierda (CVE-2026-106069):** el cliente puede validar el certificado contra una IP distinta de la que realmente se conecta, si usa una IPv4 con ceros a la izquierda y el resolvedor del sistema la interpreta de otra forma. Depende de la plataforma.

Las seis restantes:

| CVE | Severidad | Componente | Líneas afectadas |
|---|---|---|---|
| CVE-2026-105481 | Media | Sockets keep-alive del agente HTTP: una respuesta no solicitada puede tomarse como respuesta de la solicitud siguiente | 26, 24, 22 |
| CVE-2026-106072 | Media | `tls.checkServerIdentity()`: acepta IPv4 en formatos no canónicos contra nombres DNS numéricos del certificado | 26, 24, 22 |
| CVE-2026-106074 | Media | `crypto.randomUUID()` y `randomInt()`: valores repetidos en procesos iniciados desde un snapshot o SEA | 26, 24, 22 |
| CVE-2026-106070 | Baja | `zlib.ZipFile`: lectura de bytes incorrectos si el encabezado local no coincide con el directorio central | 26 |
| CVE-2026-106071 | Baja | Modelo de permisos: un comodín en `--allow-fs-read` concede más acceso del pedido | 26 |
| CVE-2026-106073 | Baja | Modelo de permisos: `fs.realpathSync()` permite comprobar y enumerar rutas fuera de las permitidas | 26, 24, 22 |

Node 20 no figura en la lista del aviso, que no publica corrección para esa línea y dice que las versiones sin soporte "siempre están afectadas". El mismo release actualiza los certificados raíz incluidos en Node por el incidente de la CA eMudhra (el que ya les comenté: no usamos esa CA).

**Cómo nos toca**

| Plataforma | Dónde se usa Node | Versión | ¿Nos toca? |
|---|---|---|---|
| SmartPedidos | `platformsService` y `concentradorService` (imagen base en el Dockerfile) | 20 en `develop`, la rama que se despliega en producción. Node 20 no tiene soporte | Node 20 no recibe corrección. El código propio no usa los módulos afectados, pero `axios` sí usa el descompresor Brotli de Node |
| SmartLoyalty | No encontré Node en sus servicios (son .NET) | No relevada | No por los servicios; sin relevar en herramientas |
| SmartCloud | No encontré Node en sus servicios (son .NET) | No relevada | No por los servicios; sin relevar en herramientas |

Detalle de SmartPedidos:
- **Versión:** ambos servicios construyen su imagen sobre `node:20.20-alpine` en `develop` (lectura de los repositorios actualizados el 26/10). No verifiqué la versión que corre dentro del contenedor en producción.
- **Exposición:** no encontré en el código propio uso directo de Brotli, `zlib`, `dns.resolve` ni `tls.checkServerIdentity`. Ambos usan `axios`, que en su adaptador de Node (rama `v1.x`; no leí el tag exacto `1.20.0`) descomprime con `zlib.createBrotliDecompress` las respuestas con `content-encoding: br` y anuncia `br` en `Accept-Encoding` por defecto. Ninguno cambia esas opciones. El riesgo sería una respuesta maliciosa de un servidor al que nos conectamos (por ejemplo una plataforma de delivery), no tráfico entrante.
- **TLS y DNS:** requieren condiciones que no encontré en el código (hosts como IP escrita en formatos no canónicos). Los hosts configurados fuera del código no los revisé.
- **Trivy:** el análisis de imágenes no alcanza esta falla; revisa los paquetes de `node_modules`, no el runtime de Node, donde está el descompresor.

**Recomendación**
1. Confirmar que la imagen de producción de ambos servicios se construyó con el `FROM` de `develop` (Node 20).
2. Migrar primero ambos a Node 22, cambiando las dos líneas `FROM` del `Dockerfile` de `api/` en `develop`. No hay corrección dentro de Node 20, y 22 es la línea con soporte más cercana, por lo que implica el menor esfuerzo y el menor riesgo de incompatibilidades:

| Opción | `FROM` | Esfuerzo | Qué corrige |
|---|---|---|---|
| Quedarse en Node 20 | `node:20.20-alpine` (sin cambio) | Ninguno | Nada: no hay corrección para esa línea (el aviso no detalla cuáles de las diez la afectan) |
| Primer paso propuesto: Node 22 | `node:22.23.4-alpine` | Bajo: un salto de línea | Las siete que afectan a la línea 22 (CVE-2026-105483, CVE-2026-106070 y CVE-2026-106071 no la afectan) |
| Segundo paso: Node 24 LTS | `node:24.22.1-alpine` | Medio: dos saltos de línea | Las ocho que afectan a la línea 24 (CVE-2026-106070 y CVE-2026-106071 solo aplican a 26) |

   Propongo empezar por Node 22 porque es el cambio más chico y deja los servicios sin ninguna de las vulnerabilidades que afectan a esa línea. Node 24 queda como segundo paso por su mayor margen de soporte (no verifiqué hoy las fechas de fin de soporte de cada línea). Es una preferencia mía, no validada con pruebas. Es una propuesta, no una decisión tomada. No verifiqué que los tags existan en Docker Hub ni probé los servicios con Node 24 o 22; hay que probar en el entorno de test antes de promover el cambio.
3. Relevar si hay otros usos de Node en herramientas y pipelines de Operaciones.
4. Mientras la migración no esté hecha, tratar como no confiables las respuestas de servidores externos y priorizar las conexiones de salida hacia terceros al revisar posibles incidentes.
5. Mitigación temporal para la falla de Brotli, a evaluar mientras Node 20 no tenga corrección. El aviso oficial no publica ninguna; esta viene de fuentes secundarias ([Qualys](https://blog.qualys.com/product-tech/2026/10/23/node-js-patches-brotli-remote-code-execution-flaw-find-vulnerable-runtimes-before-attackers-do) y otras) y no la probé en nuestros servicios:
   - **Entrada:** en el proxy inverso, quitar `Content-Encoding: br` de las solicitudes no confiables, y en `body-parser` poner `inflate` en `false`.
   - **Salida (`axios`):** según su código fuente (rama `v1.x`), se evita con `decompress: false` o enviando un `Accept-Encoding` propio sin `br`. Habría que confirmarlo en la versión instalada (`~1.20.0`) y revisar que ninguna integración dependa de la compresión Brotli o de la descompresión automática.

   No protege contra las otras tres vulnerabilidades altas ni contra las medias; solo reduce la superficie de la de Brotli.

Saludos.
