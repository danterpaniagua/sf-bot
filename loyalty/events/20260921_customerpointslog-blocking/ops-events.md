# Eventos — 20260921_customerpointslog-blocking

## 2026-09-21 07:22 — Hallazgo incidental de bloqueo activo

Durante la verificación de carga previa a la creación de índices del ticket GITIN-2074, detecté una cadena de bloqueo activa sobre `Sml.CustomerPointsLog`. Separé el hallazgo en este evento por tratarse de una tabla distinta y no relacionada.

## 2026-09-21 ~07:23-07:28 — Identificación de la cadena de bloqueo

Confirmé que `PNSSRL_MantenimientoIndices` (SPID 93) llevaba ~4h10m en cola por un lock de modificación de esquema, sin haber empezado el rebuild, bloqueado por un job de sincronización ETL (SPID 80). Identifiqué 12 sesiones reales de aplicación (MobileAppService, sitio de club, Zabbix) encoladas detrás.

## 2026-09-21 ~07:29 — Conexión con precedente GITIN-1981/2060/2061

Confirmé que el job bloqueado es el mismo investigado en GITIN-1981, con remediación (reprogramación a 08:00 UTC, rebuild acotado a partición) nunca aplicada bajo GITIN-2060/2061. Confirmé también que SPID 80 corresponde al bug ya diagnosticado en `events/20260715_cpu_spikes/`, tampoco corregido.

## 2026-09-21 07:30 — Cancelación del rebuild en cola

Recibí el ticket GITIN-2076 para este evento. Ejecuté `KILL 93` para liberar la cola de sesiones bloqueadas, dado que el rebuild no había avanzado nada (0% de progreso).

## 2026-09-21 07:30-07:31 — Confirmación de resolución del síntoma inmediato

Verifiqué que la cadena de bloqueo se despejó por completo: solo quedó SPID 80 corriendo normalmente, sin bloquear a nadie. Documenté que la causa de fondo (GITIN-2060/2061) sigue sin resolverse.
