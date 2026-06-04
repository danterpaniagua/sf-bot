# [JIRA] Incidente: Picos de CPU en SFCG-DB01 — 30/05/2026

**Tipo:** Incidente de rendimiento  
**Severidad:** Alta  
**Servidor:** SFCG-DB01 — SQL Server 2022 Standard 16.0.4075.1  
**Base de datos afectada:** SmartFran.Solution.SmartLoyalty  
**Ventana del evento:** 30/05/2026 15:00–17:00 UTC-3 (18:00–20:00 GMT)  
**Reportado por:** Monitoreo  

---

## Descripción

Se registraron dos picos de uso de CPU superiores al 90% en el servidor de base de datos SFCG-DB01 durante la tarde del 30/05/2026. La investigación se realizó sobre las tablas de captura de `PNSSRL` (24 snapshots, ventana completa cubierta).

---

## Hallazgos

### Pico 1 — 15:16–15:21 UTC-3 (18:16–18:21 GMT)

- **Delta CPU total:** ~28.000 ms en 2 snapshots consecutivos.
- **Causa:** Concurrencia de múltiples consultas sin un único dominante.
  - **Query038** (SPID 82, `SFCG-WSIT-01`): 6.866 ms de delta.
  - **Query101** (múltiples SPIDs, `SFCG-WSV2-01`): ~4.000–4.600 ms por sesión, con 6+ sesiones concurrentes.
  - Consultas LINQ ad-hoc desde `SFCG-MOBI-02` y `SFCG-CLUB-01`: ~3.900–4.000 ms cada una.
- **Resolución:** Se disipó solo a las 18:26 GMT.

---

### Pico 2 — 16:21–16:36 UTC-3 (19:21–19:36 GMT)

- **Delta CPU total:** ~397.000 ms en 2 snapshots. El 83% corresponde a un único SPID.
- **Causa principal: Query078 — SPID 136, `SFCG-WSIT-01`.**

#### Detalle — Query078

| Métrica | Valor |
|---|---|
| Archivo | `D:\SmartLoyalty.WebSite\bin\Domain\Query\Query078-sql.xml` |
| Host | `SFCG-WSIT-01` |
| Login | `SMARTIT\itservices` |
| CPU acumulado (sysprocesses) | 330.505 ms |
| CPU rate pico (TempDB) | ~130.000 ms / 10 seg |
| Lecturas lógicas | 624.690 |
| Lecturas físicas | 1.716 |
| Escrituras | 152 |
| Memory grant | 2.574.534 páginas — valor elevado |
| Spill a tempdb | Sí (`internal_objects_page_counts` > 0 a las 19:35:30 GMT) |
| Duración estimada | ~15 minutos (19:21–19:36 GMT) |
| Objetos de usuario en tempdb | 272 páginas al inicio de ejecución |

**Descripción de la consulta:** Query078 recibe un `@BranchOfficeId` y resuelve el país correspondiente mediante 5 niveles de joins sobre `Sml.Location`. Luego ejecuta un SELECT masivo de datos de clientes con subconsultas correlacionadas para resolución de dirección y localidad. El memory grant elevado y el spill a tempdb indican un plan de ejecución con estimaciones de cardinalidad incorrectas, probablemente por estadísticas desactualizadas o reutilización de un plan subóptimo.

El paralelismo intenso (~130.000 ms CPU / 10 seg) confirma ejecución con DOP > 1 sobre un dataset grande.

---

## Acciones recomendadas

1. **Query078:** Revisar el plan de ejecución y actualizar estadísticas sobre las tablas involucradas (`Sml.BranchOffice`, `Sml.Address`, `Sml.Location`, tablas de clientes). Evaluar si el query puede ser reescrito para eliminar las subconsultas correlacionadas.
2. **Query101 / Query038:** Monitorear concurrencia. El volumen de sesiones simultáneas desde `SFCG-WSV2-01` durante el Pico 1 sugiere un patrón de carga que puede repetirse.

---

## Evidencia

| Archivo | Contenido |
|---|---|
| `20260530_cpu_spikes_query078.sql` | Texto completo de Query078 capturado desde `PNSSRL_TempdbProc.Query_Text` (SPID 136, 19:35 GMT) |

- Fuente primaria: `PNSSRL.dbo.PNSSRL_AuditSysprocesses` — 24 snapshots, 1.808 filas
- Fuente secundaria: `PNSSRL.dbo.PNSSRL_TempdbProc` — 19 capturas para SPID 136 (19:35 GMT)
- Ventana GMT: 2026-05-30 18:00–20:00
