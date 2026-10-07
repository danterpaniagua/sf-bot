# Eventos — GITIN-2002

## 2026-09-08 10:07 — Apertura del ticket

He abierto el ticket como par de GITIN-2000, tras recibir el reporte de Trivy de `platforms-service` (`data/trivy_scan.zip`, `data/trivy_vuln.json`). He confirmado que los hallazgos son idénticos en sustancia a los de GITIN-2000: `tar` en `6.2.1` con 9 CVEs (1 CRITICAL), y `axios` en `0.26.1`/`1.13.6` con CVEs HIGH que requieren hasta `1.16.0`.

## 2026-09-08 10:10 — Confirmación del origen de axios y estructura del override

He verificado en `api/package.json` que `platforms-service` tiene el mismo patrón que concentrador-service: `dependencies.axios: "~1.13.5"` y `@sendgrid/mail: "^7.7.0"`, cuya cadena de dependencias (`@sendgrid/client`) declara `axios: "^0.26.0"` — mismo origen confirmado en GITIN-2000. He confirmado que el override aplicado en la rama `ope` sigue la misma estructura que GITIN-2000, con `tar` fijado inicialmente en `^7.5.21` y luego actualizado a `latest`, consistente con la decisión tomada en GITIN-2000.

## 2026-09-08 10:15 — Hallazgo del cambio de Dockerfile sin evidencia

He detectado un cambio adicional en `api/Dockerfile` en la misma rama (`apk update && apk upgrade` antes de instalar `ca-certificates`), sin respaldo en el reporte de Trivy disponible — ninguno de los dos reportes incluye un target de paquetes del sistema operativo. Recomiendo excluir este cambio del alcance de este ticket y tratarlo por separado si se decide perseguir endurecimiento a nivel de OS.

## 2026-09-08 10:20 — Registro de la jerarquía de tickets

He registrado que GITIN-2000 y GITIN-2002 son subtareas de GITIN-1306, junto a GITIN-1858, GITIN-1859 y GITIN-1957.

## 2026-09-08 14:25 — Análisis del reporte de Trivy actualizado (rama ope)

He confirmado, con un nuevo scan de Trivy sobre la rama `ope` (14:21), que el override de `axios` funciona como esperaba: solo queda reportada la versión `1.13.6`, la duplicada `0.26.1` desapareció. He encontrado, además de `tar` con sus 9 CVEs originales, nuevos hallazgos en `brace-expansion`, `cross-spawn`, `glob`, `ip-address`, `minimatch`, `pacote` y `sigstore`, y he verificado vía el campo `PkgPath` que todos viven en `/usr/local/lib/node_modules/npm/node_modules/...` — la instalación interna de npm empaquetada en la imagen base, no el árbol de dependencias de la aplicación (mismo mecanismo confirmado en GITIN-2000). También he encontrado, propios de este servicio y ausentes en GITIN-2000, hallazgos en `express-jwt@5.3.3`, `jsonwebtoken@8.5.1` y `lodash.set@4.3.2` — he verificado en `api/package.json` que concentrador-service ya declara esas dos primeras librerías en versiones posteriores al fix, por lo que esta diferencia es real, no un artefacto de reportes distintos.

## 2026-09-08 14:35 — Intento de actualizar npm en el Dockerfile

He agregado `RUN npm install -g npm@latest` al Dockerfile, como intento de resolver el `tar`/tooling empaquetado en npm. El build falló con exit code 1 sin diagnóstico útil visible (BuildKit colapsó la salida a una sola línea); he intentado varias formas de exponer el log real de npm (`grep`, `tail`, `--progress=plain`) sin obtener más que la línea de cierre estándar del log de npm. No he identificado la causa raíz del fallo.

## 2026-09-08 15:05 — Evaluación de imagen base como alternativa

He verificado que Node 20.x empaqueta npm `10.8.2` de forma fija en toda la línea LTS (mismo `tar` vulnerable en cualquier tag), que Node 22 mejora parcialmente (`tar ^7.5.11`, insuficiente) y que Node 24 se acerca más (`tar ^7.5.19`, resuelve la CRITICAL pero deja una HIGH abierta). He concluido que ninguna opción resuelve esto con un simple cambio de tag — implicaría un salto de versión mayor de Node. He dejado este hallazgo como riesgo residual documentado, pendiente de decisión final, en vez de continuar con el self-upgrade de npm o una migración de Node.

## 2026-09-08 15:20 — Actualización de ops.md y comunicación consolidada a PM

He actualizado `ops.md` con los hallazgos confirmados de esta sesión, incluyendo los hallazgos propios de este servicio (H5) y la aclaración de que el análisis de impacto de axios 1.16.0 se hizo sobre concentrador-service y todavía no se repitió sobre este código. La comunicación a PM quedó consolidada junto con GITIN-2000, en `smartpedidos/events/20260908_gitin2000-axios-tar-upgrade/email_pm.md` y `email_pm_status.md` — no hay copia separada en esta carpeta.
