Asunto: Pico de uso de base de datos — 15/07 (actualización)

Hola equipo,

Les había comentado sobre un evento que detectamos en la base de datos de SmartLoyalty el 15/07. Les escribo con una actualización, porque al profundizar la investigación identificamos que la causa no fue la que pensábamos inicialmente.

Durante la tarde del 15/07 el servidor de base de datos tuvo un uso de CPU elevado (por encima del 70%) sostenido durante aproximadamente dos horas, a partir de las 17:00 hs. En un primer momento pensamos que esto estaba relacionado con la campaña push de Grido enviada ese mismo día, por la coincidencia de horarios. Al revisar en detalle, confirmamos que no fue así: el volumen que generó el pico no correspondía a la campaña.

La causa real fue un reinicio del servidor esa madrugada, que hizo que una tarea interna de sincronización de datos (que normalmente corre de madrugada, en un horario de bajo uso) se reprogramara y terminara ejecutándose esa misma tarde en su lugar. Esa tarea ya tenía un margen de mejora pendiente en su rendimiento — algo que veníamos notando pero que, al correr siempre de madrugada, no generaba impacto visible. Al correr esa tarde, ese margen de mejora se hizo notar en forma de uso elevado de CPU.

No se registraron bloqueos ni afectación a los servicios de cara al socio (app, web, canje) durante el evento; el impacto se limitó al uso de CPU del servidor de base de datos.

Aparte de este evento puntual: el impacto propio de los envíos push sobre la base de datos es bajo. Excluyendo lo ocurrido el 15/07, los picos de uso durante las campañas se mantuvieron por debajo del 50%, con un promedio de 25%. Por ahora no es necesario duplicar la base de datos para el fin de semana, aunque puede hacerse de todos modos si se prefiere contar con ese resguardo adicional.

## Próximos pasos

Estamos trabajando en una optimización de esa tarea de sincronización para que, incluso si en el futuro se reprograma o corre en un horario distinto al habitual, no genere el mismo nivel de impacto.

Quedo a disposición por cualquier consulta adicional.

Saludos,
Dante

---

## Detalle técnico

**Origen de la consulta responsable:**

| Campo | Valor |
|---|---|
| Host | `SFCG-TO-01` |
| Programa | `.Net SqlClient Data Provider` |
| Login | `sfsqlusr` |

**Consulta:**

```sql
SELECT cpl.Id as CustomerPointsLogId
      ,EventTypeCode
      ,CustomerId
      ,LogDate
      ,Points
      ,SYSDATETIMEOFFSET() as _SyncDate
FROM Sml.CustomerPointsLog cpl (nolock)
INNER JOIN Sml.Customer c (nolock) ON cpl.CustomerId = c.Id
WHERE
    (
        (@LowerBoundary IS NULL OR c.CreatedDate >= @LowerBoundary)
        AND c.CreatedDate < @UpperBoundary
        AND cpl.LogDate < @UpperBoundary
    )
    OR
    (
        (@LowerBoundary IS NULL OR cpl.LogDate >= @LowerBoundary)
        AND cpl.LogDate < @UpperBoundary
        AND (@LowerBoundary IS NULL OR c.CreatedDate < @LowerBoundary)
    )
ORDER BY cpl.Id
```
