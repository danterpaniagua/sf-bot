# GITIN-1325 — [OPE] Actualización de Jenkins (versión de Java)

**Tags:** SmartLoyalty, Jenkins, SRE, PROD

## Resumen

Actualización de la versión de Java subyacente al controller de Jenkins CI de SF-LOYALTY (`SFCG-JENKINS-01`), de Java 17 a Java 21 (Eclipse Temurin), requerida porque el núcleo de Jenkins moderno exige Java 21 como mínimo para arrancar. El trabajo se ejecutó de forma reactiva el 2026-09-23 como parte de la resolución de [GITIN-2099](https://smartit-ar.atlassian.net/browse/GITIN-2099) (bucle de reinicios del servicio Jenkins tras un reinicio rutinario de la VM) — mismo trabajo técnico que este ticket ya scopeaba sin ejecutar. Detalle técnico completo, comandos y verificación en GITIN-2099.

## Tabla resumen

| Campo | Valor |
|---|---|
| Ticket Jira | GITIN-1325 |
| Sistema | Jenkins CI — SFCG-JENKINS-01 (SF-LOYALTY) |
| Severidad | N/A — mejora planificada, ejecutada de forma reactiva |
| Detectado | N/A — ticket preexistente, sin descripción ni notas previas |
| Resuelto | 2026-09-23 |
| Responsable | Dante Paniagua (SRE) |
| Relacionado | [GITIN-2099](https://smartit-ar.atlassian.net/browse/GITIN-2099) — incidente que motivó la ejecución real de esta actualización |

## Acciones realizadas

1. **(SRE) Completado.** Instalación de Eclipse Temurin JDK 21.0.12.1 en `SFCG-JENKINS-01` (vía Adoptium API), reemplazando Java 17.
2. **(SRE) Completado.** Repunteo de `jenkins.xml` (configuración de WinSW) al nuevo binario Java 21. Servicio confirmado estable, sin bucle de reinicios.
3. **(SRE) Completado.** Actualización de `JAVA_HOME`/`PATH` a nivel de sistema operativo, propagada mediante reinicio completo de la VM (Windows cachea el entorno al momento del boot; un simple reinicio de servicio no alcanza). Confirmado post-reinicio: `java -version` → `21.0.12.1`.
4. **(SRE) Completado.** Corrección de la regla de Windows Firewall para el puerto 8443, que había quedado restringida al binario de Java anterior (`jdk-17\java.exe`) y dejó de coincidir tras el cambio — reactivado el acceso externo a la UI sin dejar el firewall deshabilitado como solución temporal.
5. **(SRE) Completado.** Corrección del `java` default del sistema en `sfcg-sonarqube` (agente Jenkins compartido `sonarqube-srv`, usado también por SF-PEDIDOS), que había derivado a Java 17 y perdió compatibilidad de Remoting con el controller ya en Java 21. Verificado explícitamente sin impacto en el servicio de SonarQube (pineado de forma independiente vía `SONAR_JAVA_PATH`).
6. **(SRE) Completado.** Documentación de infraestructura actualizada: `loyalty/docs/infrastructure.md` (entrada `SFCG-JENKINS-01`), `operations/docs/sonarqube_upgrade_runbook.md` §7bis.
7. **(SRE) Pendiente, no bloqueante.** Determinar por qué el núcleo de Jenkins en `SFCG-JENKINS-01` ya exigía Java 21+ antes de esta sesión — si hubo una actualización previa del core/plugins no documentada, o si el servidor fue provisionado así originalmente. No bloquea el cierre de este ticket.

## Recursos afectados

| Recurso | Detalle |
|---|---|
| VM Jenkins controller | `SFCG-JENKINS-01`, resource group `DefaultGroup01`, subscription Smart IT - Grido |
| Servicio Windows | `Jenkins` (WinSW), `D:\Program Files\Jenkins\jenkins.xml` |
| Regla de firewall | `Jenkins` (inbound, puerto 8443) |
| Agente Jenkins compartido | `sonarqube-srv` (host `sfcg-sonarqube`, `DefaultGroup01`) |

## Comandos ejecutados

Mismo trabajo técnico documentado en GITIN-2099 — ver `events/20260923_gitin2099-jenkins-service-crash-loop/scripts.sh` para el listado completo de comandos y su salida capturada. No se duplican aquí para evitar dos copias divergentes del mismo registro.
