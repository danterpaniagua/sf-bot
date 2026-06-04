# [DB] CPU User Time >90% — 3 eventos 2026-05-18 — SmlSt.CustomerAdditionalInformation sin índice

**Tipo:** Bug / Performance
**Componente:** Base de datos — SmartFran.Solution.SmartLoyalty
**Prioridad:** Alta

---

## Descripción

El 18 de mayo de 2026 se registraron tres eventos de CPU User Time superior al 90% en el servidor de base de datos (`SFCG-DB01`), en los horarios 08:00–09:00, 11:00–12:00 y 21:00–23:00 (UTC-3).

## Causa raíz

**Query101-sql.xml** (`D:\SmartLoyalty.WebServiceV2\bin\Domain\Query\Query101-sql.xml`), ejecutada desde `SFCG-WSV2-01` con la cuenta `SMARTIT\itservices`, realiza un escaneo completo sobre `[SmlSt].[CustomerAdditionalInformation]` (4.742.925 filas) en cada llamada.

**Factores:**

- La tabla no tiene índices sobre las columnas del filtro (`CardNumber`, `UidCode`, `UidSerie`). El único índice existente es sobre `CustomerId`, que esta consulta no utiliza.
- El predicado `LOWER(ai.UidCode) = LOWER(@UidCode)` aplica una función sobre la columna, haciendo el predicado no sargable. La columna tiene collation `SQL_Latin1_General_CP1_CI_AS` (case-insensitive): el `LOWER()` es innecesario y bloquea el uso de índices.
- El evento E3 (21:00–23:00) fue el más severo: en ese horario esta consulta es la carga dominante sobre el servidor.

## Trace data

Ver: `20260518_cpu_spikes_query101.sql`

## Acciones requeridas

1. **[DB]** Crear índice sobre `(CardNumber)` con INCLUDE `(FavoriteProduct, AverageWeight, LastBuyDate)` en `SmlSt.CustomerAdditionalInformation`.

```sql
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID('[SmlSt].[CustomerAdditionalInformation]')
      AND name = 'IX_CustomerAdditionalInformation_CardNumber'
)
CREATE NONCLUSTERED INDEX [IX_CustomerAdditionalInformation_CardNumber]
    ON [SmlSt].[CustomerAdditionalInformation] ([CardNumber])
    INCLUDE ([FavoriteProduct], [AverageWeight], [LastBuyDate])
    WITH (SORT_IN_TEMPDB = ON);
```

2. **[DB]** Crear índice sobre `(UidCode, UidSerie)` con INCLUDE `(FavoriteProduct, AverageWeight, LastBuyDate)` en `SmlSt.CustomerAdditionalInformation`.

> ⚠️ **Este índice no será utilizado hasta que se implemente la Acción 3.** El predicado `LOWER(ai.UidCode) = LOWER(@UidCode)` aplica una función sobre la columna, lo que impide el uso del índice. La corrección del código es un prerequisito.

```sql
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID('[SmlSt].[CustomerAdditionalInformation]')
      AND name = 'IX_CustomerAdditionalInformation_UidCode_UidSerie'
)
CREATE NONCLUSTERED INDEX [IX_CustomerAdditionalInformation_UidCode_UidSerie]
    ON [SmlSt].[CustomerAdditionalInformation] ([UidCode], [UidSerie])
    INCLUDE ([FavoriteProduct], [AverageWeight], [LastBuyDate])
    WITH (SORT_IN_TEMPDB = ON);
```

> ⚠️ **SQL Server 2022 Standard Edition — ejecutar en ventana de mantenimiento.** `ONLINE = ON` no está disponible en esta edición. La creación de índices bloquea accesos a la tabla hasta que finaliza.

3. **[WebServiceV2]** Corregir Query101-sql.xml: reemplazar `LOWER(ai.UidCode) = LOWER(@UidCode)` por `ai.UidCode = @UidCode`. La corrección del código es necesaria para que los índices sean utilizables en la rama UidCode/UidSerie del filtro.

## Hallazgo secundario — ASYNC_NETWORK_IO en SFCG-WEBS-03 (E2)

Durante el evento E2 (14:00–15:00 GMT) se detectaron sesiones en estado `suspended / ASYNC_NETWORK_IO` desde `SFCG-WEBS-03`, ejecutando consultas LINQ sobre el catálogo de productos. Indica que el cliente no consumía filas con la velocidad suficiente. Se recomienda abrir ticket separado para investigar configuración de timeout y tamaño de result set en WEBS-03.

## Entorno

| Campo            | Valor                                    |
|------------------|------------------------------------------|
| Servidor         | SFCG-DB01                                |
| Base de datos    | SmartFran.Solution.SmartLoyalty          |
| Host origen      | SFCG-WSV2-01                             |
| Cuenta           | SMARTIT\itservices                       |
| Tabla afectada   | SmlSt.CustomerAdditionalInformation      |
| Filas            | 4.742.925                                |
