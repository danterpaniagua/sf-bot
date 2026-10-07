Asunto: Picos de CPU en base de datos — SmartLoyalty

Hola,

Les cuento sobre un hallazgo detectado hoy en el monitoreo de la base de datos de SmartLoyalty.

**Qué se observó**

Entre las 19:15 y las 20:23 (hora local) se detectó carga elevada de CPU en el servidor de base de datos, originada principalmente en una consulta que usa WebServiceV2 para obtener el producto favorito y el promedio de consumo de cada cliente durante el proceso de venta. La consulta recorre la tabla completa en cada ejecución porque no existe un índice que soporte una búsqueda directa por los campos que usa (número de tarjeta / código UID).

Este mismo patrón ya había sido identificado a mediados de mayo; la mejora propuesta en ese momento no parece haberse aplicado aún.

**Consulta involucrada**

Aplicación: SmartLoyalty.WebServiceV2 (SFCG-WSV2-01 / SFCG-WSV2-02)

```sql
DECLARE @CardNumber NVARCHAR(100) = @p0
DECLARE @UidCode NVARCHAR(100) = @p1
DECLARE @UidSerie NVARCHAR(100) = @p2
SELECT ai.FavoriteProduct, ai.AverageWeight, ai.LastBuyDate, a.Name AS FavoriteProductName
FROM [SmlSt].[CustomerAdditionalInformation] ai
LEFT JOIN [Sml].[Article] a ON TRY_CAST(ai.FavoriteProduct AS INT) = a.Id
WHERE ai.CardNumber = @CardNumber OR
(
    @UidCode IS NOT NULL
    AND @UidSerie IS NOT NULL
    AND LOWER(ai.UidCode) = LOWER(@UidCode)
    AND ai.UidSerie = @UidSerie
)
```

**Resultado de la prueba**

Ya creamos los índices faltantes sobre la tabla afectada. Al probarlos, confirmamos que por sí solos no alcanzan — la consulta necesita un ajuste adicional del lado de desarrollo para poder aprovecharlos. Probamos ese ajuste hoy contra datos reales de producción, comparando cuánto trabajo hace la base de datos con la consulta actual y con la consulta optimizada:

| Búsqueda | Consulta actual | Consulta optimizada |
|---|---|---|
| Por número de tarjeta | Recorre toda la tabla (~4,9 millones de registros) | Encuentra el registro directamente |
| Por código UID | Recorre toda la tabla (~4,9 millones de registros) | Encuentra el registro directamente |

En ambos casos, la consulta optimizada devolvió el resultado correcto haciendo más del 99,99% menos trabajo que la consulta actual.

**Próximos pasos**

Queda para el equipo de desarrollo aplicar la consulta optimizada.

Más información: [GITIN-2074](https://smartit-ar.atlassian.net/browse/GITIN-2074).

Saludos,
Dante
