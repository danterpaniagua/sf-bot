# GITIN-2075 — Sales-PRO: caídas recurrentes por OOM (recurrencia GITIN-2040)

**Tags:** SmartCloud, CloudPOS, Azure, Performance, SRE, PROD

## Resumen

El servicio Sales (`SmartFran-Cloud-Sales-PRO`) venía presentando caídas recurrentes de su proceso por `System.OutOfMemoryException` — el mismo patrón identificado en septiembre bajo GITIN-2040, sin resolución confirmada desde entonces. En la ventana de 48 horas analizada se confirmaron 18 caídas con la misma firma (`0xE0434352`). El plan de App Service (P3v3, ~32 GB de RAM por instancia) tiene memoria de sobra, por lo que la causa no era evidente por el tamaño del plan. Grido reportó estas caídas por WhatsApp, coincidiendo con picos de consumo de CPU reportados en Sales. Se identificó que el worker process corría en modo 32 bits — un proceso de 32 bits solo puede direccionar ~2-4 GB independientemente de la RAM real del plan, explicación suficiente por sí sola del agotamiento de memoria. Se aplicó el cambio a 64 bits, verificado tanto en configuración como en los procesos en ejecución. **Una caída nueva confirmada el 2026-09-21 a las 06:00 GMT, ~5h45m después del cambio, muestra que el modo 32 bits no era la única causa** — un proceso de 64 bits correctamente dimensionado que vuelve a agotar memoria en pocas horas apunta a una pérdida de memoria real, que el techo de 32 bits enmascaraba o aceleraba, no algo que el cambio de bitness resuelva por sí solo. El patrón de consulta sin límite (`Movement/POSGetAll`) queda como la siguiente línea a investigar.

## Tabla resumen

| Campo | Valor |
|---|---|
| Ticket Jira | [GITIN-2075](https://smartit-ar.atlassian.net/browse/GITIN-2075) |
| ID alerta | — (recurrencia proactiva de GITIN-2040, reportada por el cliente vía WhatsApp) |
| Sistema | SmartFran Cloud — App Service `SmartFran-Cloud-Sales-PRO` (plan `SmartFran-Cloud-Sales-Plan-PRO`) |
| Severidad | Alta — caídas de proceso en producción con impacto reportado por el cliente |
| Detectado | 2026-09-20 (recurrencia; primera ocurrencia GITIN-2040, septiembre) |
| Resuelto | **No — activamente empeorando.** Corrección de 32 bits aplicada, pero el patrón de caídas continúa y se está acelerando (ver H11) |
| Responsable | Dante Paniagua |

## Causa raíz

El worker process de `SmartFran-Cloud-Sales-PRO` corría en modo 32 bits (`use32BitWorkerProcess: true`) sobre un plan P3v3 (.NET v10.0). Un proceso de 32 bits en Windows solo puede direccionar entre ~2 y 4 GB de memoria, sin importar cuánta RAM tenga la VM — techo suficiente por sí solo para explicar las caídas por `OutOfMemoryException`, sin necesidad de un límite de memoria configurado manualmente (no se encontró ninguno). Un heap artificialmente chico también obliga al garbage collector a correr con mucha más frecuencia, lo que es consistente con los picos de CPU reportados en paralelo a las caídas — hipótesis razonada, no medida directamente (sin datos de frecuencia de GC).

## Hallazgos

| # | Hallazgo | Riesgo |
|---|---|---|
| H1 | Detector de Proactive Crash Monitoring de Azure: 18 caídas por `0xE0434352 - CLR Exception` en la ventana de 48h, dos eventos inspeccionados individualmente confirman `System.OutOfMemoryException` — firma idéntica a GITIN-2040 | Alto |
| H2 | 0 filas con `ScStatus` 5xx en 640.105 requests HTTP de la misma ventana — consistente con que las caídas cuelgan los requests en curso hasta que expira el timeout del cliente, en vez de devolver un error visible | Medio |
| H3 | SKU actual confirmado: P3v3 (Windows), 3 instancias, autoescalado 1-4 por CPU. Costo aproximado USD 1,26/hora por instancia (USD 3,78/hora a capacidad actual) | Informativo |
| H4 | Historial de cambios de SKU no confirmado — la consulta inicial al Activity Log (`--resource-id`) mostraba solo un cambio de plan (2026-09-10), pero se confirmó que ese flag no filtra realmente por recurso (devuelve actividad de todo el resource group) — la conclusión original no es confiable y requiere re-chequeo con filtrado del lado del cliente | Bajo |
| H5 | Endpoint `Movement/POSGetAll`: 13.745 requests, máximo 230.015 ms — justo en el techo de espera de 230 segundos de Azure, ya señalado con errores 500 recurrentes en una investigación de septiembre | Medio |
| H6 | Patrón de consulta sin límite confirmado en el código fuente (`AccessRepository.GetByConditionsAsync`, `MovementServices.POSGetAllAsync`) — sin `Take(n)` ni límite de resultados, puede devolver el historial completo de un franchise sin filtro real. Verificado que el código coincide exactamente entre `dev` y `origin/main` (hashes idénticos) — no es un problema exclusivo de una rama no desplegada. Posible causa contribuyente, no confirmada contra los horarios exactos de las 18 caídas | Medio |
| H7 | Causa contribuyente confirmada y corregida: worker process en modo 32 bits, verificado en configuración (`use32BitWorkerProcess: false` tras el cambio) y en los procesos en ejecución (sin módulos WoW64 cargados en los `w3wp` activos) — real, pero no la causa completa (ver H8/H9) | Alto |
| H8 | Primer recheck post-cambio (~3h después): sin caídas nuevas, pero no concluyente — el historial pre-cambio ya tenía ventanas limpias de 12-14 horas durante el período activo | Medio |
| H9 | **Segundo recheck confirma una caída nueva el 2026-09-21 a las 06:00 GMT**, ~5h45m después del cambio — mismo código `0xE0434352`, no confirmada individualmente como `OutOfMemoryException` todavía. El modo 32 bits no era la causa completa; un proceso de 64 bits agotando memoria en pocas horas apunta a una pérdida de memoria real, probablemente ligada al patrón de consulta sin límite (H6) | Alto |
| H10 | **Correlación real confirmada con la métrica de memoria por instancia**: la instancia `wn1ldwk0002VU` alcanzó 87% de memoria a las 05:45 GMT — 15 minutos antes de la caída de las 06:00 GMT. Otras dos instancias también subieron en la misma ventana (`wn1ldwk0002XC` 50% a las 05:00, `wn1ldwk0002WT` 37% a las 05:15). El primer chequeo en vivo (ventana de 30 minutos, corrida después de que el pico ya había bajado, y sin desglosar por instancia) no lo había detectado | Alto |
| H12 | **`use32BitWorkerProcess` volvió a `true` — causa casi segura de H11.** Verificado directamente (`data/sales_webapp_config_20260922_check.json`): `use32BitWorkerProcess: true`, de vuelta a la causa raíz original ya corregida el 2026-09-21. Confirma el patrón de "flip-flop" que el usuario había señalado como sospecha (`investigation.md`, sección Team Only, 2026-09-21) — ahora confirmado que ocurrió de nuevo. Nada en esta sesión aplicó esta reversión — ocurrió sola entre la corrección (~00:15 GMT del 2026-09-21) y ahora | Alto (causa raíz probable de H11) |
| H13 | **Mecanismo de la reversión investigado — plausible, no confirmado.** El workflow real de deploy a PRO (`SmartFran.Cloud.Sales.PRO_win.yml`) no toca configuración de App Service en ningún paso — descarta un "default desactualizado en el pipeline" como explicación directa. Historial de deploys de Kudu confirma dos despliegues (`OneDeploy`, exitosos) después de la corrección: 2026-09-21 10:54 y 14:37 GMT — la primera caída nueva post-corrección (21:20 GMT) ocurrió 6h43m después del segundo, correlación temporal circunstancial. Se intentó confirmar vía Azure Change Analysis (traza de cambios a nivel de propiedad) — **bloqueado**: `Microsoft.ChangeAnalysis` está explícitamente excluido de los providers permitidos en esta suscripción (restricción de política, no un tema de registro). **El valor por defecto documentado de Microsoft para `use32BitWorkerProcess` es `true`** (compatibilidad legacy) — mecanismo plausible: si un despliegue hizo que el override explícito `false` se perdiera/reseteara (en vez de requerir una escritura explícita a `true`), Azure caería solo a este default, lo cual también explicaría por qué no aparece como un evento de cambio explícito en Activity Log. No confirmado como el mecanismo real — consistente con toda la evidencia observada, pero no probado | Medio (explica el mecanismo plausible, no bloquea la acción correctiva) |
| H11 | **2026-09-22: el patrón de caídas continúa y se acelera — no está resuelto.** Usuario reportó impresión de que el problema estaba resuelto; se verificó directamente en vez de aceptarlo sin chequear. Re-consulta del detector (2026-09-21 05:00 GMT en adelante, `data/sales_appcrashes_20260922_recheck.json`): **7 caídas totales**, 6 nuevas desde la última conocida — 21:20, 21:55 (2026-09-21), luego 01:20, 01:45, 03:35, 04:30 GMT (2026-09-22, esta última a menos de una hora del chequeo). Dos pares separados por solo 25-35 minutos — intervalos más cortos que las ventanas limpias de 12-14h observadas antes. También se revisó el código fuente de la aplicación (`main` recién actualizado): sin cambios relevantes desde esta investigación — el patrón de consulta sin límite (H6) sigue exactamente igual, sin remediar | Alto (activo, empeorando) |

## Recursos afectados

| Recurso | Detalle |
|---|---|
| `SmartFran-Cloud-Sales-PRO` | App Service afectado por las caídas |
| `SmartFran-Cloud-Sales-Plan-PRO` | Plan de App Service (P3v3, 3 instancias) |
| `Movement/POSGetAll`, `Movement/GetFromMoneyWarehouse` | Endpoints con el patrón de consulta sin límite identificado |
| Grido (cliente) | Reportó las caídas por WhatsApp, coincidente con los picos de CPU |

## Comandos ejecutados

Sin `scripts.sh` consolidado para este ticket — cada resultado (exportación de Graylog, métricas de Azure Monitor, detector de crashes, configuración del App Service, verificación de bitness vía Kudu) quedó persistido individualmente en `data/` a medida que se ejecutaba. Principales archivos: `sales_appcrashes_48h.json`/`sales_appcrashes_postfix_recheck.json`/`sales_appcrashes_recheck2.json` (detector de crashes, este último con la caída nueva post-cambio), `httplogs_raw_export.csv`/`timetaken_by_path_aggregated.csv` (tráfico HTTP), `cpu_ram_full_window.json` (métricas del plan), `sales_webapp_config.json`/`sales_webapp_config_recheck.json` (config del worker process), `sales_kudu_process_bitness.json` (verificación en vivo), `p3v3_pricing_broad.json` (costo del SKU).

## Acciones propuestas

0. **(SRE) Pendiente, urgente** — Re-aplicar `use32BitWorkerProcess: false` inmediatamente (revertido a `true`, ver H12) como mitigación de corto plazo.
0b. **(SRE/Dev) Pendiente, urgente — corrección real dado H13.** No se pudo confirmar la causa exacta de la reversión (Change Analysis bloqueado a nivel de suscripción), pero el mecanismo plausible (caída al default de Azure `true` si el override se pierde en un despliegue) sugiere que la corrección debe ser **durable ante futuros deploys**, no un ajuste manual único que puede volver a perderse. Opciones: (a) agregar un paso explícito `az webapp config set --use-32bit-worker-process false` al workflow `SmartFran.Cloud.Sales.PRO_win.yml` (`.github/workflows/`), reafirmando el valor en cada deploy; (b) crear un `SmartFran.Cloud.Sales.Settings.PRO.yml` análogo a los ya existentes `.Settings.DEV.yml`/`.Settings.TEST.yml` — notablemente, **no existe un equivalente para PRO hoy**, gap que probablemente sea relevante acá. Cualquiera de las dos cierra el ciclo de manera más robusta que repetir el `az webapp config set` manual.
1. **(SRE) Completado (parcialmente — ver punto 0)** — Cambio del worker process a 64 bits (`use32BitWorkerProcess: false`), verificado tanto en configuración como en los procesos en ejecución (sin módulos WoW64). Mitigó pero no eliminó el problema, y la corrección misma se revirtió sola — ver punto 3.
2. **(SRE) Pendiente** — Confirmar individualmente (drill-down del detector, o `.dmp` vía Kudu) que la caída del 2026-09-21 06:00 GMT es realmente `OutOfMemoryException` y no otra excepción con el mismo código de crash.
3. **(Dev) Pendiente, prioridad alta** — Revisar el patrón de consulta sin límite en `Movement/POSGetAll`/`GetFromMoneyWarehouse` (`AccessRepository.GetByConditionsAsync`) como causa probable de la pérdida de memoria real detrás de las caídas post-cambio. Detalle técnico completo, con diagramas y referencias de código, en `email_dev.md`.
4. **(SRE) Pendiente, baja prioridad** — Confirmar el historial real de cambios de SKU/instancia si se vuelve relevante más adelante (Resource Graph Change History, no consultado en este ticket).
5. **(SRE) Pendiente** — Repetir el chequeo de caídas post-cambio con una ventana más larga (24h+) para tener una lectura real de si el cambio a 64 bits redujo la frecuencia de caídas, más allá de la única recurrencia confirmada hasta ahora (2026-09-21 06:00 GMT).
6. **(SRE) Pendiente, baja prioridad** — Re-consultar el historial de cambios de SKU/plan (H4) filtrando del lado del cliente, dado que `--resource-id` no filtra realmente por recurso en `az monitor activity-log list` — la conclusión actual de "un solo cambio, 2026-09-10" no es confiable.
