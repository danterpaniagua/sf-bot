# JIRA — Ticket IT

**Proyecto:** SmartLoyalty / Infraestructura BD
**Tipo:** Bug — Performance
**Prioridad:** Media-Alta
**Reportado por:** Dante Paniagua, SRE
**Fecha:** 2026-05-17
**Ambiente:** Producción — SFCG-DB01 / SmartFran.Solution.SmartLoyalty

---

## Título

`[PERF] Query101 — WebServiceV2 genera concurrencia creciente por OR + funciones sobre columnas en SmlSt.CustomerAdditionalInformation`

---

## Descripción

Durante la investigación de los picos de CPU del 2026-05-17, se identificó que `Query101-sql.xml` (`SmartLoyalty.WebServiceV2`, `SFCG-WSV2-01`) genera concurrencia creciente sobre `SFCG-DB01` a partir de las 12:30 GMT, con entre 6 y 10 SPIDs simultáneos acumulando 4.000–8.500 ms de CPU cada uno por intervalo de captura.

La query consulta la tabla `SmlSt.CustomerAdditionalInformation` para obtener producto favorito y promedio de consumo por cliente. Contiene tres patrones que impiden el uso de índices.

---

## Query actual (Query101-sql.xml)

**Autor:** Juan Cruz Breppe — 21/03/2024
**Última modificación:** FedericoL — 11/02/2026

```sql
DECLARE @CardNumber NVARCHAR(100) = {0}
DECLARE @UidCode    NVARCHAR(100) = {1}
DECLARE @UidSerie   NVARCHAR(100) = {2}

SELECT ai.FavoriteProduct, ai.AverageWeight, ai.LastBuyDate,
       a.Name AS FavoriteProductName
FROM [SmlSt].[CustomerAdditionalInformation] ai
LEFT JOIN [Sml].[Article] a ON TRY_CAST(ai.FavoriteProduct AS INT) = a.Id
WHERE ai.CardNumber = @CardNumber
   OR (
       @UidCode IS NOT NULL
       AND @UidSerie IS NOT NULL
       AND LOWER(ai.UidCode) = LOWER(@UidCode)
       AND ai.UidSerie = @UidSerie
   )
```

---

## Problemas identificados

### 1 — OR en WHERE impide uso de índices

El `OR` entre `CardNumber` y `(UidCode + UidSerie)` fuerza al optimizador a realizar un full scan o index union sobre `CustomerAdditionalInformation`. Con 6–10 SPIDs concurrentes ejecutando esta query, los scans se acumulan y generan presión sostenida sobre el servidor.

### 2 — `LOWER()` sobre la columna bloquea el índice de UidCode

```sql
LOWER(ai.UidCode) = LOWER(@UidCode)
```

Aplicar una función sobre el lado de la columna impide que el optimizador use cualquier índice sobre `UidCode`. Si la collation de la columna es case-insensitive (default en SQL Server), `LOWER()` en ambos lados es además innecesario.

### 3 — `TRY_CAST` sobre la columna en el JOIN bloquea el índice de Article

```sql
LEFT JOIN [Sml].[Article] a ON TRY_CAST(ai.FavoriteProduct AS INT) = a.Id
```

Aplicar `TRY_CAST` sobre `ai.FavoriteProduct` en cada fila impide el uso del índice de `Article.Id`. Indica que `FavoriteProduct` está almacenado como `NVARCHAR` cuando debería ser `INT` o `FK` directa.

---

## Evidencia — hits a BD y CPU por ventana (PNSSRL_AuditSysprocesses)

Capturas cada 5 minutos. Los SPIDs representan ejecuciones concurrentes visibles en cada snapshot; ejecuciones breves entre capturas no quedan registradas.

| Ventana (GMT) | Hits (SPIDs) | CPU total ventana | CPU máx por SPID |
|---|---|---|---|
| 13:00 | 1 | 4.000 ms | 4.000 ms |
| 13:30 | 2 | 7.905 ms | 4.248 ms |
| 14:00 | 3 | 10.686 ms | 4.298 ms |
| 14:30 | 7 | 32.393 ms | 4.390 ms |
| 15:00 | 5 | 21.500 ms | 4.655 ms |
| 15:30 | 8 | 41.243 ms | 8.579 ms |
| 16:00 | 7 | 34.790 ms | 7.860 ms |
| 16:30 | 6 | 30.257 ms | 8.584 ms |
| **Total** | — | **182.774 ms (~182 seg)** | — |

Tendencia: concurrencia y CPU crecientes a lo largo de la tarde. Entre las 14:30 y 16:30 se estabilizan en 6–8 SPIDs simultáneos con picos individuales de hasta 8.500 ms por SPID.

---

## Solución propuesta

### Fix inmediato — reemplazar OR por UNION (desplegable sin cambio de esquema)

```sql
DECLARE @CardNumber NVARCHAR(100) = {0}
DECLARE @UidCode    NVARCHAR(100) = {1}
DECLARE @UidSerie   NVARCHAR(100) = {2}

SELECT ai.FavoriteProduct, ai.AverageWeight, ai.LastBuyDate,
       a.Name AS FavoriteProductName
FROM [SmlSt].[CustomerAdditionalInformation] ai
LEFT JOIN [Sml].[Article] a ON TRY_CAST(ai.FavoriteProduct AS INT) = a.Id
WHERE ai.CardNumber = @CardNumber

UNION

SELECT ai.FavoriteProduct, ai.AverageWeight, ai.LastBuyDate,
       a.Name AS FavoriteProductName
FROM [SmlSt].[CustomerAdditionalInformation] ai
LEFT JOIN [Sml].[Article] a ON TRY_CAST(ai.FavoriteProduct AS INT) = a.Id
WHERE @UidCode IS NOT NULL
  AND @UidSerie IS NOT NULL
  AND ai.UidCode  = @UidCode
  AND ai.UidSerie = @UidSerie
```

- Cada rama puede usar su propio índice seek.
- `LOWER()` eliminado — la collation del servidor maneja la comparación case-insensitive.
- `TRY_CAST` se mantiene temporalmente hasta que se resuelva el punto siguiente.

### Fix estructural — migración de esquema (requiere release)

Agregar columna `FavoriteProductId INT` en `SmlSt.CustomerAdditionalInformation` con FK a `Sml.Article.Id`, eliminar el `TRY_CAST` del JOIN y deprecar `FavoriteProduct NVARCHAR`.

### Índices — hallazgo y creación requerida

**Índices existentes en `SmlSt.CustomerAdditionalInformation`:**

| Índice | Tipo | Columnas | Seeks | Scans |
|---|---|---|---|---|
| `PK__Customer__3214EC074846ACB8` | CLUSTERED | `Id` | 0 | 25.833 |
| `IX_CustomerAdditionalInformation_CustomerId` | NONCLUSTERED | `CustomerId` | 278.224 | 8 |

**No existen índices sobre `CardNumber`, `UidCode` ni `UidSerie`.**

El PK clustered acumula **25.833 scans y 0 seeks** — cada llamada a Query101 realiza un full scan de la tabla. El índice de `CustomerId` es utilizado por otras queries pero no por Query101.

**Índices a crear:**

```sql
-- Rama 1: búsqueda por CardNumber
CREATE NONCLUSTERED INDEX IX_CustomerAdditionalInformation_CardNumber
ON SmlSt.CustomerAdditionalInformation (CardNumber)
INCLUDE (FavoriteProduct, AverageWeight, LastBuyDate)

-- Rama 2: búsqueda por UidCode + UidSerie
CREATE NONCLUSTERED INDEX IX_CustomerAdditionalInformation_UidCode_UidSerie
ON SmlSt.CustomerAdditionalInformation (UidCode, UidSerie)
INCLUDE (FavoriteProduct, AverageWeight, LastBuyDate)
```

Las columnas del `INCLUDE` cubren el `SELECT` completo de Query101, evitando un Key Lookup al clustered index. Con estos índices y el reemplazo del OR por UNION, los 25.833 scans se convierten en seeks por rama.

---

## Archivos relacionados

| Archivo | Descripción |
|---|---|
| `events/20260517_jira_cpu_query076_it.md` | Ticket relacionado — Query076 / SendCanjesSocioCortesiaToBlobStorage |
| `queries/PNSSRL_AuditoriaSysProcesses.sql` | Job de captura fuente de los datos analizados |
