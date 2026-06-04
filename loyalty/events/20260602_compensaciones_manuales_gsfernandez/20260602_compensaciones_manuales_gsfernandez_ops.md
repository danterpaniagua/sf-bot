# Cierre de Investigación — Explotación de Asignaciones Manuales GSFERNANDEZ
**Fecha:** 2026-06-02  
**Operador investigado:** GSFERNANDEZ  
**Tipo de incidente:** Exploit — ausencia de techo técnico en `sml.ManualAssignPoints`  
**Investigador:** DBA / SRE  
**Estado:** Pendiente decisión de operaciones

---

## 1. Métricas del evento

### Ventana reportada (06:00–08:00 UTC-3, 2026-06-02)

| Métrica | Valor |
|---|---|
| Eventos totales | 25 |
| Puntos totales | 4.555 |
| Ventana activa | 07:19–07:45 UTC-3 (26 minutos) |
| Clientes únicos | 7 |
| Transacciones POS | 21 |
| Asignaciones manuales | 0 |
| Transferencias | 0 |
| Límites superados | 0 |
| **Resultado** | **Sin anomalías — actividad POS normal** |

### Asignaciones manuales GSFERNANDEZ — 2026-06-01 / 2026-06-02

| Métrica | Valor |
|---|---|
| Eventos totales | 9 |
| Puntos totales asignados | 63.200 |
| Ventana activa | 2026-06-01 08:59 UTC-3 → 2026-06-02 13:13 UTC-3 |
| Clientes únicos | 9 |
| Cuentas con límites superados | 3 |
| Puntos en cuentas comprometidas | 45.300 |
| Saldos intactos (reversión posible) | Sí — todos |

### Alcance histórico del exploit — 2023-02-09 → 2026-06-02

> **Nota sobre canales:** `HumanResourcesPoints` e `InstitutionalPoints` son canales de empleados de Grido — excluidos del análisis de exploit. `PrizePoints` está pendiente de verificación.

| Métrica | Valor |
|---|---|
| Total asignaciones (todos los conceptos) | 6.470 |
| — HumanResourcesPoints (canal RRHH — excluido) | 51 asignaciones / 437.000 pts |
| — InstitutionalPoints (canal empleados — excluido) | 127 asignaciones / 1.992.700 pts |
| **Total asignaciones bajo análisis** | **6.292** |
| **Total puntos bajo análisis** | **58.989.571** |
| Asignaciones CompensationalPoints | 6.007 |
| Puntos CompensationalPoints | **58.032.331** |
| Asignaciones PrizePoints (verificación pendiente) | 285 / 958.240 pts |
| Asignaciones que superan límite diario (> 3.000 pts) | **4.677 (77,9%)** |
| Puntos en exceso sobre límite diario | **41.576.326** |
| Asignaciones que superan límite mensual en un solo grant (> 10.000 pts) | **1.333 (22,2%)** |
| Mayor grant individual | **165.000 pts** |
| Período activo | 3 años y 4 meses |
| Volumen mensual inicial (feb-2023) | ~263.700 pts |
| Volumen mensual pico (mar-2026) | **~3.324.186 pts (12,6× inicial)** |

---

## 2. Desglose por EventTypeCode

### Ventana reportada (06:00–08:00 UTC-3, 2026-06-02)

| EventTypeCode | Eventos | Puntos |
|---|---|---|
| EarnPointsByBuying | 21 | 4.555 |
| EarnPointsByPromotion | 3 | 0 |
| Article99999WithoutPoints | 1 | 0 |
| **Total** | **25** | **4.555** |

### Asignaciones manuales históricas — GSFERNANDEZ (todos los conceptos)

| AssignmentConcept | Asignaciones | Puntos Total | Promedio | Máximo | Estado |
|---|---|---|---|---|---|
| CompensationalPoints | 6.007 | 58.032.331 | 9.660 | 165.000 | **Exploit confirmado** |
| PrizePoints | 285 | 958.240 | 3.362 | 30.000 | Pendiente verificación |
| InstitutionalPoints | 127 | 1.992.700 | 15.690 | 76.000 | Canal empleados — legítimo |
| HumanResourcesPoints | 51 | 437.000 | 8.568 | 33.000 | Canal RRHH — legítimo |
| **Total bajo análisis** | **6.292** | **58.989.571** | — | — | excl. RRHH e Institucional |

---

## 3. Detalle por cliente — Ventana reportada 06:00–08:00 UTC-3

| Cliente | Documento | EventTypeCode | Transacciones | Puntos |
|---|---|---|---|---|
| Emiliano Casadio | 30544063 | EarnPointsByBuying | 3 | 1.900 |
| Daiana Diaz | 36793447 | EarnPointsByBuying | 3 | 850 |
| Jesica Galván | 36793456 | EarnPointsByBuying | 4 | 580 |
| German Zanier | 27065746 | EarnPointsByBuying | 1 | 500 |
| Juan Marcelo Barrera | 31404957 | EarnPointsByBuying | 3 | 430 |
| Carlos Mansilla | 27395557 | EarnPointsByBuying | 5 | 165 |
| Cristian Emanuel Cejas | 47713718 | EarnPointsByBuying | 2 | 130 |
| Emiliano Casadio | 30544063 | EarnPointsByPromotion | 1 | 0 |
| Daiana Diaz | 36793447 | EarnPointsByPromotion | 1 | 0 |
| Carlos Mansilla | 27395557 | EarnPointsByPromotion | 1 | 0 |
| Juan Marcelo Barrera | 31404957 | Article99999WithoutPoints | 1 | 0 |

---

## 4. Detalle de asignaciones manuales — 2026-06-01 / 2026-06-02

| Fecha UTC-3 | Cliente | Documento | ManualAssignId | Puntos | Límite superado |
|---|---|---|---|---|---|
| 2026-06-01 08:59 | Oscar Stuht | 40152484 | 9399 | **27.000** | Diario / Semanal / Mensual |
| 2026-06-01 09:30 | Dafna Drazic | 35631298 | 9400 | 3.000 | — |
| 2026-06-01 09:32 | Micaela Greggio | 41993019 | 9401 | **6.400** | Diario |
| 2026-06-01 10:25 | Jonathan Escudero | 33964642 | 9402 | 1.500 | — |
| 2026-06-01 14:22 | Sabrina Aguirre | 48893184 | 9403 | **5.000** | Diario |
| 2026-06-01 14:24 | Ignacio Ponce | 44506544 | 9404 | 2.000 | — |
| 2026-06-02 09:54 | Gabriela Lubrano | 95020263 | 9411 | **5.300** | Diario / Semanal |
| 2026-06-02 11:54 | Facundo Martin Gabriele | 34000952 | 9412 | **10.000** | Mensual (cap total) |
| 2026-06-02 13:13 | Jonathan Passi | 34682755 | 9413 | 3.000 | — |

---

## 5. Estado de saldos — Cuentas con límites superados (Jun 1–2)

| Cliente | Documento | CustomerId | Saldo actual | Puntos asignados | Reversión posible |
|---|---|---|---|---|---|
| Oscar Stuht | 40152484 | 2D0F3972-7907-C101-0EFE-08DAABEF4518 | 27.550 | 27.000 | Sí |
| Gabriela Lubrano | 95020263 | 03BD397B-1A6A-C4BD-6F7E-08D75A58CC66 | 9.205 | 5.300 | Sí |
| Facundo Martin Gabriele | 34000952 | AEEBEE7F-FBCA-C18F-12C7-08D59A9863AA | 17.845 | 10.000 | Sí |

**Total en cuentas comprometidas (Jun 1–2):** 45.300 pts — no canjeados.

---

## 6. Alcance del exploit

### 6.1 Evolución mensual de volumen (CompensationalPoints)

| Mes | Asignaciones | Puntos Total | Sobre límite diario | Sobre límite mensual | Mayor grant |
|---|---|---|---|---|---|
| 2023-02 | 26 | 263.700 | 19 | 9 | 40.000 |
| 2023-03 | 107 | 796.250 | 76 | 15 | 27.000 |
| 2023-04 | 78 | 701.450 | 61 | 21 | 33.000 |
| 2023-05 | 74 | 666.300 | 62 | 19 | 22.000 |
| 2023-06 | 72 | 543.250 | 52 | 7 | 20.000 |
| 2023-07 | 54 | 377.900 | 33 | 11 | 20.000 |
| 2023-08 | 83 | 573.200 | 57 | 11 | 20.000 |
| 2023-09 | 102 | 988.290 | 79 | 38 | 30.000 |
| 2023-10 | 135 | 1.341.700 | 99 | 38 | 36.000 |
| 2023-11 | 128 | 1.105.850 | 109 | 21 | 33.000 |
| 2023-12 | 111 | 1.137.715 | 87 | 27 | 30.000 |
| 2024-01 | 154 | 1.019.880 | 108 | 6 | 22.000 |
| 2024-02 | 111 | 846.300 | 98 | 5 | 20.000 |
| 2024-03 | 126 | 1.036.050 | 119 | 6 | 20.000 |
| 2024-04 | 185 | 1.738.595 | 172 | 30 | 25.000 |
| 2024-05 | 108 | 988.700 | 103 | 11 | 50.000 |
| 2024-06 | 113 | 1.447.530 | 106 | 44 | 100.000 |
| 2024-07 | 75 | 1.231.850 | 72 | 52 | 33.000 |
| 2024-08 | 70 | 794.285 | 60 | 28 | 33.000 |
| 2024-09 | 108 | 1.123.800 | 86 | 30 | 54.000 |
| 2024-10 | 138 | 1.366.230 | 109 | 32 | 40.000 |
| 2024-11 | 218 | 1.366.200 | 165 | 19 | 33.000 |
| 2024-12 | 225 | 1.833.720 | 169 | 33 | **165.000** |
| 2025-01 | 247 | 2.590.405 | 162 | 60 | 40.000 |
| 2025-02 | 199 | 1.748.850 | 130 | 42 | 50.000 |
| 2025-03 | 264 | 2.091.800 | 214 | 29 | 35.000 |
| 2025-04 | 371 | 3.306.885 | 305 | 62 | 40.000 |
| 2025-05 | 259 | 2.881.685 | 205 | 69 | 50.000 |
| 2025-06 | 199 | 1.824.400 | 155 | 34 | 50.000 |
| 2025-07 | 250 | 2.464.480 | 189 | 54 | 33.000 |
| 2025-08 | 158 | 1.870.415 | 132 | 62 | 50.000 |
| 2025-09 | 189 | 1.943.580 | 150 | 41 | 55.000 |
| 2025-10 | 128 | 1.119.315 | 88 | 22 | 33.000 |
| 2025-11 | 120 | 880.745 | 76 | 15 | 33.000 |
| 2025-12 | 126 | 1.146.440 | 92 | 28 | 33.000 |
| 2026-01 | 225 | 1.985.880 | 154 | 44 | 50.000 |
| 2026-02 | 173 | 2.401.550 | 136 | 72 | 33.000 |
| 2026-03 | 242 | 3.324.186 | 203 | 97 | 33.000 |
| 2026-04 | 145 | 1.933.090 | 109 | 57 | 33.000 |
| 2026-05 | 102 | 1.166.680 | 71 | 31 | 40.000 |
| 2026-06 (parcial) | 9 | 63.200 | 5 | 1 | 27.000 |

### 6.2 Distribución de puntos por período y EventTypeCode — GSFERNANDEZ

| Período | EventTypeCode | Eventos | Puntos | Promedio | Máximo |
|---|---|---|---|---|---|
| 2023-02 | CompensationalPoints | 26 | 263.700 | 10.142 | 40.000 |
| 2023-02 | InstitutionalPoints | 4 | 6.110 | 1.527 | 4.000 |
| 2023-02 | PrizePoints | 3 | 2.530 | 843 | 1.250 |
| 2023-03 | CompensationalPoints | 107 | 796.250 | 7.441 | 27.000 |
| 2023-03 | InstitutionalPoints | 1 | 11.000 | 11.000 | 11.000 |
| 2023-03 | PrizePoints | 9 | 8.100 | 900 | 3.000 |
| 2023-04 | CompensationalPoints | 78 | 701.450 | 8.992 | 33.000 |
| 2023-04 | HumanResourcesPoints | 4 | 39.000 | 9.750 | 11.000 |
| 2023-04 | InstitutionalPoints | 4 | 31.450 | 7.862 | 12.000 |
| 2023-04 | PrizePoints | 7 | 50.000 | 7.142 | 15.000 |
| 2023-05 | CompensationalPoints | 74 | 666.300 | 9.004 | 22.000 |
| 2023-05 | HumanResourcesPoints | 4 | 36.400 | 9.100 | 22.000 |
| 2023-05 | InstitutionalPoints | 1 | 7.920 | 7.920 | 7.920 |
| 2023-05 | PrizePoints | 8 | 10.000 | 1.250 | 2.600 |
| 2023-06 | CompensationalPoints | 72 | 543.250 | 7.545 | 20.000 |
| 2023-06 | HumanResourcesPoints | 2 | 2.150 | 1.075 | 1.150 |
| 2023-06 | PrizePoints | 10 | 33.290 | 3.329 | 20.000 |
| 2023-07 | CompensationalPoints | 54 | 377.900 | 6.998 | 20.000 |
| 2023-07 | InstitutionalPoints | 2 | 30.000 | 15.000 | 20.000 |
| 2023-07 | PrizePoints | 8 | 29.400 | 3.675 | 20.000 |
| 2023-08 | CompensationalPoints | 83 | 573.200 | 6.906 | 20.000 |
| 2023-08 | HumanResourcesPoints | 2 | 20.000 | 10.000 | 10.000 |
| 2023-08 | InstitutionalPoints | 5 | 127.050 | 25.410 | 63.000 |
| 2023-08 | PrizePoints | 3 | 1.900 | 633 | 1.000 |
| 2023-09 | CompensationalPoints | 99 | 970.290 | 9.800 | 30.000 |
| 2023-09 | HumanResourcesPoints | 2 | 31.000 | 15.500 | 25.000 |
| 2023-09 | InstitutionalPoints | 3 | 36.500 | 12.166 | 13.000 |
| 2023-09 | PrizePoints | 14 | 46.410 | 3.315 | 12.000 |
| 2023-10 | CompensationalPoints | 135 | 1.341.700 | 9.938 | 36.000 |
| 2023-10 | HumanResourcesPoints | 3 | 29.650 | 9.883 | 24.150 |
| 2023-10 | InstitutionalPoints | 2 | 60.000 | 30.000 | 50.000 |
| 2023-10 | PrizePoints | 22 | 55.700 | 2.531 | 30.000 |
| 2023-11 | CompensationalPoints | 128 | 1.105.850 | 8.639 | 33.000 |
| 2023-11 | HumanResourcesPoints | 2 | 12.000 | 6.000 | 6.000 |
| 2023-11 | InstitutionalPoints | 2 | 13.200 | 6.600 | 10.000 |
| 2023-11 | PrizePoints | 14 | 19.150 | 1.367 | 3.450 |
| 2023-12 | CompensationalPoints | 111 | 1.137.715 | 10.249 | 30.000 |
| 2023-12 | HumanResourcesPoints | 1 | 1.100 | 1.100 | 1.100 |
| 2023-12 | InstitutionalPoints | 2 | 70.000 | 35.000 | 50.000 |
| 2023-12 | PrizePoints | 11 | 125.500 | 11.409 | 20.000 |
| 2024-01 | CompensationalPoints | 154 | 1.019.880 | 6.622 | 22.000 |
| 2024-01 | HumanResourcesPoints | 3 | 35.000 | 11.666 | 15.000 |
| 2024-01 | InstitutionalPoints | 2 | 20.700 | 10.350 | 11.000 |
| 2024-01 | PrizePoints | 12 | 20.380 | 1.698 | 6.000 |
| 2024-02 | CompensationalPoints | 111 | 846.300 | 7.624 | 20.000 |
| 2024-02 | InstitutionalPoints | 5 | 168.380 | 33.676 | 76.000 |
| 2024-02 | PrizePoints | 15 | 13.600 | 906 | 3.000 |
| 2024-03 | CompensationalPoints | 126 | 1.036.050 | 8.222 | 20.000 |
| 2024-03 | InstitutionalPoints | 2 | 51.180 | 25.590 | 27.180 |
| 2024-03 | PrizePoints | 12 | 16.350 | 1.362 | 3.000 |
| 2024-04 | CompensationalPoints | 185 | 1.738.595 | 9.397 | 25.000 |
| 2024-04 | HumanResourcesPoints | 1 | 9.500 | 9.500 | 9.500 |
| 2024-04 | InstitutionalPoints | 1 | 6.710 | 6.710 | 6.710 |
| 2024-04 | PrizePoints | 2 | 1.550 | 775 | 1.050 |
| 2024-05 | CompensationalPoints | 108 | 988.700 | 9.154 | 50.000 |
| 2024-05 | HumanResourcesPoints | 1 | 5.000 | 5.000 | 5.000 |
| 2024-05 | InstitutionalPoints | 2 | 22.000 | 11.000 | 16.500 |
| 2024-05 | PrizePoints | 8 | 7.810 | 976 | 4.000 |
| 2024-06 | CompensationalPoints | 113 | 1.447.530 | 12.810 | 100.000 |
| 2024-06 | HumanResourcesPoints | 4 | 27.500 | 6.875 | 15.000 |
| 2024-06 | InstitutionalPoints | 4 | 16.500 | 4.125 | 5.000 |
| 2024-06 | PrizePoints | 16 | 49.950 | 3.121 | 7.000 |
| 2024-07 | CompensationalPoints | 75 | 1.231.850 | 16.424 | 33.000 |
| 2024-07 | PrizePoints | 20 | 158.980 | 7.949 | 25.000 |
| 2024-08 | CompensationalPoints | 70 | 794.285 | 11.346 | 33.000 |
| 2024-08 | InstitutionalPoints | 6 | 46.500 | 7.750 | 15.000 |
| 2024-08 | PrizePoints | 20 | 70.600 | 3.530 | 10.000 |
| 2024-09 | CompensationalPoints | 108 | 1.123.800 | 10.405 | 54.000 |
| 2024-09 | InstitutionalPoints | 6 | 34.000 | 5.666 | 12.000 |
| 2024-09 | PrizePoints | 45 | 141.070 | 3.134 | 15.000 |
| 2024-10 | CompensationalPoints | 138 | 1.366.230 | 9.900 | 40.000 |
| 2024-10 | HumanResourcesPoints | 1 | 500 | 500 | 500 |
| 2024-10 | PrizePoints | 25 | 65.970 | 2.638 | 10.000 |
| 2024-11 | CompensationalPoints | 218 | 1.366.200 | 6.266 | 33.000 |
| 2024-11 | HumanResourcesPoints | 2 | 8.400 | 4.200 | 6.500 |
| 2024-12 | CompensationalPoints | 225 | 1.833.720 | 8.149 | 165.000 |
| 2024-12 | HumanResourcesPoints | 2 | 16.500 | 8.250 | 15.000 |
| 2025-01 | CompensationalPoints | 247 | 2.590.405 | 10.487 | 40.000 |
| 2025-01 | HumanResourcesPoints | 4 | 51.500 | 12.875 | 33.000 |
| 2025-01 | InstitutionalPoints | 4 | 12.000 | 3.000 | 3.000 |
| 2025-01 | PrizePoints | 1 | 30.000 | 30.000 | 30.000 |
| 2025-02 | CompensationalPoints | 199 | 1.723.850 | 8.662 | 50.000 |
| 2025-03 | CompensationalPoints | 264 | 2.091.800 | 7.923 | 35.000 |
| 2025-03 | HumanResourcesPoints | 3 | 19.500 | 6.500 | 6.500 |
| 2025-03 | InstitutionalPoints | 3 | 15.000 | 5.000 | 5.000 |
| 2025-04 | CompensationalPoints | 371 | 3.306.885 | 8.913 | 40.000 |
| 2025-04 | HumanResourcesPoints | 2 | 11.000 | 5.500 | 6.000 |
| 2025-04 | InstitutionalPoints | 9 | 70.000 | 7.777 | 10.000 |
| 2025-05 | CompensationalPoints | 259 | 2.881.685 | 11.126 | 50.000 |
| 2025-06 | CompensationalPoints | 199 | 1.824.400 | 9.167 | 50.000 |
| 2025-06 | HumanResourcesPoints | 1 | 5.000 | 5.000 | 5.000 |
| 2025-06 | InstitutionalPoints | 5 | 70.000 | 14.000 | 30.000 |
| 2025-07 | CompensationalPoints | 250 | 2.464.480 | 9.857 | 33.000 |
| 2025-07 | HumanResourcesPoints | 3 | 50.000 | 16.666 | 30.000 |
| 2025-07 | InstitutionalPoints | 14 | 150.000 | 10.714 | 20.000 |
| 2025-08 | CompensationalPoints | 158 | 1.870.415 | 11.838 | 50.000 |
| 2025-08 | InstitutionalPoints | 10 | 100.000 | 10.000 | 10.000 |
| 2025-09 | CompensationalPoints | 189 | 1.943.580 | 10.283 | 55.000 |
| 2025-09 | InstitutionalPoints | 5 | 150.000 | 30.000 | 30.000 |
| 2025-10 | CompensationalPoints | 128 | 1.119.315 | 8.744 | 33.000 |
| 2025-11 | CompensationalPoints | 120 | 880.745 | 7.339 | 33.000 |
| 2025-11 | HumanResourcesPoints | 1 | 5.000 | 5.000 | 5.000 |
| 2025-11 | InstitutionalPoints | 5 | 150.000 | 30.000 | 30.000 |
| 2025-12 | CompensationalPoints | 126 | 1.146.440 | 9.098 | 33.000 |
| 2025-12 | HumanResourcesPoints | 1 | 10.000 | 10.000 | 10.000 |
| 2026-01 | CompensationalPoints | 225 | 1.985.880 | 8.826 | 50.000 |
| 2026-01 | InstitutionalPoints | 6 | 156.500 | 26.083 | 30.000 |
| 2026-02 | CompensationalPoints | 173 | 2.401.550 | 13.881 | 33.000 |
| 2026-02 | HumanResourcesPoints | 1 | 10.000 | 10.000 | 10.000 |
| 2026-03 | CompensationalPoints | 242 | 3.324.186 | 13.736 | 33.000 |
| 2026-03 | HumanResourcesPoints | 1 | 1.300 | 1.300 | 1.300 |
| 2026-03 | InstitutionalPoints | 5 | 150.000 | 30.000 | 30.000 |
| 2026-04 | CompensationalPoints | 145 | 1.933.090 | 13.331 | 33.000 |
| 2026-05 | CompensationalPoints | 102 | 1.166.680 | 11.438 | 40.000 |
| 2026-05 | InstitutionalPoints | 7 | 210.000 | 30.000 | 30.000 |
| 2026-06 | CompensationalPoints | 10 | 83.200 | 8.320 | 27.000 |

> **Nota:** 2026-06 muestra 10 eventos de `CompensationalPoints` vs los 9 analizados durante la investigación — un grant adicional fue emitido después de que se abrió el caso.

> **Patrón InstitutionalPoints:** A partir de 2025-07 aparece un batch mensual recurrente de 150.000 pts (5 receptores × 30.000 pts). Requiere verificar si tiene autorización explícita separada al canal compensacional.

> **PrizePoints:** Activo con volumen significativo en 2023–2024; desaparece virtualmente en 2025. Requiere verificar si el canal fue discontinuado formalmente o simplemente dejó de usarse.

---

### 6.3 Top 10 beneficiarios históricos (CompensationalPoints)

| Cliente | Documento | Asignaciones | Puntos Total | Mayor grant |
|---|---|---|---|---|
| Adrian Gustavo Di Lauro | 22884904 | 1 | 165.000 | 165.000 |
| Veronica Zabala | 26964763 | 1 | 100.000 | 100.000 |
| Mayra Gomez | 38648716 | 3 | 90.000 | 30.000 |
| Micaela Elizabeth Pastorini | 41912279 | 4 | 86.000 | 30.000 |
| Laura Soledad Lezcano | 28820625 | 7 | 85.500 | 25.000 |
| Fernando Segura | 39202067 | 2 | 85.000 | 55.000 |
| Paula Alfieri | 25906480 | 3 | 85.000 | 30.000 |
| Luis Fabián Zaffonte | 23593862 | 4 | 72.550 | 33.000 |
| Romina Paula Avendaño | 29168050 | 2 | 63.000 | 33.000 |
| Sol Ribetto | 33106389 | 2 | 60.000 | 40.000 |

**Total combinaciones cliente-mes con > 10.000 pts recibidos:** 1.346

---

## 7. Descripción del exploit

### Para gestores de proyecto (PM)

El sistema permite que un operador asigne manualmente cualquier cantidad de puntos a cualquier cliente sin ningún límite ni aprobación. No existe un techo configurado, no se requiere justificación y la operación se aprueba de forma automática. Esto significa que un operador con acceso al panel de compensaciones puede entregar, por ejemplo, 165.000 puntos a un cliente en un solo clic — equivalente a más de 16 años de compras diarias — sin que el sistema lo detecte ni lo bloquee. El exploit lleva activo desde febrero de 2023 y ha inyectado más de 58 millones de puntos fuera de los límites del reglamento de Club Grido.

### Para desarrolladores

**Tabla afectada:** `sml.ManualAssignPoints`

**Causa raíz:** La tabla no tiene restricciones de validación sobre la columna `Points` ni controles en la capa de aplicación que la consuma. El flujo de inserción es:

1. El operador crea una fila en `sml.ManualAssignPoints` con `RegisterByUser`, `AssignmentConcept`, `Points` y `AssignDate`.
2. `Status` se establece como `Approved` automáticamente — no hay estado intermedio de revisión.
3. `Catalog_Id` es nullable y no se valida — cualquier fila con `NULL` es aceptada.
4. El proceso que consume esta tabla inserta una fila correspondiente en `sml.CustomerPointsLog` con `EventTypeCode = 'CompensationalPoints'` y `ManualAssignPointsId` como FK.
5. `smlst.CustomerPointsLog` (tabla de saldo) se actualiza inmediatamente — los puntos quedan disponibles para canje en el mismo instante.

**Ausencias que habilitan el exploit:**
- No hay `CHECK CONSTRAINT` ni `TRIGGER` sobre `sml.ManualAssignPoints.Points`.
- No hay validación contra los límites diario (3.000), semanal (5.000) o mensual (10.000) del reglamento antes de aprobar.
- No hay rol de aprobador secundario (`ApproverId`, `ApprovedAt` o similar).
- No hay campo obligatorio de justificación (`Catalog_Id` es nullable).
- No hay alertas o umbrales de monitoreo sobre el volumen de esta tabla.

**Vector de explotación mínimo:** una sola fila insertada en `sml.ManualAssignPoints` con `Points = <cualquier valor>` y `RegisterByUser = <operador válido>`.

---

## 9. Hallazgos técnicos

- `sml.ManualAssignPoints` no tiene campo de techo de autorización ni validación de monto. Cualquier valor en `Points` es aceptado y aprobado automáticamente (`Status = 'Approved'`).
- `Catalog_Id = NULL` en todas las asignaciones de GSFERNANDEZ — no existe validación de motivo ni categoría obligatoria.
- Los IDs secuenciales (p. ej. 9411 y 9412 en un mismo día) confirman que las asignaciones se generan en sesiones continuas sin interrupciones de aprobación.
- El 77,9% de los grants de `CompensationalPoints` superan el límite diario de acumulación (3.000 pts), lo que indica que el canal opera sistemáticamente fuera del reglamento desde su activación.
- El volumen mensual creció de 263.700 pts (feb-2023) a 3.324.186 pts (mar-2026), un incremento de 12,6× sin ningún evento de control registrado.
- Los tipos `InstitutionalPoints` se asignan periódicamente a los mismos 5 receptores fijos — este subconjunto aparenta ser un proceso institucional separado y podría tener autorización explícita.
- Ninguna de las tres cuentas comprometidas en los días 1–2 de junio realizó canjes posteriores a las asignaciones. Los saldos son reversibles.

---

## 10. Acciones requeridas

### Inmediatas

| # | Acción | Responsable | Estado |
|---|---|---|---|
| 1 | Suspender operaciones de GSFERNANDEZ hasta completar auditoría | Operaciones | Pendiente |
| 2 | Confirmar si las compensaciones recientes cuentan con tickets de soporte respaldatorios | Operaciones | Pendiente |
| 3 | Definir reversión para Oscar Stuht (27.000 pts, ManualAssignId 9399) | Operaciones | Pendiente |
| 4 | Definir reversión para Gabriela Lubrano (5.300 pts, ManualAssignId 9411) | Operaciones | Pendiente |
| 5 | Definir reversión para Facundo Gabriele (10.000 pts, ManualAssignId 9412) | Operaciones | Pendiente |

### Técnicas (remediación del exploit)

| # | Acción | Responsable | Estado |
|---|---|---|---|
| 6 | Agregar campo `MaxPointsAllowed` o `RequiresApproval` en `sml.ManualAssignPoints` con techo configurable por concepto | Desarrollo | Pendiente |
| 7 | Hacer `Catalog_Id` obligatorio — rechazar inserciones con `NULL` | Desarrollo | Pendiente |
| 8 | Implementar flujo de aprobación de segundo nivel para grants > 3.000 pts | Desarrollo | Pendiente |
| 9 | Agregar validación de límites diario/semanal/mensual antes de aprobar cualquier `ManualAssignPoints` | Desarrollo | Pendiente |

### Auditoría histórica

| # | Acción | Responsable | Estado |
|---|---|---|---|
| 10 | Determinar qué porcentaje de los 58M pts de CompensationalPoints ya fueron canjeados (irreversibles) | DBA | Pendiente |
| 11 | Revisar los 1.346 episodios de cliente-mes con > 10.000 pts para identificar patrones de canje inmediato post-asignación | DBA | Pendiente |
| 12 | Auditar los 10 principales beneficiarios — verificar si los grants tienen justificación documentada | Operaciones | Pendiente |
| 13 | Determinar si `InstitutionalPoints` tiene autorización explícita separada | Operaciones | Pendiente |
| 14 | Evaluar si los grants de GSFERNANDEZ desde 2023-02-09 requieren notificación a compliance/legal | Legal | Pendiente |
