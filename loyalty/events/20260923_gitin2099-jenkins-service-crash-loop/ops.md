# GITIN-2099 — Jenkins service crash loop en SFCG-JENKINS-01

**Tags:** SmartLoyalty, Jenkins, SRE, PROD

## Resumen

El servicio Jenkins (controller de CI para SF-LOYALTY) en `SFCG-JENKINS-01` quedó caído tras un reinicio rutinario de la VM el 2026-09-23: el wrapper de servicio Windows (WinSW) reinició el proceso Java repetidamente cada 2-4 minutos durante más de 30 minutos sin lograr levantar Jenkins, dejando el servicio de CI de SmartLoyalty completamente inaccesible. Plataforma SmartFran Loyalty, componente Jenkins/CI (`SFCG-JENKINS-01`, `DefaultGroup01`), severidad Alta (CI completamente indisponible).

## Tabla resumen

| Campo | Valor |
|---|---|
| Ticket Jira | GITIN-2099 |
| ID alerta | N/A — reportado manualmente |
| Sistema | Jenkins CI — SFCG-JENKINS-01 (SF-LOYALTY) |
| Severidad | Alta |
| Detectado | 2026-09-23 |
| Resuelto | 2026-09-23 |
| Responsable | Dante Paniagua (SRE) |
| Relacionado | [GITIN-1325](https://smartit-ar.atlassian.net/browse/GITIN-1325) — "[OPE] Actualización de Jenkins" (actualización de versión de Java), resuelto por esta corrección (Java 17 → 21 en `SFCG-JENKINS-01`); ticket propio con las acciones en `events/20260924_gitin1325-jenkins-java-update/ops.md` |

## Causa raíz

El núcleo de Jenkins moderno exige como mínimo Java 21 y aborta el arranque de inmediato si detecta una versión anterior. `SFCG-JENKINS-01` solo tenía Java 17 instalado (`C:\Program Files\Java\jdk-17`), configurado como el `<executable>` del wrapper WinSW (`jenkins.xml`). Cada intento de arranque fallaba el chequeo de versión y terminaba inmediatamente; la política `<onfailure action="restart"/>` (sin backoff configurado) reintentaba el arranque en bucle infinito, generando el ciclo de reinicios observado.

## Hallazgos

| # | Hallazgo | Riesgo |
|---|---|---|
| H1 | Java 17 en `SFCG-JENKINS-01`, por debajo del mínimo requerido por Jenkins (21) — causa raíz del bucle de reinicios | Alto |
| H2 | La regla de Windows Firewall para el puerto 8443 estaba correctamente configurada (Allow/Any/Any) pero además restringida a un `Program` específico (`jdk-17\java.exe`) — dejó de coincidir tras el cambio de JDK, bloqueando el acceso externo a la UI aunque el servicio estuviera sano | Medio |
| H3 | Un cambio de `JAVA_HOME`/`PATH` a nivel de sistema en Windows no se propaga a servicios ya corriendo ni a procesos nuevos hasta un reinicio completo de la VM — Windows cachea el entorno del sistema al momento del boot | Medio |
| H4 | El agente Jenkins compartido `sonarqube-srv` (host `sfcg-sonarqube`, distinto de `SFCG-JENKINS-01`) perdió compatibilidad de Remoting tras la actualización del controller a Java 21 — su propio `java` default del sistema había quedado en Java 17 desde una deriva no investigada posterior a `GITIN-1327` | Medio |

## Recursos afectados

| Recurso | Detalle |
|---|---|
| VM Jenkins controller | `SFCG-JENKINS-01`, resource group `DefaultGroup01`, subscription Smart IT - Grido |
| Servicio Windows | `Jenkins` (WinSW), `D:\Program Files\Jenkins\jenkins.xml` |
| Regla de firewall | `Jenkins` (inbound, puerto 8443) |
| Agente Jenkins compartido | `sonarqube-srv` (host `sfcg-sonarqube`, `DefaultGroup01`) — usado también por SF-PEDIDOS |

## Comandos ejecutados

Ver `scripts.sh` en este evento.

| # | Comando | Propósito |
|---|---|---|
| C1-C3 | Diagnóstico inicial | Confirmar host, estado del servicio, configuración de WinSW y causa raíz vía `jenkins.err.log` |
| D1-D3 | ⚠️ Instalación de JDK 21 y repunteo de `jenkins.xml` | Resolver el bucle de reinicios |
| D4-D5 | ⚠️ Corrección de regla de firewall | Restaurar acceso externo a la UI sin dejar el firewall deshabilitado |
| D6-D7 | ⚠️ Actualización de `PATH`/`JAVA_HOME` + reinicio de VM | Propagar el cambio de JDK a nivel de sistema (requerido por SonarScanner) |
| D8 | Verificación post-reinicio | Confirmar servicio, versión de Java y puerto 8443 |
| D9-D11 | ⚠️ Corrección del `java` default en `sfcg-sonarqube` | Restaurar la conexión Remoting del agente `sonarqube-srv`, verificando cero impacto en SonarQube |

## Acciones propuestas

1. **(SRE)** — Completado. Se instaló Eclipse Temurin JDK 21.0.12.1 en `SFCG-JENKINS-01` y se repunteó `jenkins.xml` al nuevo binario, resolviendo el bucle de reinicios.
2. **(SRE)** — Completado. Se corrigió la regla de Windows Firewall (restringida al binario de Java anterior) y se reactivó el firewall completo, sin dejarlo deshabilitado como solución temporal.
3. **(SRE)** — Completado. Se actualizó `JAVA_HOME`/`PATH` a nivel de sistema y se reinició la VM para propagar el cambio, verificado post-reinicio (`java -version` → 21.0.12.1).
4. **(SRE)** — Completado. Se corrigió el `java` default del sistema en `sfcg-sonarqube` para restaurar la conexión del agente `sonarqube-srv`, verificando explícitamente que el servicio de SonarQube (pineado de forma independiente vía `SONAR_JAVA_PATH`) no sufrió ningún impacto.
5. **(SRE)** — Completado. Se actualizó la documentación de infraestructura (`loyalty/docs/infrastructure.md`) y el runbook de SonarQube (`operations/docs/sonarqube_upgrade_runbook.md`) con el detalle completo de esta incidencia.
6. **(SRE)** — Pendiente. Investigar la causa de la deriva del `java` default en `sfcg-sonarqube` (quedó en Java 17 en algún momento posterior a `GITIN-1327`, sin causa confirmada).

## Hallazgos secundarios

| # | Hallazgo | Detalle |
|---|---|---|
| S1 | Bug real en los 23 jenkinsfiles de SF-LOYALTY | El bloque `post { failure { ... } }` de notificación a Google Chat referenciaba `LOCAL_GIT_COMMIT_MESSAGE`, una variable que solo se definía en el bloque `success` (mutuamente excluyente con `failure`) — toda notificación de build fallido rompía con `MissingPropertyException` en lugar de notificar. Corregido en los 23 archivos y publicado en `sf-devops` (`origin/main`). |
| S2 | Bug real en `packProject.ps1` | El chequeo de "ya existe una compilación previa" usaba un wildcard solo contra el `.zip`, asumiendo que el archivo `.build` asociado siempre existe — un build interrumpido entre la creación de ambos archivos (posiblemente por los reinicios de este mismo evento) dejaba un `.zip` huérfano que rompía el build siguiente al intentar leer un `.build` inexistente. Corregido para requerir la existencia de ambos archivos antes de intentar archivar la compilación previa; publicado en `sf-devops`. |
