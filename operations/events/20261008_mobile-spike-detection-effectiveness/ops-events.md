# Eventos — 20261008_mobile-spike-detection-effectiveness

## 2026-10-08 17:07 — Extracción de Zabbix de la ventana 14:00–15:00 (UTC-3)

**Comando:** C1 — Extracción de triggers, eventos, alertas e historial (`scripts.sh`)
**Resultado:**
Cero eventos y cero intentos de notificación para los 7 triggers (26742–26747 y 26898) entre las 13:30 y las 15:30. Serie de SFCG-MOBI-02: mediana 5,2 req/s y una muestra de 144,2 req/s a las 14:24:15, entre 3,4 y 5,7. Promedios móviles con las ventanas documentadas: 25,3 (10 min), 34,7 (5 min) y 51,4 (3 min), contra umbrales de 45, 75 y 100. Salidas en `data/`.

He verificado que el pico fue una sola muestra de un minuto que el promedio de cada nivel absorbe, por lo que ningún trigger podía dispararse con la regla vigente.

## 2026-10-08 17:10 — Día completo y 14 días de historial

**Comando:** C1 — Extracción de triggers, eventos, alertas e historial (`scripts.sh`, rangos `run2-dia` y `run3-14d`)
**Resultado:**
El máximo del día es 144,2 req/s (MOBI-02, 14:24:15), la siguiente muestra es 33,7 y no hay ninguna de 200 o más. En 14 días: 78 eventos (39 problemas) entre el 09-25 y el 09-29, ninguno desde entonces y ninguno con intento de notificación. El 09-29 hubo muestras de 71, 142, 93 y 69 req/s. Salidas en `data/run2-dia/` y `data/run3-14d/`.

He comprobado que los eventos del 09-25 al 09-29 se dispararon con promedios de 3 minutos de 20 a 29 req/s y de 5 minutos de 29 a 31 req/s, por debajo de los umbrales actuales, de modo que con las reglas de hoy esos eventos no existirían. Eso indica que el reajuste del 2026-10-02 redujo la sensibilidad a ráfagas de uno a pocos minutos; no he leído los valores anteriores.

## 2026-10-08 17:18 — Valores vigentes de las macros

**Comando:** C1 — Extracción de macros (`scripts.sh`, `ONLY_MACROS=1`)
**Resultado:**
Macros globales sin sobrescrituras en host ni plantilla: `{$MOBILE_PCOUNT_SPIKE_WARN|AVG|HIGH|OK:MOBI}` = 45/75/100/40 y `{$MOBILE_PCOUNT_SPIKE_TIME_WARN|AVG|HIGH|OK}` = 10m/5m/3m/20m. Colapso: `ABS` 0,2, `MINCOUNT` 15, `MINVAL` 1, `PRESENT` 25, `WINDOW` 5m, `RECWIN` 3m, `REC` 1. Salida en `data/macros/`.

He confirmado que la configuración vigente coincide con la documentada, por lo que los replays usan los valores que están en vigor.

## 2026-10-08 17:32 — Creación de macros y triggers "IIS Spike - Burst"

**Comando:** C2 — Crear macros y triggers del detector de ráfagas (`scripts-burst-apply.sh`) ⚠️
**Resultado:**
Las guardas pasaron antes de escribir. Macros globales creadas con ids 128 (`{$MOBILE_PCOUNT_BURST:MOBI}` = 60) y 129 (`{$MOBILE_PCOUNT_BURST_TIME}` = 5m). Triggers 26909 (SFCG-MOBI-01) y 26910 (SFCG-MOBI-02): prioridad Average, habilitados, soportados, sin error y con 12 tags copiados del trigger 26744. Ambos quedaron en estado OK. Salidas en `data/burst-apply/`.

He creado un detector que dispara con una sola muestra de 60 req/s o más y se recupera cuando el máximo de 5 minutos baja de 40 req/s. En un replay sobre 14 días da 6 problemas, todos en los dos días con ráfagas. No he ejecutado la reversa (`scripts-burst-rollback.sh`).

## 2026-10-08 17:36 — Configuración de la acción 7 y envíos desde el 2026-10-02

**Comando:** C4 — Lectura de la acción 7 (`scripts-action7.sh`)
**Resultado:**
Acción 7 habilitada con filtro `scope = GIT-SML-OPE` y `action ~ GCHAT` y (`service_group` LOYALTY o CLOUD); un solo paso sin escalamiento, un mensaje al usuario 9 por el medio 38, más un mensaje de recuperación y uno de actualización al mismo usuario. 16 envíos desde el 10-02, todos en estado enviado, sin reintentos ni errores (8 problemas con su recuperación). Los triggers 26909 y 26910 cumplen las tres condiciones del filtro. Salidas en `data/action7/`.

He confirmado que el detector de ráfagas se enruta a la acción 7 y que genera un mensaje al abrirse, uno al recuperarse y otro si alguien lo reconoce. No he identificado qué trigger originó el envío de las 14:40 del 10-08 (evento 715395).
