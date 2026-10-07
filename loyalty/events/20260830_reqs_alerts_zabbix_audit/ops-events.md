# Eventos — 20260830_reqs_alerts_zabbix_audit

## 2026-08-30 — Apertura de la auditoría, alcance definido

He confirmado que GITIN-1966 es hijo de GITIN-1965, desprendido de GITIN-1961 ese mismo día. He definido el alcance: revisar la eficiencia (no solo la existencia) de las alertas de tráfico Req/s en toda la flota Zabbix.

## 2026-08-30 — Inventario completo de triggers/tags en la flota

He ejecutado `trigger.get` a nivel flota, filtrado a hosts monitoreados reales, y he relevado 1.176 triggers en 22 hosts. He confirmado que, salvo `SFCG-WSCG-01`, el resto de la flota ya tenía triggers funcionales — he descartado la hipótesis inicial de que todos los hosts compartían el mismo gap de `WSCG-01`.

## 2026-08-30 — Corrección: los macros base sí estaban definidos

He re-ejecutado `usermacro.get` sin filtro (global y por host) y he confirmado que los macros base `PERF_COUNT_TRIG_*` sí estaban definidos, contradiciendo un chequeo filtrado previo (2026-08-28) que había dado un falso negativo. He dejado esta corrección registrada en `investigation.md`.

## 2026-08-30 — Mapeo de 4 generaciones de configuración en la flota

He mapeado 4 esquemas distintos de alertas de tráfico coexistiendo en la flota: macros base sin contexto, contexto compartido `CLUBS`, la familia `IIS_REQUESTS_WSV1_POST` compartida literalmente entre 4 hosts, y el contexto `WEBSCG01` recién creado en `GITIN-1961`. He identificado que `SFCG-MOBI-01`/`02` corren tres esquemas superpuestos simultáneamente sobre la misma métrica.

## 2026-08-30 — Confirmación del enrutamiento de alertas real

He confirmado, con `action.get`, que de todos los tags presentes en la flota, solo la combinación `scope:OPE` + `service_group:LOYALTY` + `action~MAIL` enruta alguna alerta habilitada actualmente.

## 2026-08-31 — Resolución del interrogante sobre la brecha de umbral Mobi01/Mobi02

He cruzado esta auditoría con el trabajo de línea base de tráfico hecho en GITIN-1965 (`operations/events/20260829_mobile_alerts_coverage_analysis/`) y he confirmado que la brecha de umbral ~13x entre `SFCG-MOBI-01` y `SFCG-MOBI-02` en el esquema `IIS Spike` es proporcional a la diferencia real de tráfico entre ambos hosts, no un error de copiado — he cerrado ese interrogante sin necesidad de ninguna acción.

## 2026-08-31 — Redacción del ticket como Story

He redactado `ops.md` para GITIN-1966 con formato de Story (criterios de aceptación y sub-tareas en vez de causa raíz/cierre de incidente), dado que este trabajo no se originó en una caída de servicio sino en una auditoría proactiva.
