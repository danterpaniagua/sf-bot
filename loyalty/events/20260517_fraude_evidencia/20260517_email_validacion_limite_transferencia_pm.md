# Email — Reporte de Hallazgo

**Para:** PMs — SmartLoyalty / Club Grido
**De:** Dante Paniagua, SRE
**Fecha:** 2026-05-17
**Asunto:** [ALERTA] Límite diario de transferencia de puntos no está siendo aplicado por la plataforma

---

Equipo,

Durante el monitoreo del día de hoy se detectó una transferencia de puntos que excede el límite diario establecido en el Reglamento de Club Grido. La investigación confirma que la plataforma no aplica este límite en tiempo real, permitiendo que las transferencias se procesen sin validación del tope reglamentario.

---

## Regla de negocio afectada

El Reglamento de Club Grido establece los siguientes límites para transferencia de puntos entre socios:

| Período | Límite |
|---|---|
| Diario | 8.000 puntos |
| Semanal | 10.000 puntos |
| Mensual | 13.000 puntos |

## Evento detectado hoy

Hoy a las 09:26 se registró una transferencia de **24.785 puntos** entre dos cuentas de socios, representando **3,1 veces el límite diario permitido** (+16.785 puntos sobre el máximo). La operación fue aceptada por la plataforma sin rechazo ni alerta.

## Patrón recurrente

Este es el **tercer evento confirmado** con violación del límite de transferencia en los últimos días:

| Fecha | Modalidad |
|---|---|
| 2026-05-14 | Múltiples transferencias coordinadas entre varias cuentas |
| 2026-05-15 | Múltiples transferencias coordinadas entre varias cuentas |
| 2026-05-17 | Transferencia única por el total del saldo disponible |

## Situación actual

La plataforma registra cada transferencia de forma individual sin verificar si el socio emisor alcanzó o superó el límite reglamentario antes de procesar la operación. Esta ausencia de control es estructural y afecta a todos los canales (web, mobile, punto de venta).

El equipo IT tiene identificada la causa técnica y está trabajando en la corrección.

---

Se recomienda que el área de negocio evalúe si corresponde alguna acción sobre las cuentas involucradas en los eventos registrados, en línea con lo establecido en el Reglamento.

Dante Paniagua
SRE — SmartLoyalty
