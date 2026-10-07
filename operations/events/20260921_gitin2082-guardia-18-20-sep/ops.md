# GITIN-2082 — [OPE] Guardia 18-9 → 20-9

**Tags:** Operaciones, SRE

## Resumen

Ticket de agrupación: consolida los eventos reales atendidos durante la guardia del 18 al 20 de septiembre (incluye la madrugada del 21, continuación directa de uno de los eventos del 20). No reemplaza el detalle de cada evento — cada fila abajo referencia su propio ticket y carpeta de evento para el detalle completo.

## Eventos de la guardia

| Fecha | Proyecto | Evento | Descripción breve | Ticket |
|---|---|---|---|---|
| 18-9 | SmartCloud | Sales / Cosmos DB — 403 Forbidden | Bloqueo de firewall en la cuenta de Cosmos DB, IP de origen no habilitada | [GITIN-2083](https://smartit-ar.atlassian.net/browse/GITIN-2083) |
| 18-9 | SmartCloud | Sales-PRO — discrepancia de CPU (Azure Monitor vs. Live Metrics) | Verificación de una alerta de escalamiento real basada en CPU; se confirmó que la alerta y el grupo de acción funcionan correctamente | [GITIN-2085](https://smartit-ar.atlassian.net/browse/GITIN-2085) |
| 19-9 | SmartCloud | Onboarding de App Service Plan a Insights | Falta de Diagnostic Settings a nivel de Plan; el fix real probablemente es otro (autoscale por instancia) — pendiente de confirmar el enfoque antes de aplicar el cambio | [GITIN-2073](https://smartit-ar.atlassian.net/browse/GITIN-2073) |
| 19-9 | SmartCloud | Demoras en pedidos — Grido, sucursales Perú (5396/5481/5523) | Reclamo de demoras en la recepción de pedidos, relacionado con incidentes previos de la misma región | [GITIN-2084](https://smartit-ar.atlassian.net/browse/GITIN-2084) |
| 20-9 | SmartCloud | Sales-PRO — caídas recurrentes por OOM | Recurrencia de un patrón de septiembre; causa raíz (worker de 32 bits + pérdida de memoria real) confirmada, fix de 32 bits aplicado y verificado, pero una caída nueva post-cambio confirma que no alcanza solo — queda pendiente el patrón de consulta sin límite del lado de Dev | [GITIN-2075](https://smartit-ar.atlassian.net/browse/GITIN-2075) |
| 20-9 | SmartLoyalty | Picos de CPU en DB — Query101 | Consulta sin índices de soporte, recurrencia de un hallazgo de mayo; índices creados, reescritura de la consulta validada contra datos reales (más de 99,9% de mejora) y ya desplegada en ambos hosts. Pendiente crítico: commitear el cambio al control de versiones | [GITIN-2074](https://smartit-ar.atlassian.net/browse/GITIN-2074) (subtareas: [GITIN-2077](https://smartit-ar.atlassian.net/browse/GITIN-2077), [GITIN-2078](https://smartit-ar.atlassian.net/browse/GITIN-2078)) |
| 21-9 (madrugada) | SmartLoyalty | Bloqueo activo sobre CustomerPointsLog | Job de mantenimiento de índices bloqueado por una consulta ETL ya conocida y sin corregir, con impacto en tráfico real de MobileAppService y sitio de club. Resuelto con cancelación del job en cola; el riesgo de fondo (reprogramación y rebuild acotado a partición) sigue abierto por separado | [GITIN-2076](https://smartit-ar.atlassian.net/browse/GITIN-2076) |

## Excluido de este ticket

Una propuesta de diseño interna (índice de búsqueda local sobre archivos `investigation.md`) del 19-9 no se incluyó por no ser un evento/incidente de guardia — es trabajo de tooling interno, no una respuesta a un evento real.
