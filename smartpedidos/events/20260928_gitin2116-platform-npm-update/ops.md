# [SP] Platform: Actualización de Paquetes NPM — GITIN-2116

**Tags:** SmartPedidos, Platform

## Resumen

Actualización de dependencias de `platforms-service` con foco en `axios` y `mongoose`, acompañada de una medición de CVEs (HIGH y CRITICAL) sobre la imagen Docker completa: capa del sistema operativo y paquetes Node. La imagen actual de producción (rama `develop`, Node 20.20) tiene **51 hallazgos**: 4 del sistema operativo, 22 del npm que trae la imagen base, 22 de `axios` (dos copias: `1.13.6` y una copia transitiva `0.26.1` de `@sendgrid/client`) y 3 de otros paquetes (`express-jwt`, `jsonwebtoken`, `lodash.set`).

Con los cambios ya preparados en la rama `ope` (axios `~1.20.0` con `overrides`, npm 11.20.0 fijado en el `Dockerfile` y `apk upgrade`), la imagen baja a **6 hallazgos**, con **0 en el sistema operativo**, tanto con Node 20.20 (Opción 1) como con Node 22.20 (Opción 2), medidos con el mismo método. `mongoose` queda en `7.8.12`, sin CVEs (decisión de mantener la versión 7.8). Los 6 hallazgos restantes no dependen de la versión de Node y se listan en H4 y H5.

Este ticket cubre exclusivamente `platforms-service`. `concentrador-service` y `backOffice` se rastrean por separado bajo el mismo padre.

Durante las pruebas sobre la rama `ope` apareció además un error de registro en Mongo (`Log.save`: `Path message is required`) que **no está causado por estos cambios**: viene de un defecto de código que también está en `develop` (H11). Se incluye en este ticket porque se detectó y corrigió en la rama de pruebas; la corrección todavía no fue probada.

## Tabla resumen

| Campo | Valor |
|---|---|
| Ticket Jira | [GITIN-2116](https://smartit-ar.atlassian.net/browse/GITIN-2116) |
| Ticket padre | [GITIN-2107](https://smartit-ar.atlassian.net/browse/GITIN-2107) — "[SP] Plan actualización SmartPedidos" |
| Tickets hermanos | GITIN-2117 (Concentrador), GITIN-2118 (BBOO) — fuera de alcance de este ticket |
| Sistema | platforms-service (SmartPedidos) — imagen Docker, `package.json`, pipeline de Jenkins |
| Severidad | Alta |
| Detectado | 2026-09-25 |
| Resuelto | Parcial — medición completa; falta decidir la opción de Node, subir `express-jwt`/`jsonwebtoken`/`uuid` y completar las pruebas funcionales (ver Acciones propuestas); corrección de `Log.save` en `ope` pendiente de prueba (H11) |
| Responsable | Dev / SRE |

## Causa raíz

Las dependencias `axios`, `express-jwt` y `jsonwebtoken` quedaron fijadas en versiones desactualizadas en el `package.json` de `platforms-service`, sin proceso periódico de actualización, y la imagen base de Docker no se actualiza por sí sola: el `Dockerfile` de producción no fija npm ni actualiza los paquetes del sistema operativo, por lo que la imagen hereda un npm antiguo con sus propias copias de `tar`, `brace-expansion`, `minimatch` y otras, y los paquetes de Alpine de la fecha en que se construyó la imagen base. Las versiones corregidas de las dependencias directas son compatibles con Node 20, por lo que el origen de los hallazgos no es la versión de Node.

## Hallazgos

| # | Hallazgo | Riesgo |
|---|---|---|
| H1 | **Línea base medida** (imagen de la rama `develop`, commit `ded57a5`, Node 20.20.2, npm 10.8.2, Alpine 3.23.4, construida el 2026-09-30 con la imagen base descargada de nuevo): **51 hallazgos** (1 CRITICAL, 50 HIGH) = 4 del SO (`libcrypto3`/`libssl3`) + 22 del npm de la imagen (`tar` ×9 con 1 CRITICAL, `brace-expansion` ×5, `minimatch` ×3 y otros) + 22 de `axios` + 3 de otros paquetes. | Alto |
| H2 | `axios`: la versión resuelta `1.13.6` tiene 28 CVEs en OSV (10 HIGH, 17 MODERATE, 1 LOW) y 12 hallazgos en Trivy; existe además una **segunda copia, `axios@0.26.1`** (10 hallazgos), que no es dependencia directa: viene de `@sendgrid/mail@7.7.0` → `@sendgrid/client@7.7.0` (declara `axios ^0.26.0`). `axios@1.20.0` no tiene CVEs conocidos, no tiene restricción de Node y es compatible con Node 20. En la rama `ope`, `axios ~1.20.0` más `overrides.axios: "$axios"` deja una sola copia (`1.20.0`) y `axios` desaparece de todos los escaneos. | Alto |
| H3 | Efecto colateral del `overrides`: el cliente de SendGrid (escrito para axios 0.26) pasa a usar axios 1.20.0, un salto de versión mayor cuya compatibilidad **no se probó**. El código solo usa `setApiKey` y `send(...)` (con manejo de errores que registra el cuerpo de la respuesta), en `platforms-service` (`aws.js`, 2 envíos) y en `concentrador-service` (recuperación de contraseña, alta, etc.). `concentrador-service` ya tiene ese `overrides` en su rama `develop` (commit del 2026-09-09; fecha de despliegue no verificada). `@sendgrid/mail` nunca se actualizó en `develop` en ninguno de los dos servicios (`^7.7.0`; última 7.x = 7.7.0; última versión general: 8.1.6). | Medio |
| H4 | **Quedan 3 hallazgos en paquetes de la aplicación**: `express-jwt@5.3.3` (CVE-2020-15084, bypass de autorización, HIGH; corregido en 6.0.0 o posterior; `concentrador-service` ya usa 8.5.1), `jsonwebtoken@8.5.1` (CVE-2022-23539, HIGH; corregido en 9.0.0 o posterior; `concentrador-service` usa 9.0.3) y `lodash.set@4.3.2` (CVE-2020-8203, HIGH, sin versión corregida; paquete padre sin rastrear). `uuid@8.0.0` tiene además 1 CVE MODERATE según OSV, que no aparece en Trivy porque los escaneos filtran HIGH y CRITICAL. | Alto |
| H5 | **Quedan 3 hallazgos dentro del propio npm 11.20.0**: `brace-expansion@5.0.9` (×2) y `undici@6.28.0`. No se corrigen desde `package.json`; no se verificó si una versión de npm posterior a 11.20.0 los corrige. | Medio |
| H6 | **npm de la imagen:** `tar@6.2.1` (CRITICAL, CVE-2026-59873) y `tar@7.4.3` están dentro del npm empaquetado en la imagen base (`/usr/local/lib/node_modules/npm/...`), no en `package.json`; `overrides.tar: "latest"` no tiene efecto sobre ellos (no hay `tar` en el árbol de la aplicación). Medido sobre la imagen base de Node 20.20 sin tocar: 22 hallazgos de paquetes Node, todos dentro de npm 10.8.2. Fijar `npm@11.20.0` en el `Dockerfile` los reduce a 3 (H5). `npm@latest` (12.x) requiere Node `^22.22.2` y no corre sobre Node 22.20 ni 20.20. | Alto |
| H7 | **Sistema operativo:** `apk upgrade` elimina los hallazgos del SO: de 4 a 0 con Node 20.20 y de 21 (2 CRITICAL) a 0 con Node 22.20. Se reproduce en Jenkins: el reporte de las 13:51 UTC del 2026-09-30 mostraba 4 hallazgos del SO y el de las 18:07 UTC mostró 0, con los 6 hallazgos de paquetes sin cambios. Los reportes de Jenkins no incluían el sistema operativo hasta que se cambió `--vuln-type library` por `--vuln-type os,library` en las definiciones de los pipelines `ope` y `develop` de Platform y Concentrador. | Alto |
| H8 | **Node 22.20:** la etiqueta `node:22.20-alpine` se creó el 2025-09-24 y no se reconstruyó (Alpine 3.22.2): la aplicación de `develop` sobre esa imagen, sin los cambios, tiene **87 hallazgos** (la imagen base cruda, 62) contra los 51 de Node 20.20 (cuya etiqueta se reconstruyó el 2026-04-15, Alpine 3.23.4). Con los cambios aplicados ambas opciones quedan en 6. La etiqueta de una versión de Node cambia con el tiempo: un build sin descargar la imagen base reutiliza la copia local del servidor; no se verificó qué copia usa Jenkins. | Medio |
| H9 | **`mongoose`:** `7.8.12` (`~7.8.7`) no tiene CVEs conocidos; se mantiene la versión 7.8 por decisión. La última versión (9.10.2) corre sobre Node 20.20, pero `mongoose-unique-validator` (23 archivos del servicio lo usan como plugin) exige Node 22 o superior desde su versión 6.x; con Node 20 el conjunto consistente más nuevo es `mongoose` 8.24.4 con `mongoose-unique-validator` 5.0.2. No se revisaron cambios incompatibles de 7 a 8 ni a 9. | Informativo |
| H10 | De las 35 dependencias directas, solo 4 quedan por debajo de su propio `latest` global al aplicar el límite de Node 20: `@babel/core`/`@babel/node` (requieren Node 22+ para `8.x`), `mongoose-unique-validator` (Node 22+ para `6.x`) y `sqs-consumer` (un patch por debajo, `15.0.3`→`15.0.0`). El resto puede alcanzar su última versión sin cambio de runtime. | Bajo |
| H11 | **`Log.save` (registro en Mongo) borra `message` y `category` antes de usarlos** (detectado en pruebas sobre `ope` el 2026-10-05). En `api/src/utils/log.js`, línea 54, `customDataAfter` era un alias del mismo objeto que `customData` (`let customDataAfter = customData;`), por lo que los `delete` siguientes también le quitaban `message` y `category` a `customData`; el `create` posterior leía `message` indefinido y el modelo (`message` requerido) lo rechazaba (`ValidationError: Path message is required`); el `create` de respaldo del `catch` interno fallaba igual y el `catch` externo dejaba solo un documento `FATAL` `[INFRA/ERROR] Log.save failed`. El alias se introdujo en el commit `b5f1053` (2026-09-21) y está también en `develop`. Solo se manifiesta con `mongoLogEnabled` activo (flag que se lee de la base de datos; por defecto es `false` en el código; no se verificó su valor en producción). Antes de las correcciones, `develop` y `ope` diferían solo en `Dockerfile` y `package.json`: el error no lo causan los cambios de este ticket. En `ope`: el commit `765b5b4` (2026-10-05) agregó valores de respaldo para `message` (el error desaparecía, pero se guardaba `error.message` o `Unknown error N` en lugar del mensaje real y sin `category`), y el commit `84c7efd` (2026-10-05) reemplazó el alias por `structuredClone(customData)`, que conserva ambos campos. **Ninguna de las dos correcciones fue probada todavía.** `structuredClone` lanza `DataCloneError` ante valores no clonables (funciones, algunos objetos nativos); en ese caso el registro se perdería con el documento `FATAL`. La búsqueda en el código no encontró llamadas que pasen funciones ni `null` en `customData` (revisión no exhaustiva). | Medio |

### Comparación: imagen actual contra las dos opciones

Mismo método en todas las columnas: imagen base descargada de nuevo, build con `--no-cache`, Trivy con `--scanners vuln --pkg-types os,library --severity HIGH,CRITICAL`. Opción 1 y Opción 2: rama `ope` (commit `b8d57be`) con las dos capas del `Dockerfile` (npm por un lado y `apk upgrade && apk add ca-certificates` por otro) y solo el `FROM` distinto.

| | Actual (`develop`, Node 20.20) | Opción 1 (Node 20.20 + cambios) | Opción 2 (Node 22.20 + cambios) |
|---|---|---|---|
| npm | 10.8.2 | 11.20.0 (fijado) | 11.20.0 (fijado) |
| `apk upgrade` | no | sí | sí |
| Alpine | 3.23.4 | 3.23.4 → 3.23.6 | 3.22.2 → 3.22.6 |
| axios | 1.13.6 + 0.26.1 | 1.20.0 | 1.20.0 |
| mongoose | 7.8.12 | 7.8.12 | 7.8.12 |
| Hallazgos SO | 4 | 0 | 0 |
| Hallazgos npm de la imagen | 22 | 3 | 3 |
| Hallazgos axios | 22 | 0 | 0 |
| Otros paquetes | 3 | 3 | 3 |
| **Total** | **51** | **6** | **6** |

Ningún CVE cambia entre la Opción 1 y la 2. La Opción 2 es un salto mayor de Node (20 a 22) que exige verificaciones adicionales (ver Acciones propuestas) y cumple además el requisito de Node 22 o superior del AWS SDK a partir de enero de 2027; ese plazo no es un CVE y queda fuera del alcance de este ticket. Para Node 22.20 no se midió el escalón intermedio "solo npm fijado" (sí la base cruda y el resultado final).

### Tabla de compatibilidad Node 20 y CVEs — `platforms-service`

Columnas: `Current` = versión instalada resuelta desde `package.json` (las versiones de `axios`, `mongoose`, `mongoose-unique-validator`, `uuid`, `express-jwt`, `jsonwebtoken` y `@sendgrid/*` coinciden con las instaladas en la imagen según el inventario de paquetes de Trivy); `CVE (Current)` = CVEs conocidos en esa versión (OSV.dev); `Compat` = versión máxima compatible con Node 20; `CVE (Compat)` = CVEs conocidos en esa versión; `Global` = última versión publicada (sin restricción de Node).

| Paquete | Current | CVE (Current) | Compat (Node 20) | CVE (Compat) | Global |
|---|---|---|---|---|---|
| `axios` | 1.13.6 | **28** | 1.20.0 | 0 | 1.20.0 |
| `jsonwebtoken` | 8.5.1 | **3 (1 HIGH)** | 9.0.3 | 0 | 9.0.3 |
| `express-jwt` | 5.3.3 | **1 (HIGH)** | 8.5.1 | 0 | 8.5.1 |
| `uuid` | 8.0.0 | **1 (MODERATE)** | 14.0.2 | 0 | 14.0.2 |
| `@aws-sdk/client-sqs` | 3.1140.0 | 0 | 3.1140.0 | 0 | 3.1140.0 |
| `@aws-sdk/client-ssm` | 3.1140.0 | 0 | 3.1140.0 | 0 | 3.1140.0 |
| `@babel/core` | 7.29.7 | 0 | 7.29.7 | 0 | 8.0.6 |
| `@babel/node` | 7.29.7 | 0 | 7.29.7 | 0 | 8.0.6 |
| `@babel/runtime` | 7.29.7 | 0 | 8.0.5 | 0 | 8.0.5 |
| `@meanie/mongoose-to-json` | 2.6.0 | 0 | 2.6.0 | 0 | 2.6.0 |
| `@sendgrid/mail` | 7.7.0 | 0 | 8.1.6 | 0 | 8.1.6 |
| `@types/form-data` | 2.5.2 | 0 | 2.5.2 | 0 | 2.5.2 |
| `body-parser` | 1.20.8 | 0 | 2.3.0 | 0 | 2.3.0 |
| `cookie-parser` | 1.4.7 | 0 | 1.4.7 | 0 | 1.4.7 |
| `core-js` | 3.50.0 | 0 | 3.50.0 | 0 | 3.50.0 |
| `cors` | 2.8.6 | 0 | 2.8.6 | 0 | 2.8.6 |
| `cross-env` | 7.0.3 | 0 | 10.1.0 | 0 | 10.1.0 |
| `env-var` | 7.5.0 | 0 | 7.5.0 | 0 | 7.5.0 |
| `express` | 4.22.3 | 0 | 5.2.1 | 0 | 5.2.1 |
| `form-data` | 4.0.6 | 0 | 4.0.6 | 0 | 4.0.6 |
| `lodash` | 4.18.1 | 0 | 4.18.1 | 0 | 4.18.1 |
| `moment` | 2.31.0 | 0 | 2.31.0 | 0 | 2.31.0 |
| `mongoose` | 7.8.12 | 0 | 9.10.2 | 0 | 9.10.2 |
| `mongoose-unique-validator` | 4.0.1 | 0 | 5.0.2 | 0 | 6.1.1 |
| `morgan` | 1.12.1 | 0 | 1.12.1 | 0 | 1.12.1 |
| `node-schedule` | 2.1.1 | 0 | 2.1.1 | 0 | 2.1.1 |
| `nodemon` | 1.19.4 | 0 | 3.1.14 | 0 | 3.1.14 |
| `regenerator-runtime` | 0.13.11 | 0 | 0.14.1 | 0 | 0.14.1 |
| `sqs-consumer` | 11.6.0 | 0 | 15.0.0 | 0 | 15.0.3 |
| `swagger-jsdoc` | 6.3.0 | 0 | 6.3.0 | 0 | 6.3.0 |
| `swagger-ui-express` | 5.0.1 | 0 | 5.0.1 | 0 | 5.0.1 |
| `winston` | 3.2.1 | 0 | 3.19.0 | 0 | 3.19.0 |
| `winston-mongodb` | 5.0.0 | 0 | 7.0.1 | 0 | 7.0.1 |

(`crypto-js` y `node-cron` son dependencias directas solo de `concentrador-service`; la tabla combinada de ambos servicios está en `data/dependency_cve_table_node20_20260925.md`. `@babel/core`, `@babel/node`, `cross-env` y `nodemon` figuran en `dependencies` pero no están instalados en la imagen de producción, que instala solo las dependencias de producción.)

## Recursos afectados

| Componente | Participación |
|---|---|
| platforms-service (`package.json`) | `axios`, `express-jwt`, `jsonwebtoken`, `uuid` (H2, H4), `@sendgrid/mail` (H3), `mongoose` sin cambios (H9) |
| platforms-service (imagen Docker) | npm interno de la imagen base y paquetes del SO (H1, H6, H7); versión de Node (H8) |
| Pipelines de Jenkins de Platform y Concentrador (`ope` y `develop`) | Escaneo Trivy ampliado a la capa del SO (H7) |
| concentrador-service | Mismo `@sendgrid/mail` y mismo `overrides` en `develop` (H3); fuera de alcance, ver GITIN-2117 |
| platforms-service (código, `api/src/utils/log.js`) | Registro en Mongo con `mongoLogEnabled` activo (H11); corrección en `ope`, defecto también presente en `develop` |

## Comandos ejecutados

| # | Comando / Script | Propósito |
|---|---|---|
| C1 | `scripts.sh` | Descarga de los packuments completos desde `registry.npmjs.org` |
| C2 | `scripts_osv.sh` / `scripts_osv_current.sh` | Consulta OSV.dev para la versión límite (`Compat`) y la instalada (`Current`) de cada paquete |
| C3 | Trivy local sobre la imagen `ope` (29 y 30 de septiembre) | Ubicar `tar` dentro del npm de la imagen (H6) y el inventario de paquetes instalados |
| C4 | Pares de builds antes/después de `apk upgrade`, Node 20.20 y 22.20 | Efecto sobre el SO (H7) |
| C5 | Escalera sobre `node:20.20-alpine`: base cruda → + npm 11.20.0 → + `apk upgrade` | Efecto de cada cambio por separado (H6, H7) |
| C6 | Build de `origin/develop` sin cambios y escaneo | Línea base medida: 51 hallazgos (H1) |
| C7 | `scripts_n20_opt1.sh` y `scripts_trivy_n22.sh` | Medición de la Opción 1 y de la Opción 2 con el mismo método |
| C8 | Reportes de Jenkins `ope` del 2026-09-30 (13:51 y 18:07 UTC) | Confirmar en el pipeline real la ampliación al SO y el efecto de `apk upgrade` (H7) |
| C9 | Lectura de código y de historial de `git` de `@sendgrid/mail` en ambos servicios | Cadena de dependencias y uso (H3) |
| C10 | `scripts_sendgrid_client.sh` y `scripts_sendgrid_test.sh` | Preparados, sin resultados todavía (H3, Acciones propuestas) |
| C11 | Lectura de `api/src/utils/log.js`, de su historial en `git` (`ope` y `develop`) y de los llamadores de `Log.save`/`Log.saveError`; documento `FATAL` pegado por el desarrollador | Causa y origen del error de `Log.save` (H11) |

Salida completa de cada paso en la carpeta `data/` del evento.

## Acciones propuestas

1. (Dev) Actualizar `express-jwt` a una versión corregida (`^8.5.1`, la que ya usa `concentrador-service`) y `jsonwebtoken` a `^9.0.3`, tras revisar cómo se usan en `platforms-service`; son saltos de versión mayor.
2. (Dev) Actualizar `uuid` (1 CVE MODERATE) y rastrear qué paquete trae `lodash.set@4.3.2`, que no tiene versión corregida.
3. (SRE/Dev) Decidir entre la Opción 1 (Node 20.20) y la Opción 2 (Node 22.20). Ambas dejan 6 hallazgos y 0 en el SO. La Opción 2 requiere verificar antes: el controlador de MongoDB de `mongoose` 7.8 (`mongodb 5.9.2`) y la conexión a Atlas en Node 22, las dependencias antiguas (`nodemon`, `node-cron`, `winston 3.2.1`, `@babel/node`), el comportamiento del runtime (TLS y certificados con `NODE_EXTRA_CA_CERTS`), pruebas funcionales completas en staging, y si existen versiones menores más nuevas de Node 22 con imagen base reconstruida.
4. (Dev) Antes de mergear el cambio de `axios`: probar el login OAuth de UberEats (único uso de `multipart`/`FormData`), el envío de correos con SendGrid en ambos servicios (los scripts de prueba con modo sandbox están preparados) y, en `concentrador-service`, que el interceptor de `httpClient` siga registrando las duraciones (GITIN-2117). Confirmar además en qué rama quedan estos cambios (se revisó `ope`; `develop` aún tiene `axios ~1.13.5` sin `overrides` en Platform).
5. (SRE) Dejar en el `Dockerfile` de la rama que se despliega las dos capas probadas (`npm install -g npm@11.20.0` y `apk upgrade --no-cache && apk add --no-cache ca-certificates`, en el stage final) y confirmar con el próximo reporte de Jenkins que el SO sigue en 0. El `apk upgrade` en una capa cacheada no se re-ejecuta mientras no cambie la imagen base ni el texto del comando: valorar `--pull` o `--no-cache` en el build de Jenkins; confirmar qué copia de la imagen base usa hoy el servidor de build.
6. (SRE) Evaluar si una versión de npm posterior a 11.20.0 corrige `brace-expansion` y `undici` (H5); si se sube npm más allá de la serie 11.x, subir Node a 22.22.2 o superior en el mismo cambio.
7. (Dev) Opcional: `mongoose` queda en 7.8; una subida a 8.x implicaría `mongoose-unique-validator` 5.0.2 y revisar cambios incompatibles en los 31 archivos que usan `mongoose`, y a 9.x exigiría Node 22 y reemplazar o actualizar el plugin.
8. (Dev) Probar la corrección de `Log.save` ya presente en `ope` (commit `84c7efd`): con el registro en Mongo activo, ejecutar `Log.saveError(new Error('boom'), { message: '[TEST/ERROR] marker', category: 'INFRA' })` y comprobar que el último documento de `logerrors` tenga `message` igual a `[TEST/ERROR] marker` y `category` igual a `INFRA`; además, que no aparezcan documentos nuevos `[INFRA/ERROR] Log.save failed` ni `unexpected_error in Log.save` después de la corrección. Evaluar si `{ ...customData }` es preferible a `structuredClone` (copia superficial: no lanza ante valores no clonables). Como `develop` tiene el mismo defecto, llevar la corrección a `develop` por el proceso habitual del repositorio, como cambio aparte de los CVEs.

## Hallazgos secundarios

- Desde el commit `b5f1053` el registro usa `customData` sin sanear los headers (`SanitizeHeaders` y `SENSITIVE_HEADERS` siguen declarados pero ya no se aplican en `log.js`), y el manejador de errores de autenticación (`app.js`) incluye el token Bearer en el objeto de log (`authContext.token`). No se verificó qué se registra en la práctica; conviene revisarlo como cambio aparte.
