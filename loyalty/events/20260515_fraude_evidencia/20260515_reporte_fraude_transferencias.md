# Reporte de Fraude — Transferencias de Puntos
**Fecha del reporte:** 15 de mayo de 2026  
**Sistema:** SmartLoyalty — Base de datos principal  
**Elaborado por:** Dante Paniagua, SRE  
**Estado:** ACTIVO — se espera una tercera oleada esta noche

---

## Resumen ejecutivo

Se detectó un ataque automatizado de dos noches consecutivas contra el sistema de transferencia de puntos de SmartLoyalty. Un atacante con datos personales de clientes reales (incluyendo DNI) ejecutó transferencias masivas desde 117 cuentas afectadas hacia 5 cuentas receptoras bajo su control. El total de puntos sustraídos asciende a **1.062.270 puntos**. Al momento de este reporte, **1.025.270 puntos permanecen en las cuentas receptoras y son recuperables** si se actúa de inmediato. **4.000 puntos ya fueron canjeados** por dinero y no son recuperables.

El ataque continúa activo. Se espera una tercera oleada esta noche entre las **02:30 y 03:00 (UTC-3)**.

---

## Cronología

### Noche 1 — 14 de mayo de 2026

| | |
|---|---|
| Horario (UTC-3) | 01:28 – 02:07 |
| Cuentas comprometidas | 26 |
| Puntos sustraídos | 294.270 |
| Cuentas receptoras | Lautaro Crupi + Pedro Portillo |
| Redistribución | Lautaro Crupi transfirió 30.000 pts a Carlos Agustín Sihuen Sánchez |
| Canjes | 4.000 pts canjeados por Beluuu Ibazeta ("Punto Dinero") |

### Noche 2 — 15 de mayo de 2026

| | |
|---|---|
| Horario (UTC-3) | 02:38 – 03:20 |
| Cuentas comprometidas | 91 |
| Puntos sustraídos | 768.000 |
| Cuenta receptora | Theito Pirola |
| Redistribución | Ninguna hasta el momento |
| Canjes | Ninguno hasta el momento |

---

## Estado actual de los puntos

| Cuenta | DNI | Puntos acumulados | Canjeados | Recuperables |
|---|---|---|---|---|
| Theito Pirola | 44886521 | 743.000 | 0 | **743.000** |
| Rocío Benítez | 53889136 | 25.000 | 0 | **25.000** |
| Lautaro Crupi | 48050655 | 120.000 | 0 | **120.000** |
| Pedro Portillo | 39772013 | 99.270 | 0 | **99.270** |
| Carlos A. Sihuen Sánchez | 48394358 | 30.000 | 0 | **30.000** |
| Marcela Barrionuevo | 23412314 | 8.000 | 0 | **8.000** |
| Beluuu Ibazeta | 38074410 | 3.000 | 4.000 | 3.000 |
| **Total** | | **1.028.270** | **4.000** | **1.025.270** |

---

## Método del ataque

El atacante dispone de un listado de datos personales de clientes de SmartLoyalty —incluyendo al menos número de DNI— organizado numéricamente. Cada noche procesa un lote del listado en forma automática:

- **Noche 1:** DNIs en rango 26028669–26029388 (26 cuentas)
- **Noche 2:** DNIs en rango 26029436–26029858 (91 cuentas)

Las transferencias se ejecutan cada 4–7 segundos de forma ininterrumpida durante ~40 minutos, lo que descarta operación manual. Las cuentas de origen son clientes reales con años de antigüedad en el sistema — no son cuentas falsas. El origen del listado de datos personales utilizado por el atacante es desconocido y está bajo investigación.

**51 de las 117 transferencias superaron el límite diario de 8.000 puntos** establecido en el reglamento de Club Grido, lo que indica que el sistema no está validando los límites en tiempo real.

---

## Cuentas receptoras (hubs)

Estas cuentas actuaron como puntos de concentración de los puntos sustraídos y deben ser suspendidas de inmediato:

| Nombre | DNI | Email | Rol |
|---|---|---|---|
| Lautaro Crupi | 48050655 | lautarocrupi8@gmail.com | Hub N1 — recibió y redistribuyó |
| Pedro Portillo | 39772013 | portillopedro096@gmail.com | Hub N1 — acumulador |
| Theito Pirola | 44886521 | pirola.theo@gmail.com | Hub N2 — acumulador (743.000 pts) |
| Rocío Benítez | 53889136 | rorrorocio17@gmail.com | Hub N2 secundario — recibió de 2 cuentas outlier (25.000 pts) |
| Carlos A. Sihuen Sánchez | 48394358 | agus.sanchezz649@gmail.com | Receptor final N1 |
| Marcela Barrionuevo | 23412314 | marcelabarrionuevo935@gmail.com | Receptor N1 |
| Beluuu Ibazeta | 38074410 | bel.5@icloud.com | Receptor N1 — ya canjeó |

---

## Acciones recomendadas

### Inmediatas (antes de las 02:30 de esta noche)

1. **Suspender la función de transferencia de puntos** en la plataforma hasta nuevo aviso.
2. **Bloquear o suspender las 6 cuentas receptoras** listadas arriba para impedir canjes adicionales.
3. **Revertir los puntos** acumulados en las cuentas receptoras hacia un estado auditado.

### Corto plazo

4. **Implementar validación en tiempo real** del límite diario/semanal/mensual de transferencias (actualmente no se aplica).
5. **Implementar detección de anomalías** en transferencias: múltiples remitentes distintos hacia el mismo receptor en ventanas cortas de tiempo.
6. **Investigar el origen del listado de datos personales** utilizado por el atacante para prevenir futuros ataques del mismo tipo.

---

## Archivos de evidencia

### Carpeta: `events/20260515_fraude_evidencia/`

| Archivo | Contenido |
|---|---|
| `01_queries_investigacion.sql` | Todas las consultas ejecutadas durante la investigación (Q1–Q6) |
| `02_noche1_transferencias.csv` | Detalle de los 33 participantes de la Noche 1 con rol, puntos e identidad |
| `03_noche2_emisores.csv` | Detalle de los 91 emisores de la Noche 2 con puntos y estado de límite |

### Exportar evidencia cruda de PointsLog
Ejecutar la consulta **Q6** del archivo `01_queries_investigacion.sql` en SSMS con "Results to File" para obtener el CSV completo de los registros originales de `sml.CustomerPointsLog` de ambas noches.

### Incidente separado
- `events/20260514_lucas_query_sfsqlusrit.sql` — consulta ejecutada manualmente en producción por cuenta de QA

---

*Análisis realizado con datos del sistema de monitoreo interno (PNSSRL) y la base de datos de producción (SmartFran.Solution.SmartLoyalty).*
