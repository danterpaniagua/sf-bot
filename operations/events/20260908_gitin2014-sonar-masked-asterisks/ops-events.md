# Eventos — 20260908_gitin2014-sonar-masked-asterisks

## 2026-09-08 17:00 — Apertura de investigación

He abierto la investigación para GITIN-2014 sobre el contenido enmascarado con asteriscos en SonarQube, para dos archivos de `concentrador-service` (`development.js`, `branch.js`). He descartado primero un problema de renderizado por tamaño de archivo en `branch.js` (6.256 líneas) al confirmar, más adelante, que la API cruda también devuelve el contenido enmascarado.

## 2026-09-08 17:15 — Confirmación de versión y hostname reales

He confirmado, vía `api/system/info`, que la instancia corre SonarQube 26.9.0.129388, actualizada el 2026-09-05. He detectado que el hostname real configurado (`sonar.core.serverBaseURL`) es `sfcg-sonarqube.smartfran.com`, distinto del que documenta el runbook de operaciones (`sf-sonarqube.smartfran.com`) — esto había causado un `HTTP_STATUS:000` real durante los primeros intentos de esta investigación.

## 2026-09-08 17:30 — Descarte de causas alternativas

He descartado, en orden: un token de tipo incorrecto (Global/Analysis Token devuelve 403, resuelto generando un User Token), un enmascarado global al proyecto (`country.js` devolvió código real sin enmascarar), un Security Hotspot (`api/hotspots/search` sin resultados para `branch.js`), un Issue de tipo Vulnerability (`api/issues/search?types=VULNERABILITY` sin resultados), y un filtro a nivel de proxy (la config de nginx es un reverse proxy simple, sin `sub_filter` ni WAF).

## 2026-09-08 17:45 — Causa raíz confirmada

He confirmado, contra las release notes oficiales de SonarSource, que la versión 26.9.0.129388 introdujo el enmascarado de valores de secretos detectados en las respuestas de la Web API — reemplaza el rango detectado por asteriscos, y cuando no puede determinar una ubicación segura, enmascara la línea completa o el archivo entero. No es un bug. He verificado que `development.js` ya tiene una explicación completa: contiene credenciales reales ya documentadas en `20260720_credenciales-mongodb-hardcodeadas`. El literal puntual que dispara el enmascarado en `branch.js` queda sin identificar.

## 2026-09-08 18:00 — Redacción del ticket

He redactado `ops.md` con la causa raíz confirmada, los hallazgos descartados en el proceso, y las acciones pendientes: identificar el secreto puntual en `branch.js`, y corregir el hostname desactualizado en la documentación.

## 2026-09-08 18:15 — Prueba: desactivación global de detección de secretos

He desactivado `sonar.text.activate` (global, vía GUI en Administration → General Settings → Languages → Secrets) como prueba deliberada de la causa raíz confirmada — no como corrección permanente. He dejado pendiente disparar un análisis nuevo de `concentrador-service`, ya que el cambio de configuración por sí solo no afecta resultados ya persistidos de análisis anteriores. He dejado preparado el comando de reversión para ejecutar apenas termine la prueba.

## 2026-09-08 18:30 — Primer intento de prueba: el cambio nunca se guardó

He detectado que el primer intento de la prueba no fue válido: el toggle de la GUI se había marcado pero nunca se guardó, así que la detección de secretos siguió activa durante ese análisis. El resultado de "sigue enmascarado" de ese intento no era evidencia contra la hipótesis — simplemente la prueba nunca se ejecutó.

## 2026-09-08 18:45 — Prueba real: desactivación confirmada, re-análisis, resultado negativo

He confirmado, vía `HTTP_STATUS:204` sobre `api/settings/set`, que `sonar.text.activate` quedó realmente en `false` a nivel global. Tras un nuevo análisis de `concentrador-service`, he verificado `development.js` vía `api/sources/raw` — siguió devolviendo contenido enmascarado (`HTTP_STATUS:200`, mismo patrón de asteriscos). He concluido que `sonar.text.activate` no controla este enmascarado de una forma que un re-análisis revierta, retractando la hipótesis anterior de que desactivar la detección resolvería el problema. He dejado como hipótesis principal, sin confirmar, que el análisis incremental de SonarQube podría no reprocesar el blob de código fuente de un archivo sin cambios de contenido, dejando la versión enmascarada ya persistida desde el análisis original.

## 2026-09-08 19:00 — Reversión confirmada y cierre

He confirmado, vía `HTTP_STATUS:204` sobre `api/settings/reset`, que `sonar.text.activate` volvió a su valor por defecto (detección de secretos activa) a nivel global — sin dejar la detección desactivada sin beneficio demostrado. He cerrado el ticket con la causa raíz de fondo confirmada y documentada (funcionalidad nueva de la versión 26.9.0.129388), dejando como pendientes no bloqueantes: identificar el secreto puntual en `branch.js`, corregir el hostname desactualizado en la documentación, y — opcionalmente — entender por qué un re-análisis no revierte el enmascarado.

## 2026-09-08 19:15 — Secreto puntual de `branch.js` identificado

He localizado el literal que dispara el enmascarado de `branch.js`: un par de credenciales Basic Auth hardcodeadas en las líneas 3755 y 3776 (duplicado en el bloque de log de error de la misma llamada), usadas para autenticar contra la integración de la plataforma de delivery "Toque". No he encontrado este hallazgo vía Hotspots ni Issues de tipo Vulnerability — lo he confirmado leyendo directamente el código fuente del clon local. He actualizado `ops.md` con el hallazgo y una acción nueva para Desarrollo, sin repetir el valor de la credencial en ningún archivo de este repositorio.

## 2026-09-09 09:00 — Origen de la credencial de `branch.js` y cierre del ticket

He confirmado, vía `git blame` sobre el clon local, que la línea 3776 (commit `4ba1b3227`, 2026-02-18) es anterior a la línea 3755 (commit `1d2d2546d`, 2026-06-26) — la credencial parece haberse introducido primero en el bloque de log de error y haber reaparecido después en el cuerpo real del pedido. He cerrado el ticket con la causa raíz de fondo y ambos secretos puntuales identificados; dejo como seguimiento no bloqueante sacar la credencial de "Toque" del código fuente, corregir el hostname desactualizado en la documentación, y entender por qué un re-análisis no revierte el enmascarado.
