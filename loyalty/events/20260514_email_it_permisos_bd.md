# Email — Permisos excesivos en base de datos de producción

**Para:** IT Team
**De:** Dante Paniagua — SRE
**Asunto:** Permisos en producción — encontré algo que deberíamos revisar

---

Gente,

Hoy haciendo un análisis de rendimiento me topé con un par de cosas en los permisos de base de datos que creo que vale la pena revisar juntos.

**Lo que encontré**

Las cuentas `sfsqlusr` y `sfsqlusrit` tienen `db_owner` y `db_securityadmin` sobre la base de datos de producción (`SmartFran.Solution.SmartLoyalty`).

`db_owner` es el nivel de acceso más alto en SQL Server — le da a esa cuenta la posibilidad de borrar tablas, modificar estructuras, leer toda la data y otorgar permisos a otros. Es demasiado para una cuenta de servicio o de QA.

**Lo que pasó hoy**

Zabbix disparó dos alertas de CPU User Time >90% en la base de datos de producción:

- **14:00 – 16:00** — carga sostenida de CPU durante dos horas.
- **18:25 – 18:45** — pico puntual de CPU.

Revisando las capturas de monitoreo interno para entender la causa, encontré que durante el primer evento Lucas Bustos (QA) estuvo conectado a producción desde su máquina (`LUCAS-KIUVI`) con `sfsqlusrit`, corriendo consultas pesadas directamente sobre la base. Eso contribuyó a la carga de CPU de ese período.

La query que estaba ejecutando es un reporte de notificaciones de consumos por franquicia — consulta las tablas `Sml.Sale`, `Sml.Person`, `Sml.FranchiseStaff`, `Mbr.Member` y otras, con agregaciones diarias y semanales, y genera una lista de emails para envío por PowerShell. El script tiene el comentario `-- ** PARA PRUEBAS **` y una fecha hardcodeada (`2026-05-12`), lo que indica que estaba siendo ejecutado manualmente en modo de prueba sobre producción. A las 14:36 ya acumulaba **168.783 ms de CPU** (casi 3 minutos de CPU continuo) y seguía corriendo.

El script completo está en `events/20260514_lucas_query_sfsqlusrit.sql`.

No es un tema de lo que hizo Lucas — es que ese nivel de acceso no debería existir en primer lugar.

**Lo que propongo**

1. Sacarle `db_owner` y `db_securityadmin` a `sfsqlusrit` y `sfsqlusr` en `SmartFran.Solution.SmartLoyalty`.
2. Reemplazarlos por permisos acordes a lo que cada cuenta realmente hace:
   - `sfsqlusr` (TaskOperatorService) → SELECT, INSERT, UPDATE, DELETE sobre los esquemas específicos que usa.
   - `sfsqlusrit` (QA) → solo lectura, y solo si hay una necesidad puntual aprobada, no acceso permanente desde equipos personales.
3. Definir un canal controlado para que QA o desarrollo puedan consultar prod cuando lo necesiten, sin conectarse directo.
4. Aprovechar y revisar si hay otras cuentas en la misma situación — el patrón hace pensar que no son casos aislados.

Tengo los detalles técnicos completos si los necesitan para avanzar. ¿Coordinamos?

Dante Paniagua
SRE

