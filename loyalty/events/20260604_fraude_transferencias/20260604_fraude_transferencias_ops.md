# Cierre de Investigación — Fraude de Transferencias
**Fecha:** 2026-06-04
**Ventana analizada:** 01:00–09:00 UTC-3
**Tipo de incidente:** Fraude de transferencias — dos vectores simultáneos
**Vector 1:** Red de tres cuentas coordinadas — esquema circular con staging previo
**Vector 2:** Desvío de beneficio de empleado — cadencia automatizada
**Investigador:** DBA / SRE
**Estado:** Pendiente acción operativa — saldos críticos intactos  
**JIRA Epic:** [GITIN-1275](https://smartit-ar.atlassian.net/browse/GITIN-1275) — epic raíz de fraude de puntos Smart Loyalty

---

## 1. Métricas del evento

| Métrica | Valor |
|---|---|
| Ventana analizada | 2026-06-04 01:00–09:00 UTC-3 |
| Transferencias totales en ventana | 22 |
| Puntos totales transferidos | 123.345 |
| Emisores únicos | 10 |
| Receptores únicos | 10 |
| Canal | APP (100%) |
| Vectores de fraude | 2 |
| Transferencias fraudulentas (V1 + V2) | 12 |
| Puntos fraudulentos en ventana | 75.500 |
| Saldo crítico intacto — Simon Brizuela DNI 46845173 | **9.565 pts** |
| Saldo crítico intacto — Simon Brizuela DNI 46845174 | **3.300 pts** |
| Saldo crítico intacto — Santiago Cabral DNI 48786856 | **20.155 pts** |
| Transferencias sin indicios de fraude | 10 |

---

## 2. Desglose por EventTypeCode — ventana completa

| EventTypeCode | Eventos | Puntos |
|---|---|---|
| PointsByTransferSent | 22 | -123.345 |
| PointsByTransferReceived | 22 | +123.345 |

---

## 3. Detalle de participantes — ventana 01:00–09:00 UTC-3

| Cliente | Documento | Rol | Transacciones | Puntos | Flag |
|---|---|---|---|---|---|
| Simon Brizuela | 46845174 | Emisor | 1 | -8.000 | V1 — feeder conocido |
| Simon Brizuela | 46845173 | Emisor / Receptor | 5 / 5 | -27.425 / +35.915 | V1 — hub conocido, límite superado |
| Dimon Briz | 123456 | Emisor / Receptor | 4 / 5 | -27.915 / +27.415 | V1 — relay conocido, cuenta falsa |
| María Celeste Mamanis | 35384064 | Emisor | 3 | -20.155 | V2 — límite superado, automatización |
| Santiago Cabral | 48786856 | Receptor | 3 | +20.155 | V2 — receptor concentración, saldo pendiente |
| Julia Roquelina Cuccaro | 4826910 | Emisor | 1 | -8.000 | Empleada Grido — receptor externo conocido |
| Carlos Daniel Sancho | 24545466 | Receptor | 1 | +8.000 | Receptor recurrente conocido (también 2026-06-03) |
| Sergio Emanuel Cordero | 35674095 | Emisor | 2 | -16.000 | Colaborador confirmado — dentro de límite 30k |
| Maria Velez | 37315106 | Receptor | 1 | +8.000 | Sin indicios |
| Lucia Fariaz | 11744821 | Receptor | 1 | +8.000 | Sin indicios |
| Claudia Alderete | 44659878 | Emisor | 1 | -1.000 | Sin indicios |
| Gabriela Alderete Leal | 45279111 | Receptor | 1 | +1.000 | Sin indicios |
| Marta Susana Bravo | 22246498 | Emisor | 1 | -1.400 | Sin indicios |
| Mariquena Veloz | 38093019 | Receptor | 1 | +1.400 | Sin indicios |
| Celeste Sanchez | 46516234 | Emisor | 1 | -4.000 | Sin indicios |
| Lucas Barrios | 46144746 | Receptor | 1 | +4.000 | Sin indicios |
| CECILIA ROMINA AVILA | 32487731 | Emisor | 1 | -2.290 | Sin indicios |
| Ramón Alberto Santo Blanco | 29093848 | Receptor | 1 | +2.290 | Sin indicios |
| Mia Aylén Guzmán | 50616717 | Emisor | 1 | -3.070 | Sin indicios |
| Giovanni Rafael | 4384472 | Receptor | 1 | +3.070 | Sin indicios |
| Javier Barria | 43691258 | Emisor | 1 | -4.090 | Sin indicios |
| Agustina Perez | 45384178 | Receptor | 1 | +4.090 | Sin indicios |

---

## 4. Vector 1 — Red de tres cuentas coordinadas

### 4.1 Esquema

```
[Staging previo — 2026-05-25 16:10 UTC-3 vía WEB]
Dimon Briz (DNI 123456) ─────────────────────► Simon Brizuela 46845174   +10.000 pts
                                                 [almacenado 10 días]

[Ventana investigada — 2026-06-04 vía APP]
Simon Brizuela 46845174 ─────────────────────► Simon Brizuela 46845173   +8.000 pts
                                                 [hub cargado]
Simon Brizuela 46845173 ◄───────────────────► Dimon Briz 123456          esquema circular
                              9 transferencias / 47 minutos
```

### 4.2 Secuencia circular

| Hora UTC-3 | Emisor | Receptor | Puntos | Observación |
|---|---|---|---|---|
| 02:05:20 | Simon 46845174 | Simon 46845173 | 8.000 | Carga del hub desde feeder |
| 02:08:07 | Simon 46845173 | Dimon 123456 | 9.075 | Doble envío en el mismo segundo |
| 02:08:07 | Simon 46845173 | Dimon 123456 | 9.075 | Doble envío — posible submit automático |
| 02:12:32 | Dimon 123456 | Simon 46845173 | 18.150 | Devolución exacta del doble envío |
| 02:23:16 | Simon 46845173 | Dimon 123456 | 9.075 | Segundo ciclo |
| 02:29:19 | Dimon 123456 | Simon 46845173 | 8.000 | — |
| 02:31:06 | Dimon 123456 | Simon 46845173 | 100 | Sonda |
| 02:36:38 | Simon 46845173 | Dimon 123456 | 100 | Sonda |
| 02:37:06 | Simon 46845173 | Dimon 123456 | 100 | Sonda |
| 02:52:33 | Dimon 123456 | Simon 46845173 | 1.665 | Cierre de ciclo |

**Total circulado:** 55.340 pts. **Saldo final hub (46845173):** 9.565 pts intactos.

### 4.3 Perfil de las cuentas

| Cuenta | DNI | Creado | Email | En Mailing | Saldo cierre |
|---|---|---|---|---|---|
| Simon Brizuela (hub) | 46845173 | 2025-12-22 WEB | simonnnn123@yopmail.com | No | 9.565 pts |
| Simon Brizuela (feeder) | 46845174 | 2026-01-17 WEB | simon12366@yopmail.com | No | 3.300 pts |
| Dimon Briz (relay) | 123456 | 2026-05-16 WEB | keyavi4022@hilostar.com | No | 0 pts |

> Las tres cuentas usan dominios de email desechables y están ausentes de `SmlSt.CustomerMailing`. DNIs 46845173/46845174 son consecutivos con el mismo nombre — misma persona, cuentas duplicadas. DNI 123456 es inválido en AR/PY/UY (6 dígitos, secuencial). "Dimon Briz" es anagrama evidente de "Simon Brizuela".

> **Nota sobre Dimon Briz:** cuenta activa desde 2026-05-16 con actividad POS intensa en franquicia (mayoría de transacciones con 0 pts) — posible asociación a terminal POS comprometido. Requiere investigación de PDV vinculado.

> **Coordinación con investigación 2026-06-03:** Lucas Riquelme (pass-through del vector credential stuffing del día anterior) fue creado el 2026-05-15, un día antes que Dimon Briz (2026-05-16). Homer Spo fue creado el 2026-05-26, al día siguiente del staging Dimon Briz → feeder. Misma red de infraestructura.

### 4.4 Violaciones de límite — Vector 1

| Cuenta | Puntos enviados (ventana) | Límite diario cliente | Exceso |
|---|---|---|---|
| Simon Brizuela 46845173 | 27.425 | 8.000 | +19.425 (3,4×) |
| Dimon Briz 123456 | 27.915 | 8.000 | +19.915 (3,5×) |
| Simon Brizuela 46845174 | 8.000 | 8.000 | En límite exacto |

---

## 5. Vector 2 — Desvío de beneficio de empleado

### 5.1 Esquema

```
María Celeste Mamanis (DNI 35384064)
  Cliente confirmada — sin historial HumanResourcesPoints
  3 transferencias en 77 segundos → Santiago Cabral (DNI 48786856)
  20.155 pts — 2,5× el límite diario cliente (8.000 pts)
```

### 5.2 Secuencia

| Hora UTC-3 | Puntos | Intervalo | Observación |
|---|---|---|---|
| 07:30:19 | 8.000 | — | — |
| 07:30:36 | 8.000 | 17 seg | Mismo monto, mismo segundo — automatización |
| 07:31:11 | 4.155 | 35 seg | — |

### 5.3 Julia Roquelina Cuccaro — patrón de reincidencia

| Fecha | Receptor | DNI Receptor | Puntos | Evento |
|---|---|---|---|---|
| 2026-06-03 07:25 UTC-3 | Carlos Daniel Sancho | 24545466 | 8.000 | TransfId 286300 |
| 2026-06-04 08:03 UTC-3 | Carlos Daniel Sancho | 24545466 | 8.000 | — |

Misma empleada (Colaboradora Temporal) → mismo receptor externo en días consecutivos. Sancho fue creado el 2026-06-02 (2 días antes).

---

## 6. Saldos críticos — reversión posible

| Cuenta | Documento | Saldo actual | Origen | Reversión posible |
|---|---|---|---|---|
| Simon Brizuela 46845173 | 46845173 | **9.565 pts** | Esquema circular | Sí |
| Simon Brizuela 46845174 | 46845174 | **3.300 pts** | Staging Dimon Briz (25-may) | Sí |
| Santiago Cabral | 48786856 | **20.155 pts** | 20.155 pts de Mamanis (saldo previo: 100 pts) | Sí |

---

## 7. Acciones propuestas

### Inmediatas

| # | Acción | Responsable | Estado |
|---|---|---|---|
| 1 | Suspender cuenta Simon Brizuela DNI 46845173 — bloquear 9.565 pts | Operaciones | Pendiente |
| 2 | Suspender cuenta Simon Brizuela DNI 46845174 — bloquear 3.300 pts | Operaciones | Pendiente |
| 3 | Suspender cuenta Dimon Briz DNI 123456 | Operaciones | Pendiente |
| 4 | Suspender cuenta María Celeste Mamanis DNI 35384064 | Operaciones | Pendiente |
| 5 | Suspender cuenta Santiago Cabral DNI 48786856 — bloquear 20.155 pts intactos | Operaciones | Pendiente |

### Investigación adicional

| # | Acción | Responsable | Estado |
|---|---|---|---|
| 6 | PDV confirmado — ver Vector 3. Escalar a red de franquiciados involucrados | Comercial / Legal | Pendiente |
| 7 | Escalar a RRHH: Julia Roquelina Cuccaro transfirió beneficio a Carlos Daniel Sancho en días consecutivos | RRHH | Pendiente |
| 8 | Investigar Carlos Daniel Sancho DNI 24545466 (creado 2026-06-02, receptor recurrente) | Operaciones | Pendiente |
| 9 | Cruzar red con investigación 2026-06-03 (Lucas Riquelme / Homer Spo) — misma infraestructura | DBA | Pendiente |

### Técnicas

| # | Acción | Responsable | Estado |
|---|---|---|---|
| 10 | Implementar validación de límites de transferencia en tiempo real (diario 8k / semanal 10k / mensual 13k) | Desarrollo | Pendiente |
| 11 | Bloquear registro con dominios de email desechables conocidos (yopmail.com, hilostar.com) | Desarrollo | Pendiente |
| 12 | Alertar transferencias circulares: A→B seguido de B→A en < 30 minutos | Seguridad | Pendiente |
| 13 | Alertar > 2 transferencias al mismo receptor en < 5 minutos | Desarrollo | Pendiente |
| 14 | Auditar configuración POS en franquicias Cura, Zurro, Jawahar, Liberali, Mercado — detectar CustomerId hardcodeado | Seguridad / Desarrollo | Pendiente |
| 15 | Bloquear posibilidad de registrar un mismo CustomerId como cliente en > N ventas/día en un mismo PDV | Desarrollo | Pendiente |

---

## 8. Vector 3 — Fraude POS en red de franquicias

### 8.1 Esquema

La cuenta Dimon Briz (CustomerId `E6CC99E8-...`, DNI 123456) fue configurada como cliente en terminales POS de múltiples franquicias a lo largo de Argentina. Cada transacción de cliente real procesada en esos terminales acreditó puntos a Dimon Briz en lugar del cliente legítimo. Los puntos acumulados fueron transferidos al hub (Simon Brizuela 46845173) y canjeados en sucursales LICEO.

### 8.2 Red de franquicias involucradas

| Franquiciado | Sucursales | Ventas Dimon Briz | Período | Rol |
|---|---|---|---|---|
| Cura, Juan Cruz | ORAN, ORAN II, ORAN III, ORAN IV | 253 | 2026-05-18 – 2026-06-03 | Acumulación (dominante) |
| Zurro, Horacio | MARCOS PAZ | 187 | 2026-05-17 – 2026-06-03 | Acumulación |
| Jawahar, Angel | SANTIAGO DEL ESTERO II | 77 | 2026-05-21 – 2026-06-01 | Acumulación |
| Liberali, Ezequiel | FLORESTA IV | 49 | 2026-05-16 – 2026-06-03 | Acumulación + primer PDV activo |
| Mercado, Adrian | TERMINAL I | 4 | 2026-05-16 – 2026-05-24 | Acumulación + canjes 46845174 |
| Aznarez, Juan | LICEO | 13 SaleIds canje | 2025-12-24 – 2026-05-29 | Canje (dominante) |
| Lazaro, Clide Mariel | LICEO 2DA | 2 SaleIds canje | 2026-01-06 – 2026-05-19 | Canje |

**Total ventas con CustomerId Dimon Briz:** 730+ en 21 sucursales, 18 días (2026-05-16 – 2026-06-03).

### 8.3 Señal de imposibilidad geográfica — 2026-05-23

| Hora UTC-3 | Sucursal | Provincia |
|---|---|---|
| 11:05 | FLORESTA IV | Buenos Aires (CABA) |
| 11:37 | PARQUE SAN MARTIN | Mendoza |
| 11:48 | SAN NICOLAS VI | Buenos Aires pcia. |
| 12:23 | SANTIAGO DEL ESTERO II | Santiago del Estero |

Cuatro provincias en 78 minutos — físicamente imposible. La cuenta estaba siendo procesada simultáneamente en múltiples terminales de distintas provincias. Confirma configuración deliberada de la credencial en múltiples POS.

### 8.4 Insider primario identificado — Franquicia Cura

`luiscura29@yahoo.com.ar` registrado como email de 5 cuentas de staff activas en la franquicia Cura:

| Nombre | Rol |
|---|---|
| luis ignacio cura | FranchiseManager |
| Cesar Ernesto Massa | FranchiseAttendant |
| paulina roxana dias | FranchiseCollaborator |
| patricia lampe | FranchiseCollaborator |
| beatrriz segovia | FranchiseCollaborator |

Un único operador controla múltiples identidades de staff. Es el principal sospechoso de haber configurado Dimon Briz como cliente por defecto en los 4 terminales ORAN.

### 8.5 Doble acreditación — SaleId 251525013

| Campo | Valor |
|---|---|
| SaleId | 251525013 |
| Sucursal | LUIS GUILLÓN II |
| Cliente registrado en sml.Sale | Federico Vidal (DNI 32994102) |
| Puntos acreditados a | Dimon Briz (E6CC99E8-...) |

Una venta de un cliente real fue también acreditada a Dimon Briz. Confirma manipulación activa, no solo configuración pasiva del terminal.

### 8.6 Cuantificación de puntos desviados (V3-8)

| Sucursal | Franquicia | Ventas | Puntos desviados |
|---|---|---|---|
| FLORESTA IV | Liberali, Ezequiel | 48 | 3.200 |
| MARCOS PAZ | Zurro, Horacio | 187 | 1.535 |
| ORAN IV | Cura, Juan Cruz | 201 | 1.250 |
| TERMINAL I | Mercado, Adrian | 4 | 1.000 |
| SAN NICOLAS VI | Pistoleso, Melisa | 12 | 800 |
| PARQUE SAN MARTIN | Plantamura, Jonathan | 1 | 500 |
| LASTENIA GRIDO | Hernando, Mauricio | 2 | 500 |
| SANTA LUCIA II | Cano, Martin | 6 | 450 |
| SANTIAGO DEL ESTERO II | Jawahar, Angel | 77 | 395 |
| ORAN | Cura, Juan Cruz | 23 | 370 |
| ORAN II | Cura, Juan Cruz | 23 | 0 |
| ORAN III | Cura, Juan Cruz | 6 | 0 |
| Resto (9 sucursales) | Varios | 140 | 0 |
| **Total** | | **730+** | **10.000 pts** |

> El total de **10.000 pts exactos** coincide con el transfer ejecutado el 2026-05-25 (Dimon Briz → Simon Brizuela 46845174). El operador acumuló hasta el monto objetivo y transfirió el saldo completo. Operación planificada, no oportunista.
>
> ORAN II y ORAN III (Cura, Juan Cruz): 29 ventas con 0 pts — artículos sin puntos. El volumen de transacciones en esas sucursales no generó puntos acreditables.
>
> Franquiciados con actividad menor (< 800 pts, posiblemente víctimas de POS comprometido, no actores activos): Pistoleso Melisa, Plantamura Jonathan, Hernando Mauricio, Cano Martin, Echandia Marina, Chavez Sergio, Lira Hernan, Pereyra Diego, Bottero Eugenia.

### 8.7 Acciones propuestas — Vector 3

| # | Acción | Responsable | Estado |
|---|---|---|---|
| V3-1 | Suspender acceso de `luiscura29@yahoo.com.ar` a todos los sistemas Grido | Seguridad / IT | Pendiente |
| V3-2 | Auditar todos los terminales POS de la franquicia Cura (ORAN ×4) — verificar CustomerId por defecto configurado | Seguridad / Desarrollo | Pendiente |
| V3-3 | Auditar terminales de Zurro (MARCOS PAZ), Jawahar (SANTIAGO DEL ESTERO II), Liberali (FLORESTA IV), Mercado (TERMINAL I) | Seguridad | Pendiente |
| V3-4 | Notificar a Comercial para inicio de proceso contractual contra franquiciados involucrados | Comercial / Legal | Pendiente |
| V3-5 | Identificar y notificar a los clientes reales cuyos puntos fueron desviados — 730+ transacciones, priorizar FLORESTA IV (3.200 pts) y MARCOS PAZ (1.535 pts) | Customer Service | Pendiente |
| V3-6 | Restituir puntos a clientes afectados — cuantificación requiere cruzar todas las ventas con CustomerId Dimon Briz contra el cliente que debería haberlos recibido | Operaciones | Pendiente |
| V3-7 | ~~Anomalía doble-acreditación SaleId 251525013~~ — Federico Vidal recibió 330 pts normalmente. Dimon Briz no aparece en CustomerPointsLog para esta venta. Falsa alarma — SaleId pertenece exclusivamente a Vidal. | DBA | Cerrado — sin hallazgo |
| V3-8 | Total puntos desviados confirmado: **10.000 pts** en 730+ ventas a 21 sucursales. Detalle por franquicia disponible en V3-8 de este documento. | DBA | Completado |
