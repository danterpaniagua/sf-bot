# Actualización de SonarQube (GITIN-1327)

Jira: https://smartit-ar.atlassian.net/browse/GITIN-1327

## Resumen

Actualización de la instancia SonarQube Community Edition 9.9.3 en `sfcg-sonarqube` hacia la ruta de actualización oficial de Community Build (9.9.3 → 24.12.0.100206 → 26.1.0.118079 → 26.9.0.129388), junto con la actualización del sistema operativo del host (Ubuntu 20.04 → 22.04, requerida porque el repositorio oficial PGDG dejó de servir paquetes de PostgreSQL 15+ para Ubuntu 20.04). **Completado — SonarQube corriendo en la versión final objetivo (26.9.0.129388), verificado saludable.** Quedan únicamente tareas de housekeeping sin urgencia (ver Acciones propuestas).

**Decisión de alcance:** el salto a Ubuntu 24.04 se descarta para este ticket. PGDG soporta PostgreSQL 15/16/17 en Ubuntu 22.04 sin fecha de corte hasta bien entrado 2029, y JDK 21 está disponible limpiamente en 22.04 vía el repositorio de Adoptium — ambos bloqueantes que motivaron la actualización de SO ya están resueltos en 22.04, sin necesidad de llegar a 24.04. Avanzar a 24.04 además introduciría un problema real sin solución limpia: `get-fq.py` (ver más abajo) depende de Python 3.10, que en 24.04 solo está disponible vía el canal nightly/inestable de `deadsnakes` (no apto para un pipeline de datos de producción). El salto a 24.04 queda como una iniciativa separada y futura, a abordar solo después de desacoplar `get-fq.py` de la versión de Python del sistema operativo (por ejemplo, containerizándolo — Docker ya está instalado en este host).

## Tabla resumen

| Campo | Valor |
|---|---|
| Host | `sfcg-sonarqube` (Azure VM, suscripción Smart IT - Grido `0190fa7d-4ccf-4e3d-beb1-323b5780bfc8`, resource group `DEFAULTGROUP01`) |
| Estado SonarQube | 26.9.0.129388 (Community Build, versión final objetivo), `UP`, en operación normal |
| Estado SO | Ubuntu 22.04.5 LTS (jammy), kernel `6.8.0-1065-azure` |
| Java | JDK 21 (Temurin) |
| PostgreSQL | 15.19 |
| Responsable | Dante Paniagua |
| Estado del ticket | Completado — quedan solo tareas de housekeeping sin urgencia |

## Fixes aplicados hasta ahora

1. ✅ **SonarQube 9.9.3 → 24.12.0.100206**: swap de directorio de instalación (sin symlink previo), migración de base de datos disparada manualmente vía `/setup`/`api/system/migrate_db` (SonarQube no migra automáticamente al arrancar). Verificado saludable: Compute Engine procesando tareas reales contra proyectos de producción, nginx→SonarQube confirmado end-to-end.
2. ✅ **Actualización de sistema operativo 20.04 → 22.04.5 LTS**: `do-release-upgrade` completo tras resolver tres fallas reales de dpkg (dependencia faltante de `dotnet-host-7.0`; conflicto de archivo entre `linux-azure-tools-5.15.0-1050` y el paquete obsoleto `linux-azure-5.15-tools-5.15.0-1050`; y bloqueo de `cron`/`at` por atributos inmutable+append-only preexistentes en `/var/spool/cron`, restaurados correctamente después). Verificado post-reboot: SonarQube, PostgreSQL, nginx y Zabbix Agent 2 saludables, sin pérdida de datos.
3. ✅ **Repositorios de terceros re-apuntados a `jammy`**: los 3 repos de Zabbix (`zabbix.list`, `zabbix-agent2-plugins.list`, `zabbix-tools.list`), Docker CE y Microsoft Azure CLI — todos verificados resolviendo correctamente contra `jammy` vía `apt-get update`. (Trivy no requería cambio — su repo usa un componente `generic`, no un codename de distribución.)
4. ✅ **`get-fq.py`** (script que trae datos de Grido y los almacena en la capa bronze de Fabric, alojado en este mismo host) — corregido tras los cambios de entorno Python de esta actualización; confirmado por el usuario como re-ejecutado y funcionando correctamente.
5. ✅ **Limpieza de `python3.9`/repo `deadsnakes`**: la razón original del repo (proveer Python 3.10 para `get-fq.py`) ya no aplica, dado que Ubuntu 22.04 provee 3.10 nativamente desde sus propios repositorios. `python3.9`/`python3.9-minimal` no tenían ningún consumidor identificado (sin dependientes formales, sin referencias en systemd/cron, sin proceso corriendo) — purgados. Archivo de repo `deadsnakes-ubuntu-ppa-focal.list` eliminado (solo queda el backup `.distUpgrade`, inocuo).
6. ✅ **JDK 21 instalado** (Temurin, repo Adoptium), sin desinstalar Java 17. Se detectó y corrigió un problema real: un intento inicial de fijar la versión de Java de SonarQube vía variable de entorno `JAVA_HOME` en el unit de systemd no funcionó (`sonar.sh` no la respeta, resuelve `java` vía `update-alternatives`) — el fix real fue `update-alternatives --set java` en modo manual, apuntado a Java 17 explícitamente. Confirmado con inspección directa de procesos: SonarQube corre íntegramente sobre Java 17.
7. ✅ **PostgreSQL 13 → 15 migrado** vía `pg_upgradecluster` (herramienta nativa de Debian/Ubuntu para este tipo de upgrade). El nuevo cluster `15/main` quedó directamente en el puerto 5432 (sin necesidad de tocar `sonar.properties`). Cluster `13/main` viejo conservado, detenido, en `/opt/ssd01/postgresql/13/main` (plan de rollback). Verificado con consulta directa: 21 proyectos, 102 tablas migradas correctamente. SonarQube reconectado y confirmado `UP` post-migración.
8. ✅ **Salto SonarQube 24.12.0.100206 → 26.1.0.118079**: mismo patrón de corte (swap de directorios, migración de base de datos manual). Esta vez se fijó la versión de Java correctamente vía `SONAR_JAVA_PATH` (variable propia de esta versión de `sonar.sh`, distinta de `JAVA_HOME`) — confirmado con inspección directa de procesos que corre íntegramente sobre Java 21 (Temurin) desde el primer arranque. Verificado saludable: `UP` en 26.1.0.118079, Compute Engine conectado a PostgreSQL 15, nginx end-to-end confirmado, Zabbix Agent 2 sin interrupción.
9. ✅ **Salto SonarQube 26.1.0.118079 → 26.9.0.129388 (versión final objetivo)**: mismo patrón. Falla real encontrada y corregida: el paquete descargado de esta versión específica no conservó los permisos de ejecución de los scripts en `bin/` al descomprimirse (`chmod +x` faltante, no un problema introducido por este trabajo) — corregido, junto con el estado de limitación de reintentos de systemd que había quedado activado. Migración de base de datos completada (~2 minutos, la más larga de las tres). **Verificado saludable: `UP` en 26.9.0.129388, nginx end-to-end confirmado, Zabbix Agent 2 sin ninguna interrupción durante las más de dos horas que duró toda la operación.**

## Estado final

Cadena completa ejecutada y verificada de punta a punta el 2026-09-05: SonarQube `9.9.3 → 24.12.0.100206 → 26.1.0.118079 → 26.9.0.129388`, SO `20.04 → 22.04.5 LTS`, Java `17 → 21`, PostgreSQL `13.15 → 15.19`. Sin pérdida de datos, sin interrupción de monitoreo Zabbix, con planes de rollback disponibles en cada paso (instalaciones viejas y cluster PostgreSQL 13 conservados, no eliminados).

## Acciones propuestas (housekeeping, sin urgencia)

1. ⚠️ (SRE) Tras un período de observación con SonarQube 26.9 estable, eliminar el cluster viejo `13/main` (`pg_dropcluster 13 main`) — no antes.
2. ⚠️ (SRE) Una vez confirmada la estabilidad, archivar/eliminar los directorios de instalación viejos de SonarQube (`sonarqube-9.9.3.79811/`, `sonarqube-9.6.1.59531/`, `sonarqube-24.12.0.100206/`, `sonarqube-26.1.0.118079/`) en `/opt/ssd01/sonarq/`.
3. 📌 (Futuro, fuera de alcance de este ticket) Si se decide en algún momento avanzar a Ubuntu 24.04, containerizar `get-fq.py` (o desacoplarlo de otra forma de la versión de Python del sistema operativo) **antes** de ese salto — 24.04 no tiene una fuente limpia de Python 3.10.

## Referencias

Ver `investigation.md` de este evento para el detalle completo (fuentes, comandos ejecutados, hallazgos intermedios) y `operations/docs/sonarqube_upgrade_runbook.md` para el runbook de referencia persistente.
