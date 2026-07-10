# Clúster de Fraude "Brainrot" — Transferencias y Abuso de Bono de Bienvenida

**Fecha de detección:** 2026-06-12
**Período investigado:** Febrero 2026 – Junio 2026
**Base de datos:** `SmartFran.Solution.SmartLoyalty`
**Estado:** Análisis Naza Rdz y Bruno Mdm completado — cierre pendiente (suspensiones + reversiones)

---

## 1. Resumen Ejecutivo

Se detectó un clúster de cuentas sintéticas con nombres de personajes del meme "Italian Brainrot" (fenómeno viral 2025) y DNIs con dígito repetido o fuera de rango válido argentino. El patrón de registro es distinto al de la Red Batman (sin bloque DNI secuencial, sin emails de familia común), lo que indica un operador diferente o un subgrupo operando con convenciones propias.

Se identificaron tres tipos de abuso: (1) relay de transferencias con bypass de límite diario, (2) abuso de bono de bienvenida con canje inmediato, (3) uso de CustomerId como cliente por defecto en terminales POS. La cadena principal fluye desde una cuenta desactivada (origen Chaco) hacia Tung Tung Sambayone y de allí a dos cashout: Naza Rdz (30.000 pts — 12.250 recuperables) y Bruno Mdm (8.000 pts — 545 recuperables + cashout masivo preexistente independiente del clúster).

**Total puntos en el esquema (confirmado):** ~161.000 pts
**Irrecuperable confirmado:** ~139.450 pts
**Recuperable confirmado:** 16.275 pts activos + 1.825 pts retenidos = **18.100 pts total**

---

## 2. Métricas Globales

| Métrica | Valor |
|---|---|
| Ventana activa | Feb 2026 – Jun 2026 |
| Cuentas sintéticas confirmadas | 8 (Tung Tung, Bruno Mdm, Tuntuntuntun Sahur, Tralalero Tralala, desactivada 5DB72B42, desactivada C34B7D32, Naza Rdz, Facundo Ietta) |
| Patrón de nomenclatura | Personajes Italian Brainrot (meme 2025) — actores centrales |
| DNIs inválidos | 18181818 (dígito repetido), 24242424 (dígito repetido), 341688840 (imposible — >300M AR) |
| Total distribuido por cadena principal | ~65.000 pts (Tung Tung: 27.000 recv + 38.000 sent) |
| Total abuso de bono de bienvenida | ~10.000 pts (2 cuentas × 5.000 pts) |
| Total canjeado confirmado | ~139.450 pts |
| Saldo recuperable confirmado | 16.275 pts activos + 1.825 pts retenidos |
| Franquicia de origen (cuenta desactivada) | 3822 ROQUE S. PEÑA II — Pereyra, Diego (Chaco) |
| Canal de abuso principal | APP |

---

## 3. Red de Actores

### 3.1 Cuenta Desactivada — Feeder de Cadena Principal

| Campo | Valor |
|---|---|
| CustomerId | `5DB72B42-AB4F-C9CD-1AD3-08DB103601B5` |
| Identidad | Scrubbed — todos los campos PII reemplazados con el CustomerId GUID |
| Canal de registro | PUNTO DE VENTA — Sucursal 3822 ROQUE S. PEÑA II |
| Franquiciado | Pereyra, Diego (Chaco) |
| CreatedDate | 2023-02-16 |
| Primera actividad | 2022-11-05 (anterior al CreatedDate — posible uso como CustomerId POS por defecto previo al registro formal) |
| Última actividad | 2026-05-23 16:21 UTC-3 — coincide exactamente con el último transfer a Tung Tung |
| Transferido a Tung Tung | 27.000 pts en 62 segundos (4 transfers APP — 8K + 8K + 8K + 3K) |
| Estado | Desactivada después de los transfers — no antes. Sin bug de plataforma: transfers ejecutados antes de la desactivación. |

### 3.2 Actores Brainrot — Cadena Principal

| Cuenta | DNI | Email | Rol | Saldo actual | Señales de fraude |
|---|---|---|---|---|---|
| Tung Tung Sambayone | 18181818 | tatianasegovia2005@gmail.com | relay_hybrid | **2.830** | DNI dígito repetido; email no coincide con nombre; POS default CustomerId (burst 0 pts Feb 1 y Abr 28); burst receive 27K en 62 seg; burst send 30K en 67 seg con bypass de límite |
| Naza Rdz | 46652579 | nazarenojererodriguez@gmail.com | cashout_mula | **12.250** | Cuenta creada Jun 4 a las 12:20 UTC-3 en POS 4513 LANUS OESTE II — 1er transfer recibido 9 min 23 seg después (12:30 UTC-3). Sin actividad orgánica. Email name-matched. 9 canjes Jun 4–11. |
| Bruno Mdm | 24242424 | clashroyale.rocale@gmail.com | cashout_mula | **545** | DNI dígito repetido — inválido desde registro en POS 3375 LA RIOJA VIII (Sep 2023). Cashout masivo iniciado May 25 2026, 12 días antes del transfer de Tung Tung. Envió 1.500 pts a Facundo Ietta (40302714) el Jun 7. Insider en Branch 3375 a investigar. |

### 3.3 Actores Brainrot — Abuso de Bono de Bienvenida

| Cuenta | DNI | Email | Patrón | Pts abusados | Irrecuperable |
|---|---|---|---|---|---|
| Tuntuntuntun Sahur | 341688840 | pixovi6952@bultoc.com | One-shot: registro → bono +5.000 → canje inmediato (8 minutos). Cuenta inactiva. DNI imposible (>300M). Email dominio desechable (`bultoc.com`). | 5.000 | **5.000** |
| Tralalero Tralala | 51447556 | exealejgonzalez@gmail.com | Funnel: registro → bono +5.000 → relay a C34B7D32 desactivada (Mar 6 2026, 16 min). | 5.000 | **3.990** (1.010 RETENIDOS en C34B7D32) |

### 3.4 Actores Periféricos

| Cuenta | DNI / CustomerId | Rol | Saldo | Señales |
|---|---|---|---|---|
| C34B7D32 (desactivada) | C34B7D32-4722-CC2B-EA17-08DE40DEF711 | relay_destino | **1.010 RETENIDOS** | Recibió 5.000 pts de Tralalero Tralala el Mar 6 2026 vía APP. Gastó ~3.990 pts antes de desactivación. Último movimiento: May 16 2026. 1.010 pts frozen en smlst — admin-reversible por CustomerId. |
| Facundo Ietta | 40302714 | receptor_menor | **650 activos** | Recibió 1.500 pts de Bruno Mdm el Jun 7 22:32 UTC-3 vía APP. Email facu.ietta24@gmail.com (name-matched). Gastó ~850 pts en 56 min (último movimiento: 23:28 UTC-3). Bajo impacto. |

---

## 4. Contabilidad de Puntos

Datos confirmados por Q_VALIDATE_BALANCES_ALL, Q_VALIDATE_SPENT_TRANSFERRED (2026-06-13) y Q_ORIGIN / Q3–Q5 historial completo (2026-06-13).

| Actor | DNI | Rol | Origen (Canal / Fecha / Sucursal) | Email_Flag | Pts Recibidos | Gastados | Transferidos (salientes) | Activos | Retenidos |
|---|---|---|---|---|---|---|---|---|---|
| 5DB72B42 (desactivada) | scrubbed | feeder | POS 3822 ROQUE S. PEÑA II / feb 2023 (Pereyra, Diego — Chaco) | NO_EN_MAILING | — | **3.000** (1 canje) | 27.000 (4 envíos → Tung Tung) | — | **815** |
| Tung Tung Sambayone | 18181818 | relay_hybrid | pendiente de query | NO_EN_MAILING | 27.000 (4 transf.) | **19.000** (7 canjes) | 38.000 (6 envíos → Naza Rdz + Bruno Mdm) | **2.830** | — |
| Naza Rdz | 46652579 | cashout_mula | POS 4513 LANUS OESTE II / 2026-06-04 / FG 4598F376 | NO_EN_MAILING | 30.000 (5 transf.) | **17.750** (9 canjes) | 0 | **12.250** | — |
| Bruno Mdm | 24242424 | cashout_mula | POS 3375 LA RIOJA VIII / 2023-09-01 / FG 9E2895B1 | NO_EN_MAILING | 8.000 (1 transf.) | **110.700** (spree May–Jun 2026 preexiste al transfer de Tung Tung + canjes 2023–2024) | 1.500 (1 envío → Facundo Ietta 40302714) | **545** | — |
| Tuntuntuntun Sahur | 341688840 | one-shot | APP / feb 2026 | **DOMINIO_DESECHABLE** (bultoc.com) | 5.000 bono | **5.000** (1 canje) | 0 | 0 | — |
| Tralalero Tralala | 51447556 | funnel | APP / mar 2026 | NO_EN_MAILING | 5.000 bono | 0 | 5.000 (1 envío → C34B7D32 desactivada, Mar 6 2026) | 0 | — |
| C34B7D32 (desactivada) | scrubbed | relay_destino | desconocido | NO_EN_MAILING | 5.000 (1 transf. de Tralalero) | **~3.990** (gastados antes de desactivación) | desconocido | — | **1.010** |
| Facundo Ietta | 40302714 | receptor_menor | desconocido | NO_EN_MAILING | 1.500 (1 transf. de Bruno Mdm, Jun 7) | **~850** | 0 | **650** | — |

**Nota — Bruno Mdm (24242424):** El cashout masivo (May 25 – Jun 7 2026, ~84.200 pts en 14 días) comenzó 12 días antes del transfer de Tung Tung (Jun 6). El Jun 1 se registraron 18.500 pts canjeados en una sola transacción (SaleId 252089151, 16 filas al mismo timestamp). La acumulación previa (2023–2025) es orgánica: distintos SaleIds, montos variados, spread temporal — NO es patrón de CustomerId POS por defecto. DNI 24242424 era inválido desde el registro original en POS 3375 → insider a investigar.

**Nota — C34B7D32:** Recibió 5.000 pts de Tralalero el Mar 6 2026. Gastó ~3.990 pts antes de ser desactivada. 1.010 pts RETENIDOS en smlst — admin-reversibles por CustomerId.

**Resumen por estado (confirmado al 2026-06-13):**

| Estado | Puntos | Acción |
|---|---|---|
| Gastados — irrecuperables | **~139.450 pts** | Sin acción posible |
| Activos — recuperables | **16.275 pts** | Suspender + revertir (Naza Rdz 12.250 + Tung Tung 2.830 + Bruno Mdm 545 + Facundo Ietta 650) |
| Retenidos — cuentas desactivadas | **1.825 pts** | Reversión admin. por CustomerId (5DB72B42: 815 + C34B7D32: 1.010) |
| Pendiente | 0 | Trazado completo |

---

## 5. Patrón de Fraude

### 5.1 Cadena Principal — Receive-then-flush con Bypass de Límite

```
5DB72B42 (desactivada, ROQUE S. PEÑA II, Chaco)
    ↓ 27.000 pts en 62 seg (4 transfers, May 23 2026)
Tung Tung Sambayone (18181818) — relay hybrid
    ├── canjes propios: ~14.000 pts (May 23–31)
    ├── 30.000 pts en 67 seg a Naza Rdz (46652579)  ← Jun 4 2026
    │       3×8.000 + 800 + 5.200 = bypass de límite
    └── 8.000 pts a Bruno Mdm (24242424)             ← Jun 6 2026
```

El envío de 30.000 pts a Naza Rdz se fraccionó en 3×8.000 + 800 + 5.200: los primeros tres transfieren el límite diario exacto (8K); las dos últimas cubren el remanente dividido para eludir el enforcement. Idéntico al patrón de la Red Batman.

### 5.2 Uso de CustomerId como POS por Defecto

El account de Tung Tung Sambayone acumula ráfagas de `EarnPointsByBuying` con Points = 0 en fechas específicas:

| Fecha | Volumen | Ventana |
|---|---|---|
| 2026-02-01 | 60+ eventos 0 pts | 19:39 – 00:27 (límite diario ya alcanzado) |
| 2026-04-28–29 | múltiples 0 pts | tarde/noche |
| 2026-05-22–23 | múltiples 0 pts | previo al burst de receive |

El patrón (muchas transacciones POS en horario continuo, todas 0 pts) indica que el CustomerId estaba configurado como cliente por defecto en uno o más terminales — mismo patrón detectado en Dimon Briz (DNI 123456, investigación 20260604).

### 5.3 Abuso One-Shot de Bono de Bienvenida

Tuntuntuntun Sahur (341688840) y Tralalero Tralala (51447556): crearon cuentas, recibieron el bono de bienvenida de 5.000 pts (`NewCustomer`), y lo liquidaron en menos de 20 minutos. El abuso de bono de bienvenida no requiere coordinación externa — es explotable con solo registrarse con un DNI sintético y email desechable.

### 5.4 Registro Coordinado el Mismo Día — Naza Rdz

Cuenta creada el Jun 4 a las 12:20:52 UTC-3 en terminal POS (sucursal 4513 LANUS OESTE II). Primer transfer recibido a las 12:30:15 UTC-3 — **9 minutos 23 segundos después del registro**. Primer canje a las 12:34:19 UTC-3 — **2 minutos 57 segundos después del último transfer recibido**. Secuencia: registro coordinado → receive masivo → canje inmediato → cashout gradual (Jun 4–11). Sin actividad orgánica (zero EarnPointsByBuying). Perfil: probable mula real reclutada (nombre y email coinciden; DNI 46652579 es válido para Argentina).

### 5.5 Activación de Cuenta Preexistente — Bruno Mdm

Bruno Mdm (24242424) tiene historial POS desde Sep 2023 en sucursal 3375 LA RIOJA VIII con DNI inválido (24242424) — cuenta sintética desde el origen, registrada en terminal POS. El cashout masivo comenzó el May 25 2026, **12 días antes** del transfer de Tung Tung (Jun 6). Tung Tung sumó 8.000 pts a una cuenta que ya estaba siendo vaciada. El Jun 1 2026 se registró un canje de 18.500 pts en una sola transacción (SaleId 252089151) — anómalo para cualquier cliente legítimo. La cuenta NO sigue el patrón de CustomerId POS por defecto (tiene actividad POS genuina: distintos SaleIds, montos variados, horarios distribuidos). La sucursal 3375 LA RIOJA VIII requiere investigación de insider por la registración con DNI 24242424 en 2023.

---

## 6. Señales de Identidad Sintética

| Señal | Actores afectados |
|---|---|
| DNI con dígito repetido (0 entropía) | Tung Tung (18181818), Bruno Mdm (24242424) |
| DNI imposible para Argentina (>300M) | Tuntuntuntun Sahur (341688840) |
| Email dominio desechable (`bultoc.com`) | Tuntuntuntun Sahur |
| Email sin correspondencia con nombre | Tung Tung (tatianasegovia2005@gmail.com), Bruno Mdm (clashroyale.rocale@gmail.com — gamer handle) |
| Nombre de personaje ficticio (Italian Brainrot meme 2025) | Tung Tung, Tuntuntuntun Sahur, Tralalero Tralala, Bruno Mdm |
| Actividad primera posterior a fecha de registro | 5DB72B42 (nov 2022 < feb 2023) |
| Cuenta creada misma sesión de fraude | Naza Rdz (9 min 23 seg antes del primer transfer recibido) |
| DNI inválido registrado en terminal POS (insider risk) | Bruno Mdm — Branch 3375 LA RIOJA VIII, Sep 2023 |

---

## 7. Acciones Propuestas

### Inmediatas
- [ ] Suspender Naza Rdz (46652579) — saldo 12.250 pts recuperable (**prioridad alta**)
- [ ] Suspender Tung Tung Sambayone (18181818) — saldo 2.830 pts recuperable
- [ ] Suspender Bruno Mdm (24242424) — saldo 545 pts recuperable
- [ ] Suspender Facundo Ietta (40302714) — saldo 650 pts recuperable
- [ ] Revertir saldo 5DB72B42 (815 pts RETENIDOS) — reversión admin por CustomerId
- [ ] Revertir saldo C34B7D32 (1.010 pts RETENIDOS) — reversión admin por CustomerId
- [ ] Bloquear registro de DNIs con dígito repetido en la plataforma (18181818, 24242424, etc.)
- [ ] Agregar `bultoc.com` a blocklist de dominios desechables

### Auditoría
- [ ] Identificar sucursal(es) donde el CustomerId de Tung Tung fue configurado como POS por defecto (Feb 1 y Abr 28–29)
- [ ] Verificar si la cuenta desactivada (5DB72B42) fue detectada por anti-fraude interno o solicitada por el titular real
- [ ] Investigar FranchiseStaff de Sucursal 3822 ROQUE S. PEÑA II (Pereyra, Diego) — descartar complicidad interna en el registro de 5DB72B42
- [ ] Investigar bloque DNI de Bruno Mdm (24242424) — posibles cuentas en cluster 24242421–24242430
- [ ] **Investigar Branch 3375 LA RIOJA VIII (FG 9E2895B1) — identificar operador de terminal POS que registró DNI 24242424 en Sep 2023** (insider confirmado)
- [ ] **Investigar Branch 4513 LANUS OESTE II (FG 4598F376) — quién registró a Naza Rdz en el mismo día de la operación (Jun 4 2026)**
- [ ] Investigar historia completa de C34B7D32 — origen, canjes antes de desactivación, vínculo con operador de Tralalero Tralala
- [ ] Verificar Facundo Ietta (40302714) — confirmar si es contacto personal del operador o receptor recurrente
- [x] Ejecutar Q_BRAINROT_NAZA_BRUNO — historial completo Naza Rdz y Bruno Mdm ✓ 2026-06-13
- [x] Ejecutar Q_BRAINROT_TRALALERO_TRANSFER — destino: C34B7D32 desactivada (1.010 pts RETENIDOS) ✓ 2026-06-13

### Técnicas
- [ ] Limitar canjes del bono de bienvenida: bloquear `DiscountPointsByExchange` por N horas tras `NewCustomer` en cuenta nueva
- [ ] Alertar sobre `NewCustomer` + `DiscountPointsByExchange` en ventana < 30 min
- [ ] Validar DNI en registro: rechazar dígitos repetidos, rangos imposibles para Argentina
- [ ] Alertar sobre cuenta nueva recibiendo transferencia masiva en ventana < 60 min post-registro

---

## 8. Archivos de Evidencia

| Archivo | Contenido | Estado |
|---|---|---|
| `01_queries.sql` | Q_BRAINROT (búsqueda inicial), Q_BRAINROT_TUNGTUNG, Q_TUNGTUNG_TRANSFERS, Q_BRAINROT_SENDER, Q_BRANCHOFFICE_LOOKUP, Q_ORIGIN, Q2_BALANCES, Q3_HISTORIA, Q4_BRUNO_TRANSFER_DEST, Q5_TRALALERO_TRANSFER_DEST | pendiente escritura |
| `02_historial_tung_tung.csv` | 526 filas — historial completo Tung Tung Sambayone (DNI 18181818) | pendiente escritura |
| `03_transfers_tung_tung.csv` | 10 filas — transfers entrantes y salientes de Tung Tung | pendiente escritura |
| `04_historial_naza_bruno.csv` | 951 filas (14 Naza Rdz + 937 Bruno Mdm) — historial completo ambos actores | completado — datos en memoria de investigación |
| `05_tralalero_transfer_destino.csv` | 1 fila — receptor: C34B7D32 desactivada (1.010 pts RETENIDOS) | completado — datos en memoria de investigación |
