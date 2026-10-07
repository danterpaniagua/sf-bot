## Resumen

Un scan de Trivy sobre la imagen `dev-src-pedidos-concentrador:develop` (2026-09-08) detectó vulnerabilidades en las dependencias `tar` y `axios` de `concentrador-service`. Se propuso agregar un bloque `overrides` en `api/package.json` para fijar `tar` en `^7.5.21` y forzar la resolución transitiva de `axios` al valor top-level (`~1.13.5`) vía `"axios": "$axios"`. Este cambio resuelve por completo las vulnerabilidades de `tar`, pero solo resuelve parcialmente las de `axios`. Se realizó además un análisis de impacto de una eventual actualización completa de `dependencies.axios` a `1.16.0`, revisando el código fuente real.

## Tabla resumen

| Campo | Valor |
|---|---|
| Ticket Jira | GITIN-2000 |
| Componente | concentrador-service |
| Severidad | Alta (1 CVE CRITICAL en tar, múltiples HIGH en tar/axios) |
| Detectado | 2026-09-08 (Trivy scan) |
| Resuelto | Parcial — ver Acciones propuestas |
| Responsable | SRE |

## Origen

Trivy scan sobre `dev-src-pedidos-concentrador:develop`, generado 2026-09-08. Reporte completo persistido en `data/trivy_scan.zip` / `data/trivy_vuln.json`.

## Hallazgos

| # | Hallazgo | Riesgo |
|---|---|---|
| H1 | `tar` instalado en `6.2.1` (transitiva a la app), 9 CVEs (1 CRITICAL — DoS por gzip bomb; 8 HIGH — path traversal / escritura arbitraria de archivos / DoS). Fix máximo requerido: `7.5.21`. El override aplicado (`tar: "latest"`, dist-tag en lugar de versión fijada, para no requerir un nuevo ticket por cada CVE futura) resuelve por completo el uso de `tar` en el árbol de dependencias **de la propia aplicación**. `tar` no se importa directamente en `api/src` — es una dependencia transitiva pura (probablemente de una herramienta de build/test), por lo que el riesgo residual de un futuro salto de versión major recae en esas herramientas, no en el código propio. | Alto (resuelto, alcance app) |
| H2 | `axios` instalado en dos versiones distintas: `0.26.1` (transitiva, vía `@sendgrid/client@^7.7.0`, que declara `axios: ^0.26.0`) y `1.13.6` (vía el rango directo `~1.13.5`). Cada una con ~10 CVEs HIGH propios. **Confirmado por un scan posterior (2026-09-08 14:53, `data/trivy_vuln_ope_20260908_1453.txt`)**: el override (`axios: "$axios"`) funciona como se esperaba — solo queda reportada la versión `1.13.6`, la duplicada `0.26.1` desapareció. | Alto (parcialmente resuelto) |
| H3 | El override de `axios` solo fuerza la resolución de `@sendgrid/client` a coincidir con el valor top-level (`~1.13.5`) — no eleva ese techo. Las CVEs que requieren `1.15.1`–`1.16.0` (fuga de credenciales de proxy, DoS por límites de tamaño no aplicados, MITM por contaminación de prototipo, DoS en cookie XSRF) quedan sin resolver tras este cambio. | Medio — pendiente de decisión |
| H4 | Análisis de impacto de elevar `dependencies.axios` a `1.16.0` (ver `data/axios-1160-impact-analysis.md`): ningún paquete del árbol de dependencias distinto de `@sendgrid/client` depende de `axios` — se verificó explícitamente que `mongoose` y todo su subárbol no lo referencian, descartando una suposición inicial de que `mongoose` fijaba esa versión. Se revisaron ~85 call sites de uso real en `branch.js` (integraciones Rappi, Uber Eats, PediGrido, PedidosYa, SmartLoyalty) contra los cambios de comportamiento documentados por axios entre `1.14.0` y `1.16.0`: ninguno aplica a los patrones de uso actuales (no hay proxy configurado, no hay URLs con credenciales embebidas, no se usa el adaptador fetch, los headers solo contienen tokens Bearer opacos o strings estáticos). **Conclusión: la actualización de axios a `1.16.0` es técnicamente viable sin incompatibilidades conocidas, pero debe pasar por una revisión de impacto de código antes de aplicarse** — el análisis descarta incompatibilidades conocidas por patrón de uso, no reemplaza una revisión/testing real del cambio. | Bajo |
| H5 | **Confirmado por el scan posterior (2026-09-08 14:53)**: además de `tar`, aparecen `brace-expansion`, `cross-spawn`, `glob`, `ip-address`, `minimatch`, `pacote` y `sigstore` con CVEs HIGH. Verificado vía el campo `PkgPath` del reporte JSON (mismo mecanismo confirmado en GITIN-2002): **todos** viven en `/usr/local/lib/node_modules/npm/node_modules/...` — son parte de la instalación interna de **npm mismo**, empaquetada en la imagen base `node:20.20-alpine`, no del árbol de dependencias de la aplicación. El `overrides` de `package.json` no tiene alcance ahí. Se investigó actualizar la imagen base (Node 22/24 traen versiones de npm con `tar` más nuevo, pero ninguna cierra el `tar` por completo, y es un salto de versión mayor de Node, no un simple cambio de tag) y actualizar npm dentro del Dockerfile (`npm install -g npm@latest`), que actualmente falla en build sin diagnóstico claro aún. Dado que el `ENTRYPOINT`/`CMD` de producción (`npm run serve`) no ejercita el código de `tar` en operación normal, se evalúa documentar esto como riesgo residual aceptado en lugar de perseguir una migración mayor de Node. | Medio — decisión pendiente |

## Recursos afectados

| Componente | Impacto |
|---|---|
| concentrador-service | `api/package.json` — override de `tar`/`axios` propuesto; upgrade completo de `axios` pendiente de decisión |
| platforms-service | No evaluado — el scan de Trivy solo cubrió `dev-src-pedidos-concentrador:develop` |

## Comandos ejecutados

| # | Comando / Script | Propósito |
|---|---|---|
| C1 | Verificación de árbol de dependencias (registro npm) + inventario de call sites (`grep` sobre `api/src`) + revisión del changelog de axios 1.14.0→1.16.0 | Determinar el radio de impacto de elevar `dependencies.axios` a `1.16.0` |

Salida completa persistida en `data/axios-1160-impact-analysis.md`.

## Acciones propuestas

1. Aplicar el override de `axios` (`"$axios"`) y cambiar el de `tar` de `^7.5.21` a `latest`, para que futuros CVEs de `tar` no requieran un nuevo ticket de pin (Dev).
2. Decidir si el upgrade de `dependencies.axios` a `1.16.0` (o superior) se trata como parte de este mismo ticket o como uno de seguimiento — el análisis de impacto (H4) no encontró incompatibilidades conocidas, solo superficie de prueba a cubrir (Dev/SRE).
3. Si se decide postergar el upgrade completo de axios, dejar registrado que las CVEs que requieren `1.15.1`–`1.16.0` quedan abiertas tras el cierre de este ticket (SRE).

## Hallazgos secundarios

Ninguno.
