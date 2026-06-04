# Email — Reporte de Hallazgo

**Para:** IT / Desarrollo — SmartLoyalty.WebServiceV2
**De:** Dante Paniagua, SRE
**Fecha:** 2026-05-17
**Asunto:** [PERF] Query101 — WebServiceV2 — concurrencia creciente sobre SFCG-DB01

---

Equipo,

Durante la investigación de los picos de CPU del día de hoy en `SFCG-DB01`, se identificó un hallazgo de performance en `Query101-sql.xml` (`SmartLoyalty.WebServiceV2`, `SFCG-WSV2-01`).

---

## Hallazgo

La query consulta `SmlSt.CustomerAdditionalInformation` para obtener producto favorito y promedio de consumo por cliente. Genera concurrencia creciente sobre el servidor de base de datos a partir de las 12:30 GMT, con entre 6 y 8 ejecuciones simultáneas acumulando CPU de forma sostenida.

**Hits a BD y CPU por ventana de 30 minutos:**

| Ventana (GMT) | Hits (SPIDs) | CPU total | CPU máx por SPID |
|---|---|---|---|
| 13:00 | 1 | 4.000 ms | 4.000 ms |
| 13:30 | 2 | 7.905 ms | 4.248 ms |
| 14:00 | 3 | 10.686 ms | 4.298 ms |
| 14:30 | 7 | 32.393 ms | 4.390 ms |
| 15:00 | 5 | 21.500 ms | 4.655 ms |
| 15:30 | 8 | 41.243 ms | 8.579 ms |
| 16:00 | 7 | 34.790 ms | 7.860 ms |
| 16:30 | 6 | 30.257 ms | 8.584 ms |
| **Total** | — | **~182 seg** | — |

## Causa

La query contiene tres patrones que impiden el uso eficiente de índices:

1. **Condición OR en el filtro principal** — fuerza un escaneo completo de la tabla en cada llamada, en lugar de una búsqueda directa por índice.
2. **Función aplicada sobre columna indexada** — impide que el motor use el índice existente en el campo de tipo de documento.
3. **Conversión de tipo en el JOIN** — el campo de producto favorito está almacenado en un tipo de dato incorrecto, requiriendo una conversión en cada fila procesada.

## Acciones recomendadas

- Revisar la estructura del filtro principal para eliminar la condición OR y permitir búsquedas por índice en cada rama de forma independiente.
- Corregir el almacenamiento del campo de producto favorito para evitar conversiones en tiempo de ejecución.
- **Crear índices faltantes sobre `SmlSt.CustomerAdditionalInformation`** — confirmado que no existen índices sobre `CardNumber`, `UidCode` ni `UidSerie`. Actualmente cada llamada realiza un escaneo completo de la tabla (25.833 scans registrados hoy, 0 búsquedas directas por PK). La creación de índices sobre esos tres campos es la acción de mayor impacto inmediato, independientemente de la optimización del filtro OR.

Contactos de referencia: Juan Cruz Breppe (autor del archivo), FedericoL (última modificación 11/02/2026).

---

Dante Paniagua
SRE — SmartLoyalty
