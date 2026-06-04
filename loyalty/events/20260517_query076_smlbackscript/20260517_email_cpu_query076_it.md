# Email — Reporte de Incidente

**Para:** IT / Infraestructura
**De:** Dante Paniagua, SRE
**Fecha:** 2026-05-17
**Asunto:** [PERF] SendCanjesSocioCortesiaToBlobStorage — Query076 genera ~700 seg de CPU por ejecución sobre SFCG-DB01

---

Equipo,

Desde las 08:00 UTC-3 de hoy, Zabbix reporta picos de CPU de ~40% sobre `SFCG-DB01` con cadencia de 30 minutos. La investigación identifica como causa la Scheduled Task `SendCanjesSocioCortesiaToBlobStorage` (`SmartLoyalty.SmlBackScript`) ejecutando `Query076-sql.xml`.

---

## Contexto del job

La tarea extrae canjes de socios con puntos de cortesía y los escribe en Azure Blob Storage. Corre cada 30 minutos desde las 11:00 UTC durante 16 horas, totalizando 32 ejecuciones diarias.

## Problema

Cada ejecución de Query076 acumula **~700 segundos de CPU**, generando los picos detectados por Zabbix. Con 32 ejecuciones diarias, el impacto total es de ~22.400 segundos de CPU por día atribuibles exclusivamente a este job.

La causa son dos problemas en la query:

- **Fecha estática desde 2023** — cada ejecución escanea más de 3 años de registros, con un volumen que crece día a día.
- **Patrón de filtrado ineficiente** — la forma en que se identifican los clientes sospechosos fuerza una evaluación costosa en cada una de las 32 ejecuciones diarias.

| Ventana (GMT) | CPU por ejecución |
|---|---|
| 11:30 | 701.207 ms |
| 12:00 | 703.201 ms |
| 13:00 | 700.379 ms |
| 13:30 | 696.907 ms |
| 14:30 | 700.140 ms |

## ✅ Resolución aplicada

Se optimizó `Query076-sql.xml` corrigiendo el patrón de filtrado. La duración por ejecución se redujo de **1 minuto 5 segundos a 2 segundos** (reducción del 97%), con el mismo resultado de 18.422 filas.

El archivo actualizado está disponible para ser desplegado en `SFCG-TO-01`.

## Observación adicional

Independientemente de Query076, se observa concurrencia creciente de `Query101-sql.xml` desde `SFCG-WSV2-01` a partir de las 12:30 GMT. Se reporta por separado.

---

Dante Paniagua
SRE — SmartLoyalty
