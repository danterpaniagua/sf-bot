# Runbook — Actualización de SonarQube (`sfcg-sonarqube`)

> Origen: ticket `GITIN-1327`, evento `operations/events/20260905_sonarqube_upgrade/`. Ver ese evento (`investigation.md`) para el detalle completo de la investigación (fuentes de cada dato, hallazgos intermedios, teorías descartadas). Este documento es la referencia de infraestructura persistente; el evento es el registro de trabajo de la tarea puntual.

## 1. Objetivo

Actualizar la instancia de SonarQube Community Edition (9.9.3) corriendo en `sfcg-sonarqube` a una versión actual de SonarQube Community Build, siguiendo la ruta de actualización oficial y sin perder datos ni disponibilidad más allá de la ventana de mantenimiento planificada.

## 2. Topología y estado actual (confirmado)

- **Host:** `sfcg-sonarqube` (VM Azure, login `azureuser`), Ubuntu 20.04.6 LTS.
- **Versión/edición actual:** SonarQube **9.9.3** (build 79811), **Community Edition** (LGPL v3) — confirmado vía UI ("About") y vía classpath del proceso real.
- **Instalación:** manual, sin symlink — `/opt/ssd01/sonarq/sonarqube/` es un directorio real (no symlink a una versión), corre como `sonarqube:sonarqube`, servicio systemd `sonarqube.service`.
- **Otros directorios en `/opt/ssd01/sonarq/`:** `sonarqube-9.6.1.59531/` (versión anterior, sin configurar, leftover) y `sonarqube-10/` (reportado por el usuario como intento de actualización abandonado — no verificado independientemente en detalle). El directorio raíz `/opt/ssd01/sonarq/data/` (esqueleto `es8` vacío) está huérfano/sin uso — probablemente residuo de ese intento a 10.x (ES8 vs. el ES7 real de 9.9.3).
- **Datos reales:** `/opt/ssd01/sonarq/sonarqube/data/` (184M — índice ES7, plugins instalados). `sonar.path.data`/`sonar.path.temp` no están configurados explícitamente (usan el default relativo al home de instalación).
- **Java:** OpenJDK 17.0.15 (paquete Ubuntu) — suficiente hasta el primer salto (24.12), insuficiente a partir de 26.1.
- **Base de datos:** PostgreSQL 13.15 (`pgdg20.04`), local, `127.0.0.1:5432`, DB `sonarqube`, usuario `sonarqube` — suficiente hasta 25.x, insuficiente a partir de 26.x (requiere 15+).
- **Webserver:** nginx como reverse proxy (`/etc/nginx/conf.d/sonar.conf`), termina TLS con el wildcard cert de SmartFran, proxy directo a `127.0.0.1:9000` sin reescritura de path. Hostname público: `sf-sonarqube.smartfran.com`.
- **Host specs:** 2 CPU lógicas (1 core físico con hyperthreading — sin margen), 7.7GB RAM, 159GB libres en `/opt/ssd01`. `vm.max_map_count=552428` y límites de file descriptors (65536, vía systemd) ya cumplen los requisitos de Elasticsearch — sin necesidad de tuning de SO.

## 3. Ruta de actualización confirmada

SonarQube Community Edition fue renombrada a Community Build después de la versión 10.7 (nuevo esquema de versionado CalVer). Cualquier instancia anterior a 2024 debe pasar obligatoriamente por `24.12.0.100206` antes de llegar a cualquier release 2025+; además, cruzar un límite de año calendario requiere pasar por el release de diciembre de ese año.

**Ruta decidida:**

```
9.9.3 (LTA) → 24.12.0.100206 → 26.1.0.118079 → 26.9.0.129388
```

- El salto intermedio "natural" sería `25.12.0.117093`, pero esa versión tiene un bug de migración de base de datos documentado y reportado por otros usuarios (issues reales en el foro de SonarSource) — `26.1.0.118079` lo resuelve y está documentado como sustituto válido para ese hop.
- `26.9.0.129388` es la última versión de Community Build disponible al momento de esta investigación (verificar de nuevo antes de ejecutar, por si hay una versión más nueva).

## 4. Requisitos de infraestructura por salto

| Salto | Java requerido | PostgreSQL requerido |
|---|---|---|
| 9.9.3 → 24.12.0.100206 | JRE/JDK 17 (actual, sin cambios) | 13.15 (actual, sin cambios) |
| 24.12.0.100206 → 26.1.0.118079 | **JDK 21 o 25 completo** (no alcanza con JRE) | **PostgreSQL 15+** (rango soportado 15-18) |
| 26.1.0.118079 → 26.9.0.129388 | Sin cambios adicionales | Sin cambios adicionales |

Ambos cambios de infraestructura (Java y PostgreSQL) caen en el mismo punto de la secuencia.

## 4bis. Requisito de actualización de sistema operativo

Verificado: instalar PostgreSQL 15+ en Ubuntu 20.04 (host actual) ya **no es un procedimiento limpio**. El repositorio oficial PGDG dejó de construir/alojar paquetes para Ubuntu 20.04 (focal) desde julio de 2025 — esa versión de Ubuntu también está EOL del lado de PGDG. Los paquetes de PG 15/16/17 solo son alcanzables vía un repositorio de archivo, que el propio PGDG reconoce tiene "conflictos de dependencias con las bibliotecas base envejecidas" del sistema, haciendo la instalación no confiable. Independientemente, Ubuntu 20.04 llegó a fin de soporte estándar en abril/mayo de 2025 — más de un año atrás a la fecha de esta investigación (2026-09-05), salvo que el host esté enrolado en Ubuntu Pro/ESM (no confirmado).

**Pre-check confirmado (2026-09-05):** no hay suscripción Ubuntu Pro/ESM activa (`pro status` — "This machine is not attached to an Ubuntu Pro subscription"). El mirror en uso es `azure.archive.ubuntu.com` (mirror regional de Azure), que sigue sirviendo `focal` correctamente pese al EOL estándar — `apt-get update` funciona sin errores. `do-release-upgrade -c` confirma: `New release '22.04.5 LTS' available`.

**Riesgo nuevo, no cubierto en el diseño original:** cinco repos de terceros están fijados específicamente a `focal`: `ppa:deadsnakes`, Docker CE (`download.docker.com/linux/ubuntu focal`), Microsoft Azure CLI (`packages.microsoft.com/ubuntu/20.04/prod focal`), Trivy, y **tres repos de Zabbix** (`zabbix-agent2-plugins`, `zabbix-tools`, `zabbix/6.0`, todos con sufijo `focal`). Tras el upgrade a `jammy` (22.04), estos repos van a fallar (404) hasta que se re-apunten a `jammy` — `do-release-upgrade` probablemente los deshabilite automáticamente durante el proceso (comportamiento estándar y seguro para fuentes de terceros no reconocidas), pero hay que re-habilitarlos/re-apuntarlos manualmente después. El agente Zabbix ya instalado seguirá corriendo sin interrupción inmediata, pero no recibirá actualizaciones hasta corregir esto — acción de seguimiento obligatoria post-upgrade, dado el requisito explícito de mantener Zabbix funcionando.

Confirmado vía IMDS: suscripción `0190fa7d-4ccf-4e3d-beb1-323b5780bfc8` (Smart IT - Grido), resource group `DEFAULTGROUP01`.

**Decisión (confirmada por el usuario):** actualizar el sistema operativo del host **in-place** (`do-release-upgrade`, 20.04 → 22.04 → 24.04 — la herramienta de Ubuntu solo permite saltar a la siguiente LTS, no saltear una, por lo que son dos actualizaciones secuenciales; verificar que esta restricción siga vigente contra la herramienta actual antes de ejecutar). Esto es una operación de mayor riesgo sobre un host de producción vivo (toca nginx, systemd, y cualquier otro paquete instalado, no solo las dependencias de SonarQube) y necesita su propio plan de rollback (el snapshot de VM de la sección 5 cubre esto — confirmar que se toma un snapshot inmediatamente antes de la actualización de SO específicamente, no solo una vez al inicio de todo el proyecto).

## 4ter. Salto 20.04 → 22.04 completado (2026-09-05) — problemas reales y causas confirmadas

`do-release-upgrade` requirió dos pasadas para completar (la primera quedó a mitad de camino, sin reiniciar). Tres fallas reales de dpkg diagnosticadas vía `/var/log/apt/term.log` (el resumen genérico "Errors were encountered" NO trae la causa real — buscar `dpkg: error processing archive ... (--unpack)`/`(--configure)` línea por línea):

- **`dotnet-hostfxr-7.0`**: dependía de `dotnet-host-7.0`, ausente porque el repo de Microsoft está fijado a `focal` — resuelto con `apt --fix-broken install` (Ubuntu's propio jammy-updates ya trae una versión compatible).
- **`cron`/`at`**: `error creating directory './var/spool/cron/crontabs': Operation not permitted`. Causa: `/var/spool/cron` tenía **tanto el atributo inmutable (`i`) como append-only (`a`)** seteados (hardening deliberado preexistente, no introducido por este upgrade) — hubo que limpiar AMBOS (`chattr -ia`, no alcanza con solo `-i`) antes de que dpkg pudiera finalizar la extracción, y restaurar ambos (`chattr +ia`) después. Confirmado intacto post-reboot.
- **`linux-azure-tools-5.15.0-1050`**: conflicto de archivo con el paquete obsoleto `linux-azure-5.15-tools-5.15.0-1050` (gap de renombrado de paquetes de kernel entre focal/jammy). `apt-get remove` se negó a correr mientras hubiera cualquier otro paquete roto en la base de datos de dpkg (chequeo global de consistencia) — la solución fue `sudo dpkg --remove linux-azure-5.15-tools-5.15.0-1050` directo, sin pasar por el resolver de apt.

**Verificado post-reboot, todo saludable:** kernel `6.8.0-1065-azure`, SonarQube 24.12.0.100206 (`status: UP`, arrancó solo vía systemd sin intervención manual), PostgreSQL `postgresql@13-main` con SonarQube ya reconectado, nginx (`HTTP 200` vía el truco de Host header), Zabbix Agent 2 sin interrupción.

**Repos de terceros — completado (2026-09-05):** de los 5 fijados a `focal`, `do-release-upgrade` deshabilitó automáticamente 2 de los 3 de Zabbix (`zabbix.list`, `zabbix-agent2-plugins.list`, con el codename `jammy` ya pre-sustituido en el comentario) pero dejó `zabbix-tools.list` activo y sin tocar. Docker CE y Azure CLI tampoco fueron tocados por la herramienta. Los 5 fueron re-apuntados/re-habilitados a `jammy` y verificados con `apt-get update` (todos resuelven limpio). Trivy no necesitaba cambio — su repo usa un componente `generic`, no un codename de distribución (estaba mal incluido en la lista original de riesgo).

**`ppa:deadsnakes` investigado:** su único propósito real en este host era proveer Python 3.10 para `get-fq.py` (script ajeno a SonarQube, trae datos de Grido a la capa bronze de Fabric, alojado en esta misma VM). Ubuntu 22.04 ya provee `python3.10` nativamente, así que el repo dejó de ser necesario — eliminado, junto con `python3.9`/`python3.9-minimal` (sin consumidores identificados).

## 5. Decisión de alcance: salto a 24.04 descartado

Re-evaluado si 24.04 era realmente necesario: **no lo es.** PGDG soporta PostgreSQL 15/16/17 en Ubuntu 22.04 sin fecha de corte hasta bien entrado 2029, y JDK 21 está disponible limpiamente en 22.04 vía Adoptium — ambos bloqueantes que motivaron la actualización de SO ya están resueltos en 22.04. Además, 24.04 no tiene una fuente limpia de Python 3.10 para `get-fq.py`: el PPA principal de deadsnakes no lo publica para `noble` (solo su canal nightly/inestable, no apto para producción). **El salto 22.04 → 24.04 queda fuera de alcance de este ticket** — si se retoma en el futuro, `get-fq.py` debe containerizarse (Docker ya está instalado en este host) o desacoplarse de otro modo de la versión de Python del sistema operativo antes de intentarlo.

## 6. Secuencia recomendada (aísla variables — un cambio por vez)

1. `9.9.3 → 24.12.0.100206` primero, sobre el SO/Java 17/PostgreSQL 13.15 **actuales** — valida el procedimiento de swap de binario/rollback específico de SonarQube sin mezclarlo con cambios de sistema operativo.
2. **Actualización de SO** (20.04 → 22.04, sin continuar a 24.04 — ver sección 5), en su propia ventana de mantenimiento dedicada, con SonarQube 24.12 ya corriendo — verificar que SonarQube + PostgreSQL 13.15 + nginx sigan funcionando correctamente después de la actualización de SO antes de tocar cualquier otra cosa. Aísla fallas causadas por el SO de fallas causadas por la actualización de SonarQube.
3. **Actualización de Java 21/25 + PostgreSQL 15+** sobre Ubuntu 22.04, ambos disponibles limpiamente vía los repositorios oficiales PGDG/Adoptium.
4. `24.12.0.100206 → 26.1.0.118079`.
5. `26.1.0.118079 → 26.9.0.129388`.

## 7. Plan de rollback

Las migraciones de esquema de SonarQube son de un solo sentido — no hay downgrade de base de datos. El rollback real depende de backups tomados inmediatamente antes de cada salto, no de un backup único al inicio.

**Pre-flight (una sola vez, antes de tocar nada — y repetir el snapshot puntualmente antes de la actualización de SO de la sección 5, paso 2):**
- Snapshot de disco de la VM `sfcg-sonarqube` en Azure.
- `pg_dump` completo de la base `sonarqube`.
- Backup de `/opt/ssd01/sonarq/sonarqube/data/` (184M — índice ES7 + plugins). No hace falta respaldar `sonarqube/temp/` (estado regenerable).
- Backup de `sonar.properties`, `sonar.conf` (nginx) y la unit de systemd `sonarqube.service`.

**Por cada salto (24.12, 26.1, 26.9):**
- Extraer la nueva versión en un directorio propio nuevo (`sonarqube-24.12.0.100206/`, etc.) — nunca sobrescribir el directorio de la versión corriendo. **Nota:** `azureuser` no tiene permiso de escritura directo sobre `/opt/ssd01/sonarq/` — el `unzip`/`chown`/`cp` de esta etapa necesitan `sudo` (o una sesión `sudo su`), confirmado en la ejecución real del salto 1.
- Copiar el `sonar.properties` ya configurado (no retipear credenciales de DB) al `conf/` de la nueva versión.
- **Mecanismo de corte confirmado (salto 1):** la unit `sonarqube.service` no usa `WorkingDirectory` — `ExecStart`/`ExecStop` embeben el path literal `/opt/ssd01/sonarq/sonarqube/bin/linux-x86-64/sonar.sh`. Por eso el corte es un **swap de directorios** (`mv sonarqube sonarqube-<version-vieja>` seguido de `mv sonarqube-<version-nueva> sonarqube`), no una edición de la unit — cero cambios de systemd, sin `daemon-reload`.
- `pg_dump` nuevo inmediatamente antes de este salto puntual (no reusar el del salto anterior).
- Detener `sonarqube.service`, apuntarlo al nuevo directorio, iniciar, revisar `logs/sonar.log` y `logs/ce.log`.
- **Migración de base de datos manual, confirmado en el salto 1:** al iniciar, SonarQube NO corre la migración de esquema automáticamente — queda en estado `DB_MIGRATION_NEEDED`, visible en `sonar.log` ("The database must be manually upgraded. Please backup the database and browse /setup") y vía `GET /api/system/status`. Hay que disparar la migración explícitamente (UI en `/setup`, o `POST /api/system/migrate_db`) en cada salto — no asumir que el arranque del servicio ya completó la migración. `ce.log` no existe todavía en este estado (Compute Engine no arranca hasta después de migrar) — no es un error. `GET /api/server/version` ya no existe como endpoint desde esta versión en adelante; usar `/api/system/status` para chequear versión/estado.
- Si falla: detener, apuntar de nuevo al directorio anterior (intacto), restaurar el `pg_dump` de este salto, reiniciar.
- No borrar/archivar la versión anterior hasta confirmar que el siguiente salto está estable.
- **Verificación correcta post-salto (confirmado en salto 1):** curlear el hostname público directamente desde la propia VM puede devolver `000` aunque todo funcione bien — esta VM no resuelve su propio nombre DNS público. Verificar con `curl -H "Host: sf-sonarqube.smartfran.com" https://127.0.0.1/` (forzando el header) en vez de `curl https://sf-sonarqube.smartfran.com/` desde la misma VM. La confirmación real de extremo a extremo es desde fuera de la VM (navegador o `curl` externo).
- Zabbix Agent 2 debe verificarse sano (activo, sin gaps de reporte) antes y después de cada salto — ver sección 4bis para el punto de mayor riesgo (actualización de SO).

**Java:** instalar JDK 21/25 en paralelo al JDK 17 existente (`update-alternatives`), sin desinstalar 17 — un rollback a 24.12 después de un intento fallido de 26.1 todavía necesita Java 17.

**PostgreSQL:** el upgrade mayor 13→15 es una operación separada y más difícil de revertir (`pg_upgrade` o dump/restore a un cluster nuevo) — mantener el cluster PG 13 detenido pero intacto (no borrado) hasta confirmar estabilidad de PG 15 + SonarQube 26.1 durante un período de observación, no solo inmediatamente después del corte.

## 7bis. Rol adicional del host: agente Jenkins compartido (`sonarqube-srv`), confirmado 2026-09-23 (`GITIN-2099`)

Además de correr SonarQube, `sfcg-sonarqube` también es el agente Jenkins **`sonarqube-srv`** (Ubuntu, vía SSH), compartido entre los pipelines de SF-LOYALTY y SF-PEDIDOS (ver `sf-devops/jenkins/SF-PEDIDOS/smartpedidos.md`). Este rol es independiente del servicio de SonarQube — no está documentado en la investigación original de `GITIN-1327`.

**Hallazgo confirmado (2026-09-23):** tras actualizar el controller Jenkins (`SFCG-JENKINS-01`) de Java 17 a Java 21 (ver `loyalty/docs/infrastructure.md` → `SFCG-JENKINS-01`), el agente `sonarqube-srv` empezó a fallar la conexión SSH/Remoting con `java.lang.UnsupportedClassVersionError` (class file version 65 = Java 21 vs. 61 = Java 17 máximo soportado) — el `java` del sistema en este host (resuelto vía `update-alternatives`, **no** `SONAR_JAVA_PATH`) seguía apuntando a `java-17-openjdk-amd64` al momento del hallazgo, pese a que Temurin 21 ya estaba instalado en el host desde el propio `GITIN-1327` (sección 6/7).

**Causa de que `java-17` volviera a ser el default del sistema:** no investigada — el `update-alternatives --set java` a Temurin 21 documentado en la sección 6 fue explícitamente reconocido en su momento como "trade-off aceptado... nada más depende de 21 todavía"; en algún punto posterior algo lo revirtió a 17 (no confirmado si fue un `apt upgrade` rutinario re-disparando el modo `auto`, una reversión manual, u otra causa). Como el propio servicio de SonarQube nunca dependió de este default del sistema (usa `SONAR_JAVA_PATH` desde el salto a 26.1, sección 6), este drift no tuvo ningún efecto visible sobre SonarQube — solo se manifestó cuando **otro** consumidor del `java` del sistema (el agente Jenkins) empezó a necesitar una versión compatible con Java 21.

**Fix aplicado (2026-09-23):** `sudo update-alternatives --set java /usr/lib/jvm/temurin-21-jdk-amd64/bin/java` (modo manual, no `auto`). **Verificado sin impacto en SonarQube** antes y después del cambio: `GET /api/system/status` → `{"version":"26.9.0.129388","status":"UP"}` sin interrupción, uptime del servicio intacto (sin reinicio), los 5 procesos `java` de SonarQube siguen corriendo bajo `/usr/lib/jvm/temurin-21-jdk-amd64/bin/java` vía el drop-in `SONAR_JAVA_PATH` — confirma que ambos mecanismos (el `SONAR_JAVA_PATH` de SonarQube y el `update-alternatives` de todo lo demás en el host) son efectivamente independientes, tal como predice el hallazgo original de la sección 6.

**Lección para el futuro:** en este host específicamente, un cambio al `java` default del sistema (`update-alternatives`) es seguro respecto a SonarQube — pero no es la única cosa que corre `java` en esta VM (el agente Jenkins es otra). Antes de asumir que un drift del default del sistema es inofensivo, confirmar qué más depende de él (no solo SonarQube).

## 8. Fuera de alcance

- **AI Code Assurance / detección de código generado por IA:** feature de Developer Edition en adelante (pago) — no disponible en Community Build sin importar la versión alcanzada. Requeriría una decisión separada de cambio de edición/licencia, fuera del alcance de `GITIN-1327` tal como está entendido hoy.
- El directorio `sonarqube-10/` (intento de actualización abandonado, reportado por el usuario) no fue verificado en detalle — antes de ejecutar, conviene confirmar que no contiene estado de migración parcial que pueda confundir el intento real.
- **Salto de SO a Ubuntu 24.04:** descartado para este ticket (ver sección 5) — iniciativa futura separada, condicionada a desacoplar `get-fq.py` de la versión de Python del sistema operativo primero.

## 9. Referencias

- https://docs.sonarsource.com/sonarqube-community-build/server-update-and-maintenance/update/determine-path
- https://docs.sonarsource.com/sonarqube-community-build/server-installation/server-host-requirements
- https://community.sonarsource.com/t/upgrade-path-for-our-sonarqube-community-edition-9-9-3-instance/149250
- https://community.sonarsource.com/t/sonarqube-community-build-25-12-0-117093-released/153805
- https://community.sonarsource.com/t/postgresql-compatibility-for-sonarqube-upgrade-from-9-9-3-to-25-4/145051
- https://www.postgresql.org/message-id/aCtIvml4sCYnRSjp@msg.df7cb.de (PGDG drops Ubuntu focal packages, julio 2025)
- https://ubuntu.com/blog/ubuntu-20-04-lts-end-of-life-standard-support-is-coming-to-an-end-heres-how-to-prepare (fin de soporte estándar Ubuntu 20.04)
