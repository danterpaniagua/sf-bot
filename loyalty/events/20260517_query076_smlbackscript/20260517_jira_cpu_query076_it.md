# JIRA — Ticket IT

**Proyecto:** SmartLoyalty / Infraestructura BD
**Tipo:** Bug — Performance
**Prioridad:** Alta
**Reportado por:** Dante Paniagua, SRE
**Fecha:** 2026-05-17
**Ambiente:** Producción — SFCG-DB01 / SmartFran.Solution.SmartLoyalty

---

## Título

`[PERF] Query076 — SendCanjesSocioCortesiaToBlobStorage genera ~700 seg de CPU por ejecución × 32 ejecuciones diarias`

## ✅ Resolución — 2026-05-17

Optimización aplicada: reemplazo de `IN (subquery)` por `INNER JOIN` en `Query076-sql.xml`.

| Métrica | Original | Optimizado |
|---|---|---|
| Duración por ejecución | 00:01:05 | 00:00:02 |
| Filas devueltas | 18.422 | 18.422 |
| Reducción | — | **97%** |

Archivo actualizado: `Query076-sql.xml` — `UpdatedBy: Dante Paniagua`, `UpdatedDate: 2026-05-17`.
Pendiente: desplegar el XML actualizado en `SFCG-TO-01` (`E:\SmartLoyalty.TaskOperatorService\bin\Domain\Query\Query076-sql.xml`).

---

## Descripción

La Scheduled Task `SendCanjesSocioCortesiaToBlobStorage` (componente `SmartLoyalty.SmlBackScript`) ejecuta `Query076-sql.xml` cada 30 minutos durante una ventana de 16 horas diarias (11:00–03:00 UTC). Su propósito es extraer canjes de socios con puntos de cortesía y escribirlos en Azure Blob Storage.

Cada ejecución de la query acumula **~700.000 ms (~700 segundos) de CPU**, lo que genera picos de ~40% detectados por Zabbix con cadencia de 30 minutos. Con 32 ejecuciones diarias, el impacto total es de aproximadamente **22.400 segundos de CPU por día** atribuibles exclusivamente a este job.

---

## Causa raíz

`Query076-sql.xml` contiene dos problemas de performance estructurales:

### Problema 1 — Fecha de corte estática en 2023-01-01

```sql
WHERE e.ExchangeDate > '2023-01-01 00:00:00.0000000 +00:00'
```

El filtro nunca avanza. Cada ejecución escanea **más de 3 años de registros** de `Sml.Exchange`. El dataset crece día a día sin límite superior, por lo que el costo de la query aumenta progresivamente con el tiempo.

### Problema 2 — Subquery IN sobre CustomerPointsLog

```sql
AND e.[CustomerId] IN (
    SELECT DISTINCT [CustomerId]
    FROM [Sml].[CustomerPointsLog]
    WHERE Points > 19999 AND LogDate > '2023-01-01'
)
```

El patrón `IN (subquery)` fuerza la evaluación completa del conjunto de `CustomerId` antes de poder filtrar el resultado principal. Con el volumen actual de `CustomerPointsLog`, esto implica escanear todos los registros con `Points > 19999` desde 2023 en cada una de las 32 ejecuciones diarias.

### Query completa (Query076-sql.xml)

```sql
SELECT e.Id, c.[FirstName], c.[LastName], e.[ExchangeDate],
       e.BranchOfficeId, e.CustomerCardId, e.CustomerId,
       e.InvalidatedPointsLogId, b.[Id] as 'boID', b.Code, b.Name,
       b.FranchiseGroupId, b.AddressId, p.ArticleId, p.Points,
       a.LocationId, l.[ParentLocationId],
       CONCAT(c.[LastName], ', ', c.[FirstName]) AS 'Nombre completo',
       a.ZipCode, poi.Lat, poi.Lng
FROM [Sml].[Exchange] e
INNER JOIN [Sml].[BranchOffice]      b   ON e.[BranchOfficeId] = b.[Id]
INNER JOIN [Sml].[CustomerPointsLog] p   ON e.[PointsLogId]    = p.Id
INNER JOIN [Sml].[Address]           a   ON b.AddressId        = a.Id
INNER JOIN [Sml].[Person]            c   ON c.Id               = e.CustomerId
INNER JOIN [Sml].[Location]          l   ON l.Id               = a.LocationId
INNER JOIN [Sml].[Poi]               poi ON a.PoiId            = poi.Id
WHERE e.ExchangeDate > '2023-01-01 00:00:00.0000000 +00:00'
  AND e.[CustomerId] IN (
      SELECT DISTINCT [CustomerId]
      FROM [Sml].[CustomerPointsLog]
      WHERE Points > 19999 AND LogDate > '2023-01-01'
  )
```

---

## Evidencia — CPU delta por ejecución

| Ventana (GMT) | SPID | CPU delta (ms) | Login | Host |
|---|---|---|---|---|
| 11:30 | 73 | 701.207 | sfsqlusr | SFCG-TO-01 |
| 12:00 | 91 | 703.201 | sfsqlusr | SFCG-TO-01 |
| 13:00 | 100 | 700.379 | sfsqlusr | SFCG-TO-01 |
| 13:30 | 103 | 696.907 | sfsqlusr | SFCG-TO-01 |
| 14:30 | 116 | 700.140 | sfsqlusr | SFCG-TO-01 |

---

## Scheduled Task — configuración

| Campo | Valor |
|---|---|
| Nombre | `SendCanjesSocioCortesiaToBlobStorage` |
| Componente | `SmartLoyalty.SmlBackScript` |
| Host | SFCG-TO-01 |
| Login BD | `sfsqlusr` |
| Inicio | 11:00 UTC |
| Duración | 16 horas (hasta 03:00 UTC) |
| Frecuencia | cada 30 minutos |
| Ejecuciones diarias | 32 |
| Destino | Azure Blob Storage |

---

## Impacto acumulado

| Métrica | Valor |
|---|---|
| CPU por ejecución | ~700.000 ms |
| Ejecuciones por día | 32 |
| CPU total diaria (solo este job) | ~22.400 seg |
| Pico Zabbix por ejecución | ~40% |

---

## Recomendaciones técnicas

**Optimización de la query (sin cambiar el comportamiento del job):**

1. Reemplazar `IN (subquery)` por `INNER JOIN` — mayor impacto de performance:

```sql
INNER JOIN (
    SELECT DISTINCT CustomerId
    FROM [Sml].[CustomerPointsLog]
    WHERE Points > 19999
      AND LogDate > '2023-01-01'
) fraud_cpl ON e.CustomerId = fraud_cpl.CustomerId
WHERE e.ExchangeDate > '2023-01-01 00:00:00.0000000 +00:00'
```

2. Evaluar si el job puede operar sobre un delta (canjes nuevos desde la última ejecución) en lugar del set completo desde 2023. Si el blob se sobreescribe en cada run, solo los registros nuevos son relevantes, reduciendo el scan a minutos en lugar de años.

3. Verificar índices en:
   - `Sml.Exchange (ExchangeDate, CustomerId)`
   - `Sml.CustomerPointsLog (Points, LogDate, CustomerId)`

**Evaluación de frecuencia:**
Si el consumidor del blob en Azure tolera datos con hasta 60–120 minutos de antigüedad, duplicar el intervalo de ejecución reduce el impacto a la mitad sin cambiar la query.

---

## Problema secundario: Query101 (SFCG-WSV2-01)

Concurrencia creciente de `Query101-sql.xml` desde `SFCG-WSV2-01` a partir de las 12:30 GMT (6–10 SPIDs simultáneos, 4–8 seg de CPU cada uno). Contribuye al incremento sostenido del SPID count durante la tarde. Requiere análisis separado.

---

## Archivos relacionados

| Archivo | Descripción |
|---|---|
| `events/20260517_fraude_evidencia/01_queries_investigacion.sql` | Queries de investigación de fraude del mismo día |
| `queries/PNSSRL_AuditoriaSysProcesses.sql` | Job de captura fuente de los datos analizados |
