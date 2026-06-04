**Asunto:** Alertas de rendimiento en base de datos — 18 de mayo de 2026

---

Equipo,

El 18 de mayo de 2026 se registraron tres episodios de alta utilización del servidor de base de datos de SmartLoyalty, en los siguientes horarios (hora local): 08:00–09:00, 11:00–12:00 y 21:00–23:00.

Los episodios fueron originados por la consulta **Query101-sql.xml**, ejecutada desde el servidor **SFCG-WSV2-01** bajo la cuenta **SMARTIT\itservices**, correspondiente al componente WebServiceV2 (`D:\SmartLoyalty.WebServiceV2\bin\Domain\Query\Query101-sql.xml`). Dicha consulta accede a una tabla con aproximadamente 4,7 millones de registros sin la configuración de acceso adecuada:

```sql
SELECT ai.FavoriteProduct, ai.AverageWeight, ai.LastBuyDate, a.Name AS FavoriteProductName
FROM [SmlSt].[CustomerAdditionalInformation] ai
LEFT JOIN [Sml].[Article] a ON TRY_CAST(ai.FavoriteProduct AS INT) = a.Id
WHERE ai.CardNumber = @CardNumber
   OR (
        @UidCode  IS NOT NULL
    AND @UidSerie IS NOT NULL
    AND LOWER(ai.UidCode) = LOWER(@UidCode)
    AND ai.UidSerie = @UidSerie
      )
```

El equipo de Operaciones identificó la causa raíz y se encuentra trabajando en las correcciones necesarias.

Durante los eventos no se registraron errores de disponibilidad del servicio.

Dante Paniagua
SRE
