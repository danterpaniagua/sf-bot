# Cierre de Investigación — Fraude de Transferencias
**Fecha:** 2026-06-03  
**Tipo de incidente:** Fraude de transferencias — dos vectores simultáneos  
**Vector 1:** Credential stuffing + red de consolidación  
**Vector 2:** Mal uso de puntos de beneficio de empleados  
**Investigador:** DBA / SRE  
**Estado:** Pendiente acción operativa — saldos críticos aún intactos  
**JIRA Epic:** [GITIN-1275](https://smartit-ar.atlassian.net/browse/GITIN-1275) — epic raíz de fraude de puntos Smart Loyalty

---

## 1. Métricas del evento

### Ventana reportada (07:00–08:00 UTC-3, 2026-06-03)

| Métrica | Valor |
|---|---|
| Transferencias en ventana | 2 |
| Puntos totales en ventana | 16.000 |
| Emisores únicos | 2 |
| Receptores únicos | 2 |
| Canal | APP |
| Resultado | Empleados de Grido → receptores externos (ver Vector 2) |

### Scope total del día 2026-06-03

| Métrica | Valor |
|---|---|
| Transferencias totales bajo análisis | 7 |
| Puntos totales transferidos | 76.000 |
| Cuentas comprometidas (emisores involuntarios) | 12 |
| Hubs identificados | 2 (Homer Spo, Lucas Riquelme) |
| Vectores de fraude | 2 |
| Saldo crítico intacto — Lucas Riquelme | **50.000 pts** |
| Saldo crítico intacto — Nahir Niz | **40.005 pts** |

---

## 2. Desglose por EventTypeCode — ventana reportada

| EventTypeCode | Eventos | Puntos |
|---|---|---|
| PointsByTransferSent | 2 | -16.000 |
| PointsByTransferReceived | 2 | 16.000 |

---

## 3. Detalle de participantes — ventana reportada 07:00–08:00 UTC-3

| TransfId | Fecha UTC-3 | Canal | Emisor | Documento | Pts | Receptor | Documento | Rol Emisor |
|---|---|---|---|---|---|---|---|---|
| 286299 | 07:20 | APP | Matias Ezequiel Roggio | DNI 37195561 | 8.000 | Aldana Vivas | DNI 38329585 | Empleado Grido — Colaborador Permanente |
| 286300 | 07:25 | APP | Julia Roquelina Cuccaro | DNI 4826910 | 8.000 | Carlos Daniel Sancho | DNI 24545466 | Empleada Grido — Colaboradora Temporal |

---

## 4. Vector 1 — Credential stuffing + red de consolidación

### 4.1 Esquema

```
12 cuentas comprometidas
  (credenciales robadas, drenaje total, canal WEB)
           │
           ▼
     Homer Spo (DNI 43541207)     ← agregador / hub
     100% PointsByTransferReceived
     Sin actividad orgánica
           │
           ▼ (WEB, 01:52 UTC-3, transfer único de 30.000 pts)
     Lucas Riquelme (DNI 44238411)   ← pass-through
     Saldo actual: 50.000 pts
     Redistribución pendiente
```

### 4.2 Transferencias hacia Homer Spo (origen del drenaje)

| Fecha UTC-3 | Emisor | Documento | Pts enviados | Saldo post | Canal | Fecha registro |
|---|---|---|---|---|---|---|
| 2026-05-25 22:30 | Juan Jose Beraldi | DNI 11455315 | 8.660 | **0** | WEB | 2020-03-11 |
| 2026-05-25 22:32 | Ulises Gabriel Domínguez Herrera | DNI 40735388 | 4.119 | 1 | WEB | 2018-12-03 |
| 2026-05-25 22:34 | Sofia Gomez | DNI 44970351 | 1.425 | **0** | WEB | 2020-04-17 |
| 2026-05-25 22:35 | Maria Angelica Banchero | DNI 25704650 | 6.700 | 85 | WEB | 2024-04-14 |
| 2026-05-25 22:37 | Natalia Walker | DNI 33496563 | 4.999 | 106 | WEB | 2016-10-17 |
| 2026-05-27 19:46 | Maria Del Milagro Cagna Vallino | DNI 13414602 | 5.600 | **0** | WEB | 2025-02-26 |
| 2026-05-27 19:47 | Martin Pereyra | DNI 32724511 | 2.700 | 35 | WEB | 2018-08-06 |
| 2026-05-27 19:51 | Lucas Gimenez | DNI 34909531 | 3.999 | 191 | WEB | 2016-09-21 |
| 2026-05-27 20:01 | Daniel Emilio Fiorotto | DNI 37564840 | 8.000 | 690 | WEB | 2017-07-21 |
| 2026-05-27 20:05 | Luana Valentina Basualdo Filomarino | DNI 42897117 | 6.999 | 451 | WEB | 2024-02-24 |
| 2026-06-02 23:44 | Leonardo Della Nave | DNI 42022733 | 3.000 | 280 | WEB | 2016-01-22 |
| 2026-06-02 23:46 | Karla Valentina Quintero | DNI 95802540 | 3.800 | 65 | WEB | 2025-03-11 |

**Total drenado → Homer Spo:** 60.001 pts (3 sesiones)

> **Señales de credential stuffing confirmadas:**
> - Todos los envíos vía WEB (no APP)
> - Montos irregulares no redondos = balance exacto disponible de la cuenta
> - Cuentas de distintas fechas de registro (2016–2025) y distintos canales — sin patrón de registro coordinado
> - 7 de 12 cuentas quedaron con saldo = 0 o ≤ 106 pts
> - Homer Spo tiene cero actividad orgánica — puro receptor de transferencias

> **Alerta:** Leonardo Della Nave (DNI 42022733) recibió 30.000 pts de `CompensationalPoints` por GSFERNANDEZ (ManualAssignId 7361, 2025-08-07). Requiere investigación de posible superposición entre vectores.

### 4.3 Dump de Homer Spo → Lucas Riquelme

| TransfId | Fecha UTC-3 | Canal | Emisor | Receptor | Pts | Saldo receptor |
|---|---|---|---|---|---|---|
| 286296 | 2026-06-03 01:52 | WEB | Homer Spo (DNI 43541207) | Lucas Riquelme (DNI 44238411) | 30.000 | **50.000** |

> **Límite aplicable:** Homer Spo no tiene actividad orgánica ni historial de `HumanResourcesPoints` — es un **Cliente**, no Colaborador. Límite diario de transferencia para clientes: **8.000 pts** (`CustomerPointsMinLimitTransfer`). Su transfer de 30.000 pts es 3,75× el límite. Violación confirmada.

### 4.4 Historial de Lucas Riquelme — patrón pass-through

| Fecha UTC-3 | Evento | Pts |
|---|---|---|
| 2026-05-16 23:02–23:03 | Recibió 3 transfers en 30 segundos | +38.000 |
| 2026-05-20–25 | Redistribuyó | -18.000 |
| 2026-06-03 01:52 | Recibió de Homer Spo | +30.000 |
| 2026-06-03 (actual) | Sin movimientos desde recepción | **50.000 intactos** |

---

## 5. Vector 2 — Mal uso de beneficio de empleados

### 5.1 Esquema

```
Empleados Grido (HumanResourcesPoints ~20.000 pts/mes)
           │
           ├── Matias Ezequiel Roggio (Permanente) ──► Aldana Vivas (DNI 38329585)
           │   Saldo actual: 145.550 pts
           │
           ├── Julia Roquelina Cuccaro (Temporal) ──► Carlos Daniel Sancho (DNI 24545466)
           │
           └── Carlos Andrés Roldan (Permanente) ────► Nahir Niz (DNI 46374837)
               4 transfers en 93 segundos (scripted)    Beneficiaria crónica — 14+ meses
               30.000 pts — límite diario 8.000 pts
```

### 5.2 Detalle de transferencias del día — Roldan

| TransfId | Hora UTC-3 | Canal | Pts | Intervalo |
|---|---|---|---|---|
| 286308 | 12:08:57 | APP | 8.000 | — |
| 286309 | 12:09:27 | APP | 8.000 | 30 seg |
| 286310 | 12:10:05 | APP | 8.000 | 38 seg |
| 286311 | 12:10:30 | APP | 6.000 | 25 seg |

4 transferencias en **93 segundos** — cadencia automatizada. Todas al mismo receptor.

> **Nota sobre límites:** Roldan es Colaborador Permanente. El límite diario de transferencia para colaboradores es **30.000 pts** (`ColaboratorPointsMinLimitTransfer`, `Sml.LocationAttributeValue`). Su total de 30.000 pts está en el límite diario, no por encima. La violación aquí es la **cadencia automatizada y la política de uso** (transferencia a no empleado), no el monto.

### 5.3 Historial de Nahir Niz — receptora crónica

| Período | Transfers recibidas | Pts recibidos | Cadencia | Canjeó después |
|---|---|---|---|---|
| 2025-03-01 | 1 | 8.000 | — | Mar 2025 |
| 2025-04-09 | 3 | 24.000 | 44 seg | Abr 2025 |
| 2025-05-19–22 | 4 | 30.000 | spread | May 2025 |
| 2025-12-29 | 3 | 24.000 | **35 seg** | Ene 2026 |
| 2026-04-09 | 2 | 16.000 | 1 min | Abr/May 2026 |
| 2026-06-03 | 4 | 30.000 | **93 seg** | — (intactos) |

**Total recibido por Nahir Niz vía transfers:** ~132.000 pts en 14 meses.  
**Saldo actual:** 40.005 pts — no canjeados desde hoy.

---

## 6. Saldos críticos — reversión aún posible

| Cuenta | Documento | Saldo actual | Origen hoy | Reversión posible |
|---|---|---|---|---|
| Lucas Riquelme | DNI 44238411 | **50.000** | 30.000 de Homer Spo | Sí |
| Nahir Niz | DNI 46374837 | **40.005** | 30.000 de Roldan | Sí |

---

## 7. Acciones requeridas

### Inmediatas (saldos intactos)

| # | Acción | Responsable | Estado |
|---|---|---|---|
| 1 | Suspender cuenta Homer Spo (DNI 43541207) | Operaciones | Pendiente |
| 2 | Suspender cuenta Lucas Riquelme (DNI 44238411) — bloquear redistribución de 50.000 pts | Operaciones | Pendiente |
| 3 | Revertir o retener los 30.000 pts en Lucas Riquelme | Operaciones | Pendiente |
| 4 | Evaluar retención de 30.000 pts en Nahir Niz (Roldan) | Operaciones | Pendiente |

### Cuentas comprometidas (credential stuffing)

| # | Acción | Responsable | Estado |
|---|---|---|---|
| 5 | Invalidar sesiones activas de las 12 cuentas comprometidas | Seguridad | Pendiente |
| 6 | Notificar a los 12 titulares sobre el acceso no autorizado | Customer Service | Pendiente |
| 7 | Restituir puntos drenados a las cuentas comprometidas | Operaciones | Pendiente |
| 8 | Investigar Leonardo Della Nave (DNI 42022733) — posible superposición con GSFERNANDEZ | DBA | Pendiente |

### Vector 2 — Empleados

| # | Acción | Responsable | Estado |
|---|---|---|---|
| 9 | Escalar a RRHH: Roggio, Cuccaro, Roldan transfirieron beneficio a externos | RRHH | Pendiente |
| 10 | Determinar si el reglamento interno prohíbe la transferencia de HumanResourcesPoints a no empleados | Legal / RRHH | Pendiente |
| 11 | Evaluar si Nahir Niz actuó conscientemente (beneficiaria recurrente desde mar-2025) | Legal | Pendiente |

### Técnicas

| # | Acción | Responsable | Estado |
|---|---|---|---|
| 12 | Implementar validación de límites de transferencia en tiempo real (diario 8k / semanal 10k / mensual 13k) | Desarrollo | Pendiente |
| 13 | Agregar detección de cadencia: > 2 transfers al mismo receptor en < 5 min = bloqueo automático | Desarrollo | Pendiente |
| 14 | Alertas sobre cuentas con 100% PointsByTransferReceived y cero actividad orgánica | Seguridad | Pendiente |
| 15 | Revisar si HumanResourcesPoints debe tener restricción de transferencia | Desarrollo / RRHH | Pendiente |

---

## 8. Glosario

| Término | Definición |
|---|---|
| **Credential stuffing** | Ataque en el que un actor malicioso utiliza combinaciones de usuario y contraseña obtenidas de filtraciones de datos (data breaches) para acceder a cuentas de terceros. Las cuentas no fueron atacadas directamente — sus credenciales estaban previamente comprometidas en otra plataforma. |
| **Drenaje de cuenta** | Acción de transferir el saldo completo disponible de una cuenta a otra. Produce montos irregulares (no redondos) porque el atacante envía exactamente lo que hay disponible. Señal característica del credential stuffing. |
| **Hub / Cuenta hub** | Cuenta que actúa como punto de concentración: recibe puntos de múltiples emisores y los agrupa antes de reenviarlos. No tiene actividad orgánica propia (sin compras en POS). |
| **Pass-through** | Cuenta intermediaria que recibe puntos de un hub y los redistribuye rápidamente a otros destinos. Su función es dificultar el rastreo del origen de los fondos. |
| **Fan-in** | Patrón de fraude en el que múltiples cuentas distintas envían puntos a un único receptor en un período corto. Indica consolidación deliberada. |
| **Cadencia automatizada** | Serie de transferencias ejecutadas en intervalos de segundos, imposibles de replicar manualmente. Indica el uso de un script o bot. En este caso: 4 transfers en 93 segundos. |
| **Vector** | Vía o método mediante el cual se ejecuta el fraude. Este evento tiene dos vectores independientes: credential stuffing (Vector 1) y mal uso de beneficio de empleados (Vector 2). |
| **PointsByTransferReceived** | Código de evento en `sml.CustomerPointsLog` que registra la recepción de puntos mediante una transferencia entre cuentas. Siempre positivo. |
| **PointsByTransferSent** | Código de evento que registra el envío de puntos en una transferencia. Siempre negativo. Cada transferencia genera exactamente un par Sent/Received vinculado por `sml.PointsTransference`. |
| **DiscountPointsByExchange** | Código de evento que registra el canje de puntos por productos o beneficios. Siempre negativo. Indica que el usuario usó sus puntos en el sistema. |
| **HumanResourcesPoints** | Canal de asignación manual destinado exclusivamente a empleados de Grido. Los puntos se asignan mensualmente desde listas de colaboradores. Legítimo — no forma parte del exploit de CompensationalPoints. |
| **EarnPointsByBuying** | Código de evento que registra puntos ganados por una compra en punto de venta (POS). Indica actividad orgánica real del cliente. |
| **Actividad orgánica** | Puntos generados por el uso natural de la plataforma: compras, promociones, etc. Una cuenta sin actividad orgánica (solo transferencias) es una señal de que se creó o usa exclusivamente como instrumento de fraude. |
| **ManualAssignPointsId** | Clave foránea en `sml.CustomerPointsLog` que vincula el evento con un registro en `sml.ManualAssignPoints`. Presente únicamente en asignaciones manuales realizadas por operadores. |
| **smlst.CustomerPointsLog** | Tabla de saldos actuales. Contiene una fila por cliente con el total de puntos disponibles (`Points`) y la fecha del último movimiento (`LastLogDate`). Es la fuente más rápida para verificar el saldo actual de una cuenta. |
| **SourceChannel** | Canal desde el cual se ejecutó la transferencia: `WEB` (navegador), `APP` (aplicación móvil). En el credential stuffing, todas las transferencias salientes de las cuentas comprometidas fueron por WEB. |
| **RegistrationChannel** | Canal por el cual se registró originalmente la cuenta: `WEB`, `APP` o `PUNTO DE VENTA`. Sirve para detectar registros masivos coordinados desde el mismo canal. |
| **Límite diario de transferencia** | Máximo de 8.000 puntos que un cliente puede enviar en un día calendario (UTC-3). **No se aplica en tiempo real** — el sistema no bloquea transfers que lo superan. |
| **Límite mensual de transferencia** | Máximo de 13.000 puntos que un cliente puede enviar en un mes calendario. Tampoco se aplica en tiempo real. |
| **Saldo intacto** | Puntos aún no canjeados ni redistribuidos desde que fueron recibidos. Indica que la reversión es técnicamente posible si se actúa antes de que el receptor use o reenvíe los puntos. |
