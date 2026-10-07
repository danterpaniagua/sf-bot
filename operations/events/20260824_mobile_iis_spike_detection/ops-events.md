# Eventos — 20260824_mobile_iis_spike_detection

## 2026-08-24 10:00 — Localización del trigger existente

**Comando:** C1, C2 — resolución de host y búsqueda de trigger
**Resultado:**
He confirmado que "Mobile 02" corresponde al host técnico `SFCG-MOBI-02` (hostid 10660) y "Mobile 01" a `SFCG-MOBI-01` (hostid 10659). He encontrado los tres triggers existentes sobre el ítem `perf_counter_en["\Web Service(_Total)\Total Method Requests/Sec", 60]` en ambos hosts (Warning/Average/High, triggerids 26133-26138), todos con umbral fijo sobre `avg(10m)`.

He verificado con `expandExpression` que el trigger Warning real es `avg(10m)>=9`, recuperación `avg(15m)<=7` — confirmando que las macros `{$PERF_COUNT_TRIG_*}` son globales, sin override a nivel host.

## 2026-08-24 10:30 — Análisis de historial para calibrar umbrales

**Comando:** C6, C7 — extracción de 14-16 días de historial (itemids 52755 y 52797)
**Resultado:**
He extraído y analizado el historial de ambos hosts. Mobile 02 muestra p95=9.7, p99=19.4, p99.9=74.1 req/s (máximo 177.4), con ráfagas reales de varios minutos que el trigger sostenido de 10 minutos captura pero con demora. Mobile 01 muestra un tráfico ~40x menor (p99=1.3 req/s), y su cobertura de muestras es 99.9% frente al 64.5% de Mobile 02 — confirmando que Mobile 02 no está encendido 24/7, con apagones nocturnos de 7.1 a 10.1 horas.

He verificado en `loyalty/docs/infrastructure.md` que ambos hosts están detrás del mismo Load Balancer `SFCG-MOBI-LB` y ambos están activos en el backend pool — la diferencia de tráfico responde a un patrón de uso distinto, no a un problema de enrutamiento.

## 2026-08-24 11:00 — Diseño e implementación de triggers de spike

**Resultado:**
He diseñado 6 triggers nuevos de detección rápida de ráfagas (ventana de 3 minutos, tres niveles de severidad Warning/Average/High) con umbrales calibrados por host a partir de los percentiles reales — macros `{$MOBILE_PCOUNT_SPIKE_*:MOBI01}` y `{$MOBILE_PCOUNT_SPIKE_*:MOBI02}` — más un trigger `nodata()` sobre Mobile 02 con ventana de 11 horas, calibrada por encima del apagón nocturno más largo observado (10.07h).

Quedaron creadas manualmente en la interfaz de Zabbix las 11 macros globales, los 6 triggers de spike y el trigger de `nodata`, con las dependencias entre ellos configuradas según el diseño (los niveles superiores de severidad y el trigger de `nodata` como raíz de la cadena, para Mobile 02).

## 2026-08-24 11:30 — Verificación de configuración

**Comando:** C3, C4, C5 — verificación de expresiones, macros y dependencias
**Resultado:**
He verificado con `expandExpression` que las 6 expresiones de spike y la expresión de `nodata` resuelven exactamente a los valores planificados, y que las dependencias quedaron configuradas según el diseño (los triggers de mayor severidad sin dependencias, los de menor severidad dependiendo de los superiores y del trigger de `nodata` en Mobile 02).

## 2026-08-24 12:00 — Alineación de tags de enrutamiento

**Comando:** C8, C9 — tags de referencia y revisión de acciones de alerta
**Resultado:**
He extraído el set de 10 tags del trigger de referencia "IIS More than {AVERAGE}..." (idéntico en Mobile 01, Mobile 02 y WSV2-01, confirmando que es una convención de flota). He revisado las 9 acciones de alerta configuradas y confirmado que solo 4 están habilitadas; la acción 10 ("Google Chat Loyalty to OPE (EMAIL)") es la que coincide con `scope=OPE` y `service_group=LOYALTY` de este set de tags.

## 2026-08-24 12:15 — Aplicación de tags

**Comando:** C10, C11 — actualización y verificación de tags
**Resultado:**
He aplicado el set completo de 10 tags a los 7 triggers nuevos (26742-26748) vía `trigger.update`, y he confirmado con `trigger.get` que los 7 quedaron con el set completo aplicado correctamente. El trabajo de detección de spikes en Mobile 01 y Mobile 02 queda cerrado.
