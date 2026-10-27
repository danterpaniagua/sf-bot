**Asunto:** Vulnerabilidades de Node.js (release del 21/10): SmartPedidos usa Node 20, que no recibe corrección

Hola equipo,

Les resumo el release de seguridad de Node.js del 21/10 y cómo nos toca, en [GITIN-2310](https://smartit-ar.atlassian.net/browse/GITIN-2310).

**Qué pasó**
El 21/10 el proyecto Node.js publicó correcciones para diez vulnerabilidades (cuatro altas, tres medias y tres bajas) en las líneas 26, 24 y 22. Las versiones corregidas son 26.12.1, 24.22.1 y 22.23.4 ([aviso oficial](https://nodejs.org/en/blog/vulnerability/october-2026-security-releases)). Las cuatro altas son:
- **Brotli (CVE-2026-111497):** el decodificador escribe fuera de su buffer al descomprimir datos Brotli inválidos. Puede causar caída, lectura de memoria o ejecución remota de código. Aplica si la aplicación descomprime con `node:zlib` datos que no controla.
- **DNS (CVE-2026-105482):** `dns.resolve*()` corta los nombres en un byte nulo, lo que permite saltear una validación de nombre previa.
- **Validación de certificados TLS, IP con dígitos de ancho completo (CVE-2026-105483):** `tls.checkServerIdentity()` no reconoce como IP un host escrito con dígitos de ancho completo y lo compara contra los nombres DNS del certificado, por lo que puede aceptar un certificado emitido para otro nombre. Afecta solo a las líneas 26 y 24.
- **Validación de certificados TLS, IPv4 con ceros a la izquierda (CVE-2026-106069):** el cliente puede validar el certificado contra una IP distinta de la que realmente se conecta, si usa una IPv4 escrita con ceros a la izquierda y el resolvedor del sistema la interpreta de otra forma. Depende de la plataforma.

Las seis restantes, con su CVE:

| CVE | Severidad | Componente | Líneas afectadas |
|---|---|---|---|
| CVE-2026-105481 | Media | Sockets keep-alive del agente HTTP: una respuesta no solicitada puede tomarse como respuesta de la solicitud siguiente | 26, 24, 22 |
| CVE-2026-106072 | Media | `tls.checkServerIdentity()`: acepta IPv4 en formatos no canónicos contra nombres DNS numéricos del certificado | 26, 24, 22 |
| CVE-2026-106074 | Media | `crypto.randomUUID()` y `randomInt()`: valores repetidos en procesos iniciados desde un snapshot o SEA | 26, 24, 22 |
| CVE-2026-106070 | Baja | `zlib.ZipFile`: lectura de bytes incorrectos si el encabezado local no coincide con el directorio central | 26 |
| CVE-2026-106071 | Baja | Modelo de permisos: un comodín en `--allow-fs-read` concede más acceso del pedido | 26 |
| CVE-2026-106073 | Baja | Modelo de permisos: `fs.realpathSync()` permite comprobar y enumerar rutas fuera de las permitidas | 26, 24, 22 |

Las cuatro altas aplican a la línea 22 salvo CVE-2026-105483 (solo 26 y 24). Node 20 no figura en la lista del aviso, que tampoco publica corrección para esa línea.

El mismo release actualiza los certificados raíz incluidos en Node por el incidente de la CA eMudhra (el que ya les comenté: no usamos esa CA).

**Cómo nos toca**

| Plataforma | Dónde se usa Node | Versión | ¿Nos toca? |
|---|---|---|---|
| SmartPedidos | `platformsService` y `concentradorService` (imagen base en el Dockerfile) | 20 en `develop`, la rama que se despliega en producción. Node 20 no tiene soporte | Node 20 no recibe corrección. El código propio de `platformsService` y `concentradorService` no usa los módulos afectados, pero `axios` sí usa el descompresor Brotli de Node (ver detalle) |
| SmartLoyalty | No encontré Node en sus servicios (son .NET) | No relevada | No por los servicios; sin relevar en herramientas |
| SmartCloud | No encontré Node en sus servicios (son .NET) | No relevada | No por los servicios; sin relevar en herramientas |

El detalle de SmartPedidos:
- **SmartPedidos:** `platformsService` y `concentradorService` construyen su imagen sobre `node:20.20-alpine` en la rama `develop` (lectura de los repositorios actualizados el 26/10), que es la que se despliega en producción. No verifiqué la versión que corre dentro del contenedor en producción. Node 20 no figura entre las líneas corregidas y el aviso dice que las versiones sin soporte "siempre están afectadas" cuando sale un release de seguridad, sin ofrecer corrección para ellas. Por lo tanto, mientras sigamos en Node 20 no hay parche disponible.
- **Exposición real:** no encontré en el código propio uso directo de Brotli, `zlib`, `dns.resolve` ni `tls.checkServerIdentity`. Ambos servicios usan `axios`, que en su adaptador de Node (rama `v1.x` del código fuente publicado; no leí el tag exacto `1.20.0`) descomprime con `zlib.createBrotliDecompress` las respuestas con `content-encoding: br` y anuncia `br` en `Accept-Encoding` por defecto. Ninguno de los dos servicios cambia esas opciones. Por eso el descompresor afectado se usa de forma indirecta, y el riesgo sería una respuesta maliciosa de un servidor al que nos conectamos (por ejemplo una plataforma de delivery), no tráfico entrante. Las vulnerabilidades de TLS y DNS requieren condiciones que no encontré en el código (hosts como IP escrita en formatos no canónicos); los hosts configurados fuera del código no los revisé. El análisis de imágenes con Trivy no alcanza esta falla: revisa los paquetes de `node_modules`, no el runtime de Node, donde está el descompresor.

**Recomendación**
1. Confirmar que la imagen de producción de `platformsService` y `concentradorService` se construyó con el `FROM` de `develop` (Node 20).
2. Planificar la migración de ambos a una línea con soporte: 24.22.1 (LTS) o 22.23.4. Es la única forma de recibir estas correcciones; probar en el entorno de test antes de producción. El cambio concreto propuesto en el `Dockerfile` de `api/` de cada servicio, en las dos líneas `FROM`:

| Servicio | Rama | `FROM` actual | `FROM` propuesto |
|---|---|---|---|
| `platformsService` | `develop` | `node:20.20-alpine` | `node:24.22.1-alpine` |
| `concentradorService` | `develop` | `node:20.20-alpine` | `node:24.22.1-alpine` |

   Para elegir la versión, estas son las opciones. No existe una corrección dentro de Node 20 (el aviso no publica ninguna para esa línea), así que el menor esfuerzo es pasar a la línea más cercana, 22:

| Opción | `FROM` en `develop` | Esfuerzo | Qué corrige | Nota |
|---|---|---|---|---|
| Quedarse en Node 20 | `node:20.20-alpine` (sin cambio) | Ninguno | Nada: sin corrección disponible | Sigue expuesto a los diez avisos |
| Mínimo esfuerzo: Node 22 | `node:22.23.4-alpine` | Bajo: un salto de línea | Los avisos que afectan a la línea 22 (nueve de diez; CVE-2026-105483 solo afecta a 26 y 24) | Es la línea más cercana a la actual; tag sin verificar |
| Recomendada: Node 24 LTS | `node:24.22.1-alpine` | Medio: dos saltos de línea | Los diez avisos | Más margen de soporte; tag sin verificar |

   Elegí Node 24 como propuesta de la tabla anterior por el margen de soporte, pero Node 22 es el camino de menor esfuerzo y también recibe las correcciones. Esa preferencia es mía, no está validada con pruebas.

   El cambio se limita a `develop`, que es la rama que se despliega. Es una propuesta, no una decisión tomada. No verifiqué que el tag `node:24.22.1-alpine` exista en Docker Hub ni probé los servicios con Node 24; hay que probar en el entorno de test antes de promover el cambio.
3. Relevar si hay otros usos de Node en herramientas y pipelines de Operaciones.
4. Mientras la migración no esté hecha, tratar como no confiables las respuestas de servidores externos y priorizar las conexiones de salida hacia terceros al revisar posibles incidentes.
5. Mitigación temporal para la falla de Brotli, a evaluar mientras Node 20 no tenga corrección. El aviso oficial no publica ninguna mitigación; esta viene de fuentes secundarias ([Qualys](https://blog.qualys.com/product-tech/2026/10/23/node-js-patches-brotli-remote-code-execution-flaw-find-vulnerable-runtimes-before-attackers-do) y otras) y no la probé en nuestros servicios. La idea es que ningún dato Brotli llegue a `node:zlib`:
   - **Entrada:** en el proxy inverso, quitar el encabezado `Content-Encoding: br` de las solicitudes no confiables, y en `body-parser` poner la opción `inflate` en `false`.
   - **Salida (nuestras llamadas con `axios`):** según el código fuente de `axios` (rama `v1.x`), se evita desactivando la descompresión con la opción `decompress: false`, o enviando un `Accept-Encoding` propio sin `br` (el adaptador no pisa un valor ya definido). No lo probé en nuestros servicios. Habría que confirmarlo en la versión instalada (`~1.20.0`) y revisar que ninguna integración dependa de la compresión Brotli o de la descompresión automática.

   No protege contra las otras tres vulnerabilidades altas ni contra las medias; solo reduce la superficie de la de Brotli.

Saludos.
