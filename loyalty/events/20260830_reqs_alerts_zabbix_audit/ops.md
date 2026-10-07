# GITIN-1966 — Auditoría de eficiencia de alertas de tráfico (Req/s) en toda la flota Zabbix

**Tags:** SmartLoyalty, Obserbavilidad, SRE

## Descripción

Las alertas de tráfico (Req/s) configuradas en Zabbix para los distintos hosts de la flota (WebServiceV2, ClubGrido, WebService/WebSite, WebServiceCG, MobileAppService) coexisten en 4 esquemas de configuración distintos y no coordinados entre sí (ver Hallazgos). La administración de Zabbix es responsabilidad de una única persona, por lo que la falta de coordinación no responde a distintos equipos o criterios en conflicto, sino a convenciones que fueron evolucionando a lo largo del tiempo sin unificarse retroactivamente. Este story (hijo de GITIN-1965) releva el estado real de esas alertas en toda la flota — no solo si existen, sino si sus umbrales y su cobertura siguen teniendo sentido — y define qué decisiones y ajustes quedan pendientes para consolidarlas.

No es un incidente: no hubo caída de servicio ni alerta perdida que haya originado este trabajo. Es una auditoría proactiva que nació al corregir la falta de alertas en `SFCG-WSCG-01` (GITIN-1961) y encontrar, al revisar el resto de la flota, que el problema real no era ausencia de alertas sino falta de coordinación entre distintas generaciones de configuración.

## Hallazgos

| # | Hallazgo | Riesgo |
|---|---|---|
| H1 | La flota tiene 4 generaciones distintas de configuración de alertas de tráfico, sin convención unificada: macros globales sin contexto (`SFCG-WSV2-01/02`), contexto compartido por par (`CLUBS`), una familia de macros completamente distinta compartida literalmente entre 4 hosts distintos (`IIS_REQUESTS_WSV1_POST`, hosts `SFCG-WEBS-01/02/03` y `SFCG-WSIT-01`), y un contexto por host recién creado (`WEBSCG01`, GITIN-1961) | Medio |
| H2 | `SFCG-WEBS-01/02/03` y `SFCG-WSIT-01` — cuatro servicios distintos — comparten exactamente el mismo umbral de alerta (30/90/120 req/s), sin ajuste por servicio | Medio |
| H3 | `SFCG-MOBI-01`/`02` corren **tres esquemas de alerta superpuestos simultáneamente** sobre la misma métrica: el esquema legado (`PERF_COUNT_TRIG_*` base), detección de caída brusca (`DROP`, contexto compartido `MOBI`), y el esquema de picos (`IIS Spike`, contexto por host). Tener tres esquemas activos sobre una misma métrica es en sí mismo un problema de eficiencia — ruido de alertas y confusión al triangular una causa — independiente de si cada umbral individual es correcto | Alto |
| H4 | Existe un macro huérfano (`{$PERF_COUNT_TRIG_*:WEBS}`, distinto de la familia que realmente usan los hosts WEBS/WSIT) con un error de configuración: `AVERAGE=11` es menor que `WARNING=15`, invertido — no está referenciado por ningún trigger actualmente, pero quedó documentado por si fue un intento de reemplazo inconcluso | Bajo |
| H5 | `SFCG-MOBI-02` tiene un trigger de `nodata()` dedicado (cubre su ciclo de apagado nocturno); `SFCG-MOBI-01` no tiene ninguno — no confirmado si es una asimetría intencional o un gap real de cobertura | Bajo |
| H6 | La brecha de umbral ~13x entre `SFCG-MOBI-01` y `SFCG-MOBI-02` en el esquema `IIS Spike` — **resuelto durante este story, cruzando datos con GITIN-1965**: es proporcional a la diferencia real de tráfico entre ambos hosts (confirmada con una línea base fresca de 4 fines de semana), no un error de copiado. No requiere acción | Informativo |

## Recursos afectados

| Recurso | Rol en el hallazgo |
|---|---|
| `SFCG-WSV2-01`/`02` | Esquema base, funcional, sin cambios propuestos |
| `SFCG-CLUB-01`/`02` | Esquema `CLUBS`, funcional, sin cambios propuestos |
| `SFCG-WEBS-01`/`02`/`03`, `SFCG-WSIT-01` | Umbral compartido sin diferenciación por servicio (H2) |
| `SFCG-WSCG-01` | Ya corregido en GITIN-1961, referencia de la convención a seguir |
| `SFCG-MOBI-01`/`02` | Tres esquemas superpuestos (H3), asimetría de cobertura `nodata()` (H5) |

## Criterios de aceptación

- [ ] Definido y documentado, para cada host/servicio de la flota, cuál de los 4 esquemas de macros/triggers es el vigente — sin ambigüedad sobre cuál seguir al crear un host nuevo.
- [ ] `SFCG-MOBI-01`/`02` corren un único esquema de alerta de tráfico, no tres simultáneos.
- [ ] Decidido (no necesariamente implementado en este story) si `SFCG-WEBS-01/02/03`/`SFCG-WSIT-01` deben tener umbrales diferenciados por servicio o si el umbral compartido es aceptable.
- [ ] Resuelto el macro huérfano `{$PERF_COUNT_TRIG_*:WEBS}` (eliminado o corregido, según se decida).
- [ ] Confirmado si `SFCG-MOBI-01` necesita su propio trigger `nodata()`.

## Sub-tareas

| # | Sub-tarea | Esfuerzo | Riesgo |
|---|---|---|---|
| ST1 | Decidir y documentar cuál esquema de macros/triggers es la convención vigente de la flota (¿el patrón `WEBSCG01` de GITIN-1961, o algo distinto?) | Bajo | Bajo — solo documentación |
| ST2 | Deshabilitar el esquema legado `PERF_COUNT_TRIG_*` en `SFCG-MOBI-01`/`02`, dejando `IIS Spike` (ya calibrado por host, ver H6) y `Caída brusca` como los esquemas vigentes | Bajo | Medio — cambio en triggers de producción, requiere confirmar que no rompe dependencias entre triggers |
| ST3 | Confirmar con quien corresponda (o inferir de la documentación de arquitectura) si `SFCG-MOBI-01` necesita un trigger `nodata()` propio, y crearlo si aplica, replicando el patrón de `SFCG-MOBI-02` (`{$MOBILE_PCOUNT_NODATA_WINDOW:MOBI01}`) | Bajo | Bajo |
| ST4 | Pull de historial de tráfico (30d) para `SFCG-CLUB-01/02` y `SFCG-WEBS-01/02/03`/`SFCG-WSIT-01` para verificar si sus umbrales actuales siguen siendo razonables, mismo método que se usó para calibrar `MOBI` en GITIN-1918 | Medio | Bajo |
| ST5 | Decidir el destino del macro huérfano `{$PERF_COUNT_TRIG_*:WEBS}` (eliminar, o corregir el bug `AVERAGE<WARNING` y terminar de migrar los hosts WEBS/WSIT a esta familia en vez de `IIS_REQUESTS_WSV1_POST`) | Bajo | Bajo |

## Comandos ejecutados

| # | Comando / Script | Propósito |
|---|---|---|
| C1 | `trigger.get` fleet-wide (`monitored: true`, hosts reales) | Inventario completo de triggers y tags en toda la flota — 1.176 triggers, 22 hosts reales |
| C2 | `usermacro.get` sin filtro (global + por host) | Detectar el gap real: los macros base sí estaban definidos, contradiciendo un chequeo filtrado previo que dio falso negativo |
| C3 | `action.get` con `selectFilter`/`selectOperations` | Confirmar qué combinación de tags realmente enruta alertas (`scope:OPE` + `service_group:LOYALTY` + `action~MAIL`) |

Detalle completo en `all-trigger-tags-real-hosts.json` (este folder) y en `docs/zabbix_observability.md`.

## Acciones propuestas

1. **(SRE)** Ejecutar ST1-ST5 según orden de prioridad (ST2 y ST3 son cambios de bajo esfuerzo con impacto directo en reducir ruido de alertas; ST4 y ST5 son de menor urgencia).
2. **(SRE)** Una vez resuelto ST2, verificar que las dependencias entre triggers de `SFCG-MOBI-01`/`02` sigan siendo correctas (el trigger `nodata()` de `MOBI-02` debe seguir como raíz de la cadena de dependencias).
3. **(SRE)** Documentar en `docs/zabbix_observability.md` la convención vigente resultante de ST1, para que el próximo host que se incorpore a la flota (ver `GITIN-1961` como precedente) la siga desde el principio.

## Hallazgos secundarios

Ninguno fuera del alcance ya cubierto arriba.
