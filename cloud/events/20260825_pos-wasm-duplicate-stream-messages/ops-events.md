# Eventos — 20260825_pos-wasm-duplicate-stream-messages

## 2026-08-25 — Apertura de investigación GITIN-1933

He abierto la investigación a partir del ticket GITIN-1933, que reporta mensajes duplicados de `smartfran-pos-wasm` en el Default Stream y en `PROD-Pos-AppServicePlan`. Como primera hipótesis, he vinculado este ticket con el trabajo previo de GITIN-1924 (mismo tráfico), donde las Pipeline Rules creadas usan `route_to_stream()` sin `remove_from_stream()` — esa investigación ya dejaba evidencia de doble membresía de stream sin marcarlo como problema.

## 2026-08-25 12:42 UTC — Confirmación de duplicación real en tráfico Production

**Comando:** C1 — Views Search API, mensajes recientes `smartfran-pos-wasm`/Production con campo `streams`
**Resultado:**
Cada `_id` muestreado aparece dos veces en el resultado, con idéntico `streams: ["000000000000000000000001","6a7cb1884814bcaed30a8744"]`, pero bajo dos índices distintos: `graylog_4` y `pos__1`.

He confirmado que la duplicación no es solo una cuestión de conteo por stream, sino una escritura física duplicada del mismo mensaje en dos índices distintos.

## 2026-08-25 — Confirmación del stream de destino

**Comando:** C2 — `GET /streams/6a7cb1884814bcaed30a8744`
**Resultado:**
`PROD-Pos-AppServicePlan`, `index_set_id: 6a7cb1874814bcaed30a873d`.

He confirmado que el stream involucrado es exactamente el que nombra el ticket.

## 2026-08-25 — Confirmación del texto vivo de las reglas de pipeline

**Comando:** C3 — `GET /system/pipelines/rule` (filtrado a reglas de GITIN-1924)
**Resultado:**
Ambas reglas (`6a8c60ae4814bcaed31a5560` DEV, `6a8c60bf4814bcaed31a559d` PROD) muestran `then: route_to_stream(name: "...")` sin ningún `remove_from_stream()`.

He confirmado la causa raíz contra el texto vivo de la regla, no solo contra lo documentado en la investigación de GITIN-1924.

## 2026-08-25 12:45 UTC — ⚠️ Fix aplicado a la regla DEV

**Comando:** C4 — `PUT /system/pipelines/rule/6a8c60ae4814bcaed31a5560`
**Resultado:**
`modified_at: 2026-08-25T12:45:44.302Z`, `errors: null`, `source` ahora incluye `remove_from_stream(id: "000000000000000000000001")` después de `route_to_stream(name: "DEV")`.

He aplicado el fix a la regla DEV, decidido junto con la regla PROD para cubrir el mismo defecto estructural en ambas reglas.

## 2026-08-25 12:46 UTC — ⚠️ Fix aplicado a la regla PROD

**Comando:** C5 — `PUT /system/pipelines/rule/6a8c60bf4814bcaed31a559d`
**Resultado:**
`modified_at: 2026-08-25T12:46:28.744Z`, `errors: null`, `source` ahora incluye `remove_from_stream(id: "000000000000000000000001")` después de `route_to_stream(name: "PROD-Pos-AppServicePlan")`.

He aplicado el fix a la regla PROD, que es la reportada explícitamente en GITIN-1933.

## 2026-08-25 12:47 UTC — Verificación en tráfico real post-fix (PROD)

**Comando:** C6 — Views Search API, `smartfran-pos-wasm` desde `2026-08-25T12:46:28.744Z`
**Resultado:**
10 mensajes muestreados (de 38 en la ventana), todos `Environment:"Production"`, cada uno con `_id` único, `streams: ["6a7cb1884814bcaed30a8744"]` (sin Default Stream), `index: "pos__1"` únicamente.

He verificado el fix contra tráfico real posterior al cambio, no solo contra el texto de la regla — confirmado que el lado PROD ya no duplica.

## 2026-08-25 13:05 UTC — Verificación en tráfico real post-fix (DEV)

**Comando:** C7 — Views Search API, `smartfran-pos-wasm AND Environment:"Development"` desde `2026-08-25T12:45:44.302Z`
**Resultado:**
Primer intento (13:02 UTC) sin resultados (`total_results: 0`, tráfico DEV es de bajo volumen). Segundo intento (13:05 UTC) con 10 mensajes muestreados (de 32 en la ventana), cada uno con `_id` único, `streams: ["6a7a1b8a34e7b9a985f43cbc"]` (sin Default Stream), `index: "dev__6"` únicamente.

He verificado el fix también en el lado DEV contra tráfico real, quedando confirmados ambos lados de la corrección.

## 2026-08-25 — Cierre: redacción del reporte de cierre

He redactado `ops.md` como reporte de cierre de GITIN-1933, con causa raíz, hallazgos, recursos afectados y acciones completadas/verificadas. He dejado explícito como pendiente sin decidir la limpieza de los documentos duplicados históricos (previos al fix), sin darlo por resuelto.
