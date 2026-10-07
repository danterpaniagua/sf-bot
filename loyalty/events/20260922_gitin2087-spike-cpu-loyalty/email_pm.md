**Asunto:** GITIN-2087 — Pico de CPU en SmartLoyalty (WebService) — causa raíz identificada

Hola [PM],

El 2026-09-21 se detectó un pico de CPU en el servidor de base de datos de SmartLoyalty, originado en los tres servidores de WebService (v1). No se reportó caída del servicio, pero el consumo de CPU se mantuvo elevado durante aproximadamente una hora.

Se identificó la causa raíz: una consulta de la aplicación que trae el listado completo de promociones activas sin paginado, lo que genera que el servidor de base de datos quede esperando mientras la aplicación procesa un resultado más grande de lo necesario. Esta consulta específica es:

```sql
SELECT [Project1].[Id], [Project1].[Name], [Project1].[Description], [Project1].[Points], ...
FROM [Sml].[Promotion] AS [Extent1]
WHERE (@p0 = 1) AND ([Extent1].[ActivatedDate] IS NOT NULL) AND ([Extent1].[DeactivatedDate] IS NULL) AND (@p1 <= [Extent1].[ValidToDate])
```

**Origen:** servidor `SFCG-WEBS-03`, aplicación `.Net SqlClient Data Provider`, usuario de conexión `SMARTIT\itservices`.

El mismo patrón se repitió la noche siguiente (2026-09-22), lo que sugiere que no es un evento aislado, aunque todavía no está confirmado si ocurre todos los días.

**Próximos pasos:**
- Desarrollo debe ajustar esta consulta para que traiga los resultados de forma paginada en lugar de todo el listado completo de una vez. La causa ya está identificada a nivel de código, por lo que el trabajo puede comenzar sin investigación adicional.

Más información en el ticket: [GITIN-2087](https://smartit-ar.atlassian.net/browse/GITIN-2087)

Saludos,
Dante
