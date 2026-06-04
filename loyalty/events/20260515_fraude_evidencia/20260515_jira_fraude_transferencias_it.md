# Jira — Incidente: Ataque automatizado sobre transferencias de puntos

**Tipo:** Incidente  
**Prioridad:** Crítica  
**Componente:** SmartLoyalty — Transferencia de puntos  
**Fecha:** 15/05/2026  

---

## Descripción

Ataque automatizado detectado durante dos noches consecutivas (14 y 15/05). El atacante dispone de datos personales de clientes (DNI) y ejecuta transferencias masivas desde cuentas reales hacia cuentas receptoras bajo su control, a razón de una transferencia cada 4–7 segundos.

- **Noches afectadas:** 2
- **Cuentas de origen:** 117
- **Puntos sustraídos:** 1.062.270
- **Puntos recuperables:** 1.025.270 (en cuentas receptoras identificadas)
- **Puntos irrecuperables:** 4.000 (ya canjeados)
- **Próxima oleada esperada:** esta noche entre 02:30 y 03:00 (UTC-3)

El sistema no aplica validación en tiempo real del límite diario de 8.000 puntos por transferencia. 51 de las 117 operaciones lo superaron.

---

## Acciones requeridas

1. Suspender la función de transferencia de puntos en la plataforma.
2. Bloquear las 7 cuentas receptoras identificadas (ver reporte de evidencia).
3. Revertir los puntos acumulados en dichas cuentas.
4. Implementar validación en tiempo real del límite diario/semanal/mensual de transferencias.
5. Implementar detección de anomalías: múltiples remitentes distintos hacia un mismo receptor en ventana corta de tiempo.
6. Investigar el origen del listado de datos personales utilizado por el atacante.

---

## Evidencia

`events/20260515_fraude_evidencia/` — queries, CSVs de participantes e identificación de hubs.
