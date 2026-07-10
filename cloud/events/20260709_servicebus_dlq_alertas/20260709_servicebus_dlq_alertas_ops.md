# [OPE] Configurar alertas de DLQ en Service Bus — SmartFran-Cloud-ServiceBus-Grido-PRO

**Fecha:** 2026-07-09
**Estado:** Cerrado
**Severidad:** Media
**Suscripción:** SmartIT Cloud (`85c76dea-3304-4310-8656-bf21b28e4f4b`)

---

## Resumen

Se deberá configurar notificaciones por email cuando mensajes arriben a las colas Dead Letter Queue (DLQ) del namespace `SmartFran-Cloud-ServiceBus-Grido-PRO`. Según Gastón existía una configuración previa, pero el equipo confirma que no se recibieron notificaciones. Se deberá auditar la configuración existente y corregir o crear las alertas necesarias en Azure Monitor.

---

## Tabla resumen

| Campo | Valor |
|---|---|
| Sistema | Azure Service Bus — `SmartFran-Cloud-ServiceBus-Grido-PRO` |
| Resource Group | `SmartFran.Cloud.PRO.GRIDO` |
| Suscripción | SmartIT Cloud (`85c76dea-3304-4310-8656-bf21b28e4f4b`) |
| Severidad | Media |
| Detectado | 2026-07-09 |
| Resuelto | 2026-07-09 |
| Responsable | Dante Paniagua |

---

## Causa raíz

A determinar. Gastón habría configurado alertas previamente que no están funcionando. Posibles causas: action group con emails incorrectos, regla de alerta deshabilitada, umbral mal configurado, o alerta apuntando a un scope incorrecto.

---

## Hallazgos

A completar tras investigación.

---

## Recursos afectados

| Recurso | Tipo | RG |
|---|---|---|
| `SmartFran-Cloud-ServiceBus-Grido-PRO` | Service Bus Namespace | `SmartFran.Cloud.PRO.GRIDO` |
| Alert rules existentes | Azure Monitor | A confirmar |
| Action Group existente | Azure Monitor | A confirmar |

---

## Comandos ejecutados

| # | Comando / Script | Propósito |
|---|---|---|
| CX-01 | `20260709_servicebus_dlq_alertas_scripts.sh` | Listar alert rules existentes sobre el Service Bus |
| CX-02 | `20260709_servicebus_dlq_alertas_scripts.sh` | Listar action groups en el RG |
| CX-03 | `20260709_servicebus_dlq_alertas_scripts.sh` | Listar colas y DLQ count actual |

---

## Acciones propuestas

1. Auditar alert rules y action groups existentes para identificar por qué no llegan notificaciones.
2. Corregir o crear action group con los siguientes destinatarios de email:
   - Dante Paniagua (`danterpaniagua@gmail.com`)
   - Javier Allende (email a confirmar)
   - Javier Picco (email a confirmar)
   - Gaspar (email a confirmar)
3. Crear o corregir metric alert rule sobre la métrica `Dead-lettered messages` con umbral `> 0` para todas las colas del namespace.
4. Verificar recepción de notificación de prueba en todos los destinatarios.
