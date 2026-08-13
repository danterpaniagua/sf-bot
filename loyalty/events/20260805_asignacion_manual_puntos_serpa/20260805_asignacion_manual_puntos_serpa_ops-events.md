# Eventos — 20260805_asignacion_manual_puntos_serpa

## 2026-08-05 17:59 — Solicitud recibida

He recibido de Jacky la solicitud de asignar 63.580 puntos, motivo "Puntos por Premio", a la cuenta con CustomerId `561BEF0E-3CE9-C29C-36D2-08DDF9361945`, DNI 16762109.

## 2026-08-05 17:59 — Verificación de identidad

He ejecutado Q1 y confirmado que el `CustomerId` corresponde a Claudia Serpa, DNI 16762109.

## 2026-08-05 19:30 — Primera ejecución — placeholder sin reemplazar

He ejecutado el `INSERT` transaccional (Q2) dejando sin reemplazar el parámetro `RegisterByUser` (placeholder `<usuario_que_ejecuta>`). Antes de confirmar, he verificado el estado con una consulta `NOLOCK` (Q3) y he detectado el error.

## 2026-08-05 19:32 — Reejecución y commit

He vuelto a ejecutar el `INSERT` (Q2) con `RegisterByUser = 'dantep'` y he confirmado la transacción.

## 2026-08-05 19:33 — Confirmación final

He ejecutado Q3 y confirmado el estado final: `ManualAssignPointsId` 9835, `CustomerPointsLogId` 390056929, `Status = Approved`, 63.580 puntos, `RegisterByUser = dantep`. Asignación cerrada.
