# Eventos — 20260723_bloqueo_customerpointslog_loadtest

*Nota: este registro se escribió de forma retroactiva, reconstruido a partir de la conversación de trabajo del mismo día — no en tiempo real.*

## 2026-07-23 08:30 — Reporte de picos de batch requests

He recibido el reporte de que el equipo de App Grido inició un load test sobre MobileAppService a las 08:30 (UTC-3), y que Zabbix venía reportando picos de ~5.000 batch requests sobre `PNSSRL` desde ese horario, junto con tiempos de espera elevados (avg 8.272 / max 30.078 en ventana de 6h).

## 2026-07-23 — Identificación de la cadena de bloqueo

He ejecutado el chequeo de disponibilidad de datos y el delta de CPU por SPID (Q1, Q2), y luego consultado las DMVs en vivo (Q3). Confirmé una cadena de bloqueo real: SPID 87 bloqueado por SPID 93, `wait_type LCK_M_SCH_M`.

## 2026-07-23 — Terminación de la transacción abandonada

Identifiqué que SPID 93 correspondía a una transacción sin confirmar bajo el login `zabbix`, consistente con una sesión de SSMS dejada abierta. Terminé la sesión (`KILL 93`, Q4) — comando ejecutado con éxito.

## 2026-07-23 — Confirmación de que SPID 87 es mantenimiento legítimo

Verifiqué que, tras liberarse el bloqueo, SPID 87 seguía en ejecución — es un `ALTER INDEX REBUILD` de mantenimiento programado (`PNSSRL_MantenimientoModulos`), no una consecuencia del incidente. Al ser un rebuild offline, retiene `Sch-M` durante toda su duración y no reporta `percent_complete` confiable.

## 2026-07-23 14:09 — Nueva métrica de espera

Verifiqué una métrica de espera reportada desde las 14:09 (avg 55.683) y confirmé que correspondía al mismo SPID 87 en ejecución, no a un evento nuevo.

## 2026-07-23 — Decisión de esperar el rebuild en curso

Evalué terminar 7 sesiones adicionales bajo el login `zabbix` — se decidió esperar a que terminara el rebuild en curso en vez de intervenir sobre SPID 87 ni sobre esas sesiones.

## 2026-07-23 — Normalización observada al cierre de la sesión de trabajo

Al cierre de la sesión de trabajo, la CPU había bajado a ~14% y Zabbix reportaba valores normalizados (min 0,59 / avg 4,4 / max 14). No se hizo una verificación final explícita de que SPID 87 hubiera terminado — queda como acción propuesta pendiente.

## 2026-07-23 — Confirmación de normalización (Zabbix, últimas 3h)

Verifiqué los tiempos de espera de Zabbix de las últimas 3 horas: Locks (wait time) avg 45ms / max 5.746ms; Waits avg 7ms / max 1.244ms. Son órdenes de magnitud menores que los valores del incidente (avg 8.272 / max 30.078 en la ventana inicial, avg 55.683 durante el rebuild) — confirma que SPID 87 terminó y la situación está normalizada. Cierro la verificación pendiente de H7.
