# Reporte de Eventos — Uso Elevado de CPU
**Fecha:** 14 de mayo de 2026
**Sistema:** SmartLoyalty — Base de datos principal
**Elaborado por:** Dante Paniagua, SRE

---

## Resumen

El día de hoy se registraron dos episodios de uso elevado de CPU en la base de datos principal de SmartLoyalty. Ambos fueron identificados y analizados. El sistema se recuperó solo en los dos casos, sin necesidad de intervención manual.

---

## Evento 1 — Pico de CPU (18:25 – 18:45)

**¿Qué pasó?**
Un proceso del sistema ejecutó una operación muy pesada que consumió prácticamente toda la capacidad del servidor durante aproximadamente 10 minutos.

**¿Cuál fue el impacto?**
El servidor superó el 90% de uso de CPU. Esto pudo haber generado lentitud en las respuestas del sistema para los usuarios durante ese período.

**¿Está resuelto?**
Sí. El proceso finalizó solo y el servidor volvió a niveles normales antes de las 18:45.

**Próximos pasos**
El equipo técnico revisará el proceso identificado para optimizarlo y evitar que vuelva a generar este nivel de impacto.

---

## Evento 2 — Carga elevada y sostenida (14:00 – 16:00)

**¿Qué pasó?**
Durante dos horas se registró un uso elevado de CPU generado por tres procesos que corrían al mismo tiempo:

1. Una consulta manual ejecutada desde una computadora de QA directamente sobre la base de datos de producción.
2. Un servicio del sistema con alta frecuencia de ejecución que estaba consumiendo más recursos de lo esperado.
3. Un proceso de mantenimiento de datos programado que corría en paralelo.

**¿Cuál fue el impacto?**
Carga sostenida sobre la base de datos durante el período indicado. No se registraron caídas ni interrupciones del servicio.

**¿Está resuelto?**
Sí. Los tres procesos finalizaron de forma natural dentro del período.

**Próximos pasos**
- Se eliminarán las IPs desconocidas de las reglas de acceso al servidor de base de datos.

---

*Reporte generado con datos de monitoreo interno (PNSSRL). Para consultas técnicas, contactar al equipo SRE.*
