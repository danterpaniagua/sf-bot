# GITIN-1918 — Detección de ráfagas de tráfico IIS en Mobile 01/02 (MobileAppService)

**Tags:** SmartLoyalty, MobileAppService, Obserbavilidad, PROD, SRE

## Resumen

Los triggers de Zabbix existentes sobre `\Web Service(_Total)\Total Method Requests/Sec` en `SFCG-MOBI-01` y `SFCG-MOBI-02` (MobileAppService, detrás del Load Balancer `SFCG-MOBI-LB`) evaluaban únicamente un promedio sostenido de 10 minutos, lo que introduce una demora real en la detección de ráfagas de tráfico de arranque rápido — una ráfaga necesita varios minutos sostenidos por encima del umbral antes de que el promedio de 10 minutos lo refleje. Adicionalmente, `SFCG-MOBI-02` no permanece encendido 24/7 (a diferencia de `SFCG-MOBI-01`) y no contaba con ningún trigger de `nodata()` que detectara una falla al reencender tras su ciclo habitual de apagado. Se diseñaron y crearon 6 triggers nuevos de detección rápida de ráfagas (ventana de 3 minutos, tres niveles de severidad, calibrados por host a partir de 16 días de historial real) y 1 trigger de `nodata()` en Mobile 02, con sus dependencias y tags de enrutamiento configurados.

## Tabla resumen

| Campo | Valor |
|---|---|
| Ticket Jira | GITIN-1918 |
| ID alerta | N/A — mejora proactiva de monitoreo, no originada por una alerta puntual |
| Sistema | SmartLoyalty MobileAppService (`SFCG-MOBI-01`, `SFCG-MOBI-02`) |
| Severidad | Media — mejora de observabilidad, no hubo caída de servicio |
| Detectado | N/A — trabajo proactivo |
| Resuelto | 2026-08-24 |
| Responsable | Dante Paniagua |

## Causa raíz

El trigger sostenido (`avg(10m)>=9/13/15`, macros `{$PERF_COUNT_TRIG_*}` globales sin distinción por host) captura la mayoría de las ráfagas grandes porque una sola muestra muy alta puede arrastrar el promedio de una ventana corta por encima del umbral, pero requiere varios minutos de tráfico sostenidamente alto antes de que el promedio de 10 minutos lo refleje — la demora de detección es el problema, no la cobertura. Por separado, `SFCG-MOBI-02` mostró solo 64,5% de cobertura de muestras en 14 días (frente a 99,9% de `SFCG-MOBI-01`), con apagones nocturnos recurrentes de 7,1 a 10,1 horas — sin un trigger de `nodata()` calibrado a ese patrón, una falla al reencender tras el ciclo nocturno no generaría ninguna alerta.

## Hallazgos

| # | Hallazgo | Riesgo |
|---|---|---|
| H1 | El trigger sostenido de 10 minutos ya cubre casi todas las ráfagas grandes, pero con demora de varios minutos respecto al inicio real de la ráfaga | Medio |
| H2 | Mobile 01 y Mobile 02 tienen perfiles de tráfico ~40x distintos (p99 de 3m-avg: 1,22 vs 18,99 req/s) — un umbral de spike compartido habría dejado a Mobile 01 sin cobertura real | Alto |
| H3 | Mobile 02 no está encendido 24/7 y no contaba con trigger de `nodata()` — una falla de reencendido tras el apagado nocturno no generaba alerta | Medio |
| H4 | El ciclo de apagado/encendido de Mobile 02 no está confirmado como programado o manual (mismo punto abierto en GITIN-1909, investigación de carga del 2026-08-21) — la ventana de `nodata()` (11h) se calibró de forma empírica sobre el historial, no contra un horario conocido | Bajo |
| H5 | El SKU/tamaño de VM de `SFCG-MOBI-01` y `SFCG-MOBI-02` no está documentado en `loyalty/docs/infrastructure.md` | Bajo |

## Recursos afectados

| Recurso | Detalle |
|---|---|
| Host | `SFCG-MOBI-01` (Mobile 01) |
| Host | `SFCG-MOBI-02` (Mobile 02) |
| Ítem Zabbix | `perf_counter_en["\Web Service(_Total)\Total Method Requests/Sec", 60]` en ambos hosts |
| Macros nuevas | 11 macros globales `{$MOBILE_PCOUNT_SPIKE_*}` / `{$MOBILE_PCOUNT_NODATA_WINDOW:MOBI02}` |
| Triggers nuevos | 26742–26744 (Mobile 01, spike Warning/Average/High), 26745–26747 (Mobile 02, spike Warning/Average/High), 26748 (Mobile 02, `nodata`) |

## Comandos ejecutados

| # | Comando / Script | Propósito |
|---|---|---|
| C1 | Resolución de host "Mobile" | Confirmar hostid/nombre técnico |
| C2 | Búsqueda de triggers "Method Total requests per second" | Localizar triggers existentes en toda la flota |
| C3 | `trigger.get` con `expandExpression` | Decodificar la expresión real del trigger sostenido de Mobile 02 |
| C4 | `usermacro.get` a nivel host | Confirmar que las macros del trigger sostenido son globales |
| C5 | `host.get` con `selectParentTemplates`/`selectMacros` | Confirmar que ambos hosts solo enlazan templates de fábrica |
| C6 | `history.get` 14 días, Mobile 02 | Calibrar umbrales de spike y ventana de `nodata` |
| C7 | `history.get` 14 días, Mobile 01 | Validar que el mismo umbral no aplica a Mobile 01 |
| C8 | `trigger.get` con `selectTags` sobre trigger de referencia | Obtener el set de tags de enrutamiento de la flota |
| C9 | `action.get` con `selectFilter`/`selectOperations` | Confirmar qué acción de alerta realmente enruta este set de tags |
| C10 | ⚠️ `trigger.update` — aplicar tags a los 7 triggers nuevos | Habilitar el enrutamiento de alertas |
| C11 | `trigger.get` con `selectTags` | Confirmar que los 7 triggers quedaron con el set completo |

Detalle completo en `scripts.sh`. La creación de las 11 macros y los 7 triggers en sí (incluyendo dependencias) se realizó manualmente en la interfaz de Zabbix, no vía API.

## Acciones propuestas

1. **(SRE) Completado** — Diseño y creación de 6 triggers de detección rápida de ráfagas (ventana de 3 minutos, niveles Warning/Average/High) en Mobile 01 y Mobile 02, con umbrales calibrados por host a partir de percentiles reales de 16 días de historial.
2. **(SRE) Completado** — Creación de trigger `nodata()` en Mobile 02 (ventana de 11h, por encima del apagón nocturno más largo observado) para detectar una falla de reencendido.
3. **(SRE) Completado** — Configuración de dependencias entre los 7 triggers nuevos (niveles superiores de severidad y el trigger de `nodata` como raíz de la cadena en Mobile 02) para evitar alertas apiladas por una misma causa.
4. **(SRE) Completado** — Aplicación del set de tags de enrutamiento existente (idéntico al de los triggers sostenidos ya en producción) a los 7 triggers nuevos; confirmado el enrutamiento vía la acción "Google Chat Loyalty to OPE (EMAIL)".
5. **(SRE) Pendiente** — Confirmar si el ciclo de apagado/encendido de Mobile 02 responde a un horario programado (Azure Activity Log); de confirmarse, recalibrar la ventana de `nodata()` contra ese horario real en lugar del valor inferido empíricamente.
6. **(SRE) Pendiente, opcional** — Confirmar SKU/tamaño de VM de Mobile 01 y Mobile 02 vía `az vm show` y documentar en `loyalty/docs/infrastructure.md`.

## Hallazgos secundarios

El punto abierto sobre el origen (manual vs. programado) del ciclo de apagado de Mobile 02 ya figuraba, sin resolver, en la investigación de carga `GITIN-1909` (2026-08-21) — no es un hallazgo nuevo de este ticket, pero queda como bloqueante para calibrar con precisión la ventana de `nodata()` de la acción propuesta 5.
