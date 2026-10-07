# 20260908_gitin2013-query-insights-slow-queries

**Tags:** SmartPedidos, MongoDB, Concentrador, Platform

## Resumen

Atlas Query Insights reportó consultas lentas sobre el cluster `PedidosSmartfran` (base `smartfran`), sin causa conocida al momento de abrir el ticket. La investigación identificó tres causas independientes: un patrón de conteo total sin filtro sobre `news` (repetido varias veces en pocas horas), un pipeline de búsqueda sobre `branches` que ejecuta `$lookup` antes de aplicar el filtro real de búsqueda (señalado directamente por Atlas), y un trigger de Atlas App Services (`clearCollection`, no documentado previamente en este repositorio) que corre diariamente 7 operaciones `deleteMany()` sin batching sobre distintas colecciones, explicando los picos de latencia de escritura observados.

## Tabla resumen

| Campo | Valor |
|---|---|
| Ticket Jira | [GITIN-2013](https://smartit-ar.atlassian.net/browse/GITIN-2013), parent [GITIN-1857](https://smartit-ar.atlassian.net/browse/GITIN-1857) |
| ID alerta | Atlas Query Insights (múltiples entradas) |
| Sistema | MongoDB Atlas — cluster `PedidosSmartfran`, base `smartfran`, `us-east-1` |
| Severidad | Media — degradación de performance, sin caída de servicio |
| Detectado | 2026-09-08 |
| Resuelto | Parcial — causas raíz identificadas; un ajuste operativo ya aplicado (horario del trigger); cambios de código pendientes de Desarrollo |
| Responsable | SRE |

## Causa raíz

No hay una única causa: (1) el conteo total de `news` usa `aggregate()`/`countDocuments()` sin filtro, forzando un escaneo completo de la colección en cada llamada; (2) la búsqueda de `branches` aplica el filtro real de búsqueda después de dos `$lookup`, haciendo que ambos joins corran sobre miles de documentos innecesarios; (3) el trigger `clearCollection` ejecuta 7 `deleteMany()` secuenciales y sin batching todos los días, generando picos de latencia de escritura en las colecciones que procesa.

## Hallazgos

| # | Hallazgo | Riesgo |
|---|---|---|
| H1 | `news`: patrón repetido de conteo total sin filtro (`{$match:{}}, {$group:{_id:1,n:{$sum:1}}}`, equivalente a `countDocuments()` sin filtro) — 4 ocurrencias observadas en pocas horas (925 ms a 11.01 s), examinando prácticamente toda la colección (~395K–432K documentos) cada vez. Confirmado contra `develop`: función `search` (`POST /news/search`), `news.js:71-195` — código en detalle más abajo | Medio |
| H2 | `branches`: pipeline de búsqueda ejecuta `$lookup` a `chains` y `clients` antes de aplicar el filtro real de búsqueda (segundo `$match`) — señalado directamente por Atlas ("$lookup usage detected... consider restructuring"). 500 ms, 7.047 documentos examinados. Confirmado contra `develop`: función `search` (`POST /branches/search`), `branch.js:4138-4259` — código en detalle más abajo | Bajo/Medio |
| H3 | Trigger `clearCollection` (Atlas App Services, no documentado previamente en este repositorio) ejecuta 7 `deleteMany()` secuenciales sin batching sobre `orders`, `news`, `ordersFaileds`, `logerrors`, `openclosedlogs`, `rejectpeyas` y `ordertimes`, todos los días. Explica los picos de latencia de escritura observados (`orders` promedio 8.88 s, `ordertimes` 5.73 s, `news` 2.72 s) | Medio |
| H4 | Horario del trigger `clearCollection` modificado de `08 13 * * *` a `08 10 * * *` (13:08 UTC / 10:08 ART → 10:08 UTC / 07:08 ART) durante esta investigación. Motivo confirmado: a las 10:08 ART hay riesgo de superposición con el cron de Concentrador y con sesiones/deploys activos del frontend POS de sucursales; a las 07:08 ART no hay chance de un deploy en curso ni de una sucursal con el POS abierto | Resuelto/Aplicado |
| H5 | `ordertimes` en el trigger reutiliza la variable de fecha declarada para `openclosedlogs` en vez de tener la propia — mismo valor funcional (-15 días), es un problema de mantenibilidad, no un bug de comportamiento | Bajo |
| H6 | Discrepancia sin resolver: la consulta de `branches` examinó 7.047 documentos, contra 2.361 registrados en el inventario de GITIN-2006 unas horas antes, mismo día — no explicada | Bajo — no accionable sin más datos |

## Código relevante

Extraído de `dev-src-smartPedidos-concentradorService`, rama `develop` (pulled 2026-09-08, `9704315b..01733d90`).

### H1 — `news.js`, conteo sin filtro

Filtro `data` armado con spreads condicionales (`api/src/controllers/news.js:103-146`, extracto):

```js
const data = {
  ...(search != '' ?  { 'order.originalId': search } : {}),
  ...(platform != '' ? { 'order.platformId':{ $in: platform } } : {}),
  ...(chain != '' ? { 'extraData.chain': { $in: chain }  } : {}),
  ...(status != '' ? {
      $or: [
        ...(types.length > 0 ? [{ typeId: { $in: types } }] : []),
        ...(orderStatus.length > 0 ? [{ 'order.statusId': { $in: orderStatus } }] : [])
      ]
    } : {}),
  ...(branch != '' ? { branchId: branch } : {}),
  // ...spreads adicionales, todos con el mismo patrón: un parámetro
  // vacío/default aporta {} al filtro.
};
```

Cada condición colapsa a `{}` cuando el parámetro correspondiente está vacío o es el default. Sin criterios de búsqueda, `data` queda literalmente `{}`.

Llamada al conteo (`api/src/controllers/news.js:193-195`):

```js
model
  .find(data, { 'order.id': true })
  .countDocuments()
  .then((length) => {
    // ...lógica de paginación usando `length`
  });
```

Con `data` vacío, esto se traduce internamente en `aggregate([{ $match: {} }, { $group: { _id: 1, n: { $sum: 1 } } }])` — exactamente lo capturado por Atlas Query Insights.

**Fix sugerido:** ramificar según si `data` queda vacío y usar `estimatedDocumentCount()` en ese caso, en vez de `.find(data, ...).countDocuments()`.

### H2 — `branch.js`, `$lookup` antes del filtro real

`api/src/controllers/branch.js:4206-4254`:

```js
const data = await model
  .aggregate([
    { $match: { deletedAt: null } },
    {
      $lookup: {
        from: 'chains',
        localField: 'chain',
        foreignField: '_id',
        as: 'chain'
      }
    },
    {
      $lookup: {
        from: 'clients',
        localField: 'client',
        foreignField: '_id',
        as: 'client'
      }
    },
    {
      $project: {
        id: '$_id',
        branchId: '$branchId',
        branchIdReference: '$platforms.branchIdReference',
        branchReference: '$platforms.branchReference',
        // ...resto de campos proyectados
      }
    },
    { $match: dataSearch },   // <-- filtro real, aplicado DESPUÉS de los $lookup
    { $sort: { [sort]: order } }
  ])
  .facet({
    pagination: [{ $count: 'length' }],
    data: [{ $skip: (page - 1) * size }, { $limit: size }]
  });
```

`dataSearch` (armado en las líneas 4165-4204) es donde viven `branchReference`/`branchIdReference` y el resto de los criterios reales de búsqueda — pero se aplica recién en el segundo `$match`, después de ambos `$lookup` y del `$project`. Todo documento que matchea el `$match` inicial (`deletedAt: null`, prácticamente toda la colección) se joinea contra `chains` y `clients` antes de que el filtro real descarte nada.

**Fix sugerido:** separar `dataSearch` entre lo que puede correr contra campos propios de `branches` (mover al primer `$match`, antes de los `$lookup`) y lo que realmente depende de los campos joineados (eso sí debe quedar después). Si ningún criterio de `dataSearch` depende de datos joineados — probable, dado que `branchReference`/`branchIdReference` son campos nativos de `branches` — todo el filtro puede moverse antes de ambos `$lookup`.

## Recursos afectados

| Componente | Impacto |
|---|---|
| Concentrador | Endpoint de paginación de `news` — candidato del patrón de conteo sin filtro; endpoint de búsqueda de `branches` con el pipeline `$lookup` |
| Platform | Comparte las colecciones (`news`, `orders`, `ordertimes`) afectadas por el trigger de limpieza |
| MongoDB Atlas App Services | Trigger `clearCollection` — ejecución diaria, 7 colecciones, sin batching |

## Comandos ejecutados

| # | Comando / Script | Propósito |
|---|---|---|
| C1 | `scripts.js` → `data/slow-queries-20260908.txt` | Intento de verificar `getProfilingStatus()`/`system.profile`/`currentOp()` vía mongosh — las 3 verificaciones fueron denegadas (`Unauthorized`) |
| C2 | Atlas Query Insights — 5 "Query Details" individuales | `data/query-insights-news-count-20260908.txt`, `-2-`, `-3-`, `-4-`, `data/query-insights-branches-lookup-20260908.txt`, `data/query-insights-news-trigger-cleanup-20260908.txt` |
| C3 | Atlas Query Insights — panel "Top namespace operations" | `data/query-insights-top-namespaces-20260908.txt` |
| C4 | Atlas App Services — lista de Triggers | `data/app-services-triggers-list-20260908.txt`, `-2-` (post-cambio de horario) |
| C5 | Atlas App Services — código fuente del trigger `clearCollection` | `data/clearCollection-trigger-source-20260908.txt` |

## Acciones propuestas

1. (Dev) En `news.js:193-195` (`develop`), reemplazar `.countDocuments()` por `estimatedDocumentCount()` cuando `data` resulta `{}` (sin criterios de búsqueda aplicados).
2. (Dev) En `branch.js:4206-4254` (`develop`), reestructurar el pipeline de búsqueda de `branches` para aplicar el `$match: dataSearch` (línea 4248, el filtro real con `branchReference`/`branchIdReference`) antes de los dos `$lookup` (4209-4224), no después.
3. (SRE/Dev) Agregar batching/throttling a los 7 `deleteMany()` del trigger `clearCollection`, y corregir la variable de fecha duplicada usada para `ordertimes` (usar una propia, aunque el valor resultante sea el mismo).
4. ~~(SRE) Confirmar la motivación real detrás del cambio de horario de `clearCollection`~~ — confirmado, ver H4.
5. (SRE) Si la discrepancia de conteo de `branches` (H6) reaparece, investigarla — no bloqueante para este ticket.

## Hallazgos secundarios

- El segundo trigger de Atlas App Services, `sendMailBranchReject` (cada minuto), está `Disabled` — no contribuye a la carga actual, mencionado solo por aparecer en el mismo listado.
