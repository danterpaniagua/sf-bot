# Red de Fraude "Batman" — Transferencias Fraudulentas

**Fecha de cierre:** 2026-06-12
**Período investigado:** Noviembre 2024 – Junio 2026 (18 meses)
**Base de datos:** `SmartFran.Solution.SmartLoyalty`
**Estado:** Cerrado — acciones pendientes

---

## 1. Resumen Ejecutivo

Se confirmó una red organizada de fraude por transferencia de puntos en Club Grido SmartLoyalty. El operador controla múltiples cuentas con nombres ficticios (personajes de DC Comics y Los Simpsons), registradas con DNIs secuenciales o inválidos, que actúan como hubs de acumulación y redistribución. La red opera desde noviembre de 2024 con escalada de montos individuales a partir de febrero de 2026, cuando el operador confirmó la ausencia de controles en tiempo real.

Se identificaron 5 cuentas hub bajo control del mismo operador y 9 cuentas receptoras confirmadas. Total distribuido: ~438.000 puntos. Total canjeado (irrecuperable): ~144.300 puntos. Saldo recuperable en hubs: ~294.000 puntos. La cuenta receptora principal (Huanca, 38973061) acumula 74.000 puntos sin ningún canje — recuperación inmediata posible.

Una detección previa ocurrió en diciembre 2024 (reversión por GSLCEBALLOS, -62.475 pts) sin suspensión de cuenta. La red continuó operando 18 meses adicionales.

---

## 2. Métricas Globales

| Métrica | Valor |
|---|---|
| Ventana activa | Nov 2024 – Jun 2026 (18 meses) |
| Cuentas hub (mismo operador) | 5 |
| Cuentas receptoras confirmadas | 9 |
| Feeders confirmados | 2+ (Ciraco, Diaz) |
| Total distribuido por red | ~438.000 pts |
| Total canjeado — irrecuperable | ~144.300 pts |
| Saldo recuperable — hubs | ~224.077 pts |
| Saldo recuperable — Huanca | 74.000 pts (sin canje, 100%) |
| Transferencias individuales confirmadas | 31+ |
| Violaciones límite diario (>8.000 pts único envío) | 15+ |
| Detección previa sin suspensión | Sí — 2024-12-20 (GSLCEBALLOS) |

---

## 3. Red de Actores

### 3.1 Cuentas Hub — Mismo Operador

| Cuenta | DNI | Email | Rol | Saldo actual | Distribuido | Señales de fraude |
|---|---|---|---|---|---|---|
| El Batman | 43541208 | locosdeperros3090@gmail.com | Hub primario | 41.385 | ~256.000 | Nombre ficticio; patrón email; activo 18 meses; 0 actividad POS |
| Bat Man | 43541200 | locosdeperros3030@gmail.com | Alias/Hub | 37.149 | 20.000 | DNI secuencial -8 de El Batman; mismo patrón email |
| Elbarto Malo | 43541209 | josecastroo12343@gmail.com | Hub paralelo | 109.354 | 129.999 | DNI +1 de El Batman; nombre ficticio (Bart Simpson); email no coincide |
| Eustacio C. Castro | 92623449 | ortegacastro1234@gmail.com | Relay/Hub | ~32.499 | 32.240 | DNI imposible (92M+); email combina apellidos de Castro Ortega |
| Juana De Torres | 13883289 | locosdeperros3080@gmail.com | Alias | 3.690 | — | Tercer email familia locosdeperros30XX; pendiente investigación completa |

### 3.2 Cuentas Receptoras / Cashout

| Cuenta | DNI | Pts recibidos | Pts canjeados | Saldo estimado | Estado |
|---|---|---|---|---|---|
| Esteban J. Huanca | 38973061 | 74.000 | **0** | **74.000** | RECUPERABLE 100% — sin ningún canje |
| Lucas L. Castro Ortega | 45253012 | 128.000+ | — | — | Relay confirmado → Huanca |
| Angel Pereyra | 48016024 | ~94.000 | 45.800 | ~48.500 | Parcialmente canjeado |
| Valentina A. Choque | 47813765 | ~102.740 | 61.300 | ~42.140 | Mayor volumen de canje en la red |
| Agustina Guzman | 46403467 | 45.000 | 14.500 | ~2.000 | Cliente real reclutada; relay activa (Jun 10) |
| Agustina Sandoval Sobarzo | 45978514 | 30.000 | 22.700 | ~2.850 | Receptor de Guzman; cashout inmediato (101 seg) |
| Lucas Riquelme | 44238411 | 22.000 | — | — | Pendiente investigación |
| Carlos Barrionuevo | 44679076 | 24.000 | — | — | Pendiente investigación |
| Cuenta desactivada 79C680B6 | — | 37.000 | — | Congelados | Desactivada — 5 transferencias recibidas |

### 3.3 Feeders (Cuentas Alimentadoras)

| Cuenta | DNI | Email | Destino | Pts | Señal |
|---|---|---|---|---|---|
| Diego Ciraco | 23223694 | diegociraco@gmail.com | El Batman | 19.000 | Transfer único; misma sesión que Diaz |
| Christian Diaz | 36449166 | nahuelazo21@gmail.com | El Batman | 24.000 | Email "nahuel" ≠ nombre; transfer único |

---

## 4. Patrón de Fraude

### 4.1 Acumular-y-vaciar (Receive-then-flush)

Los hubs reciben desde múltiples feeders en sesiones breves, luego redistribuyen en minutos:

| Fecha | Hub | Carga | → | Vaciado |
|---|---|---|---|---|
| Feb 7, 2026 | El Batman | 66.935 pts en 22 min (10 feeders) | → | 30.000 a Castro Ortega 5 min después |
| Mar 7, 2026 | Elbarto Malo | 30.000 pts al crear cuenta | → | -30.000 18 min después de creación |
| May 27, 2026 | Elbarto Malo | 32.998 pts en 10 min | → | -29.999 a Eustacio Castro 1 min después |
| Jun 7, 2026 | El Batman + Castro Ortega | 54.000 pts coordinados | → | A Huanca en 6 min |

### 4.2 Escalada de Montos

| Período | Patrón de envío | Monto máximo individual |
|---|---|---|
| Nov 2024 – Ene 2026 | Siempre 8.000 pts exactos (límite diario) | 8.000 pts |
| Feb 2026 → presente | 10.000, 20.000, 22.000, 30.000 pts | **30.000 pts (3,75× límite)** |

El operador confirmó la ausencia de enforcement e incrementó los montos en febrero 2026.

**Causa raíz confirmada por análisis de código:** el commit `667bc6877` (29 ago 2025, FedericoLovera — `federicol@smartfran.com`) eliminó la bifurcación `if (isCustomerContributor)` en `CustomerService.cs:550–590` (`GetAvailablePointsTransfer`). A partir de ese momento, el sistema aplica el límite del colaborador (30.000 pts/día) a todos los clientes, independientemente del tipo de cuenta. Los límites del cliente regular (`CustomerPoints*LimitTransfer` = 8.000/10.000/13.000 pts) quedaron inalcanzables. La escalada de la red a partir de febrero 2026 (cinco meses después del commit) corresponde al período en que el operador verificó que el enforcement había desaparecido y ajustó los montos al nuevo límite efectivo. Ver `ANALISIS_SEGURIDAD_FRAUDE_2026-06-03.md` — Hallazgo 1.

### 4.3 DNIs Secuenciales — Registro Masivo Coordinado

| DNI | Cuenta | Email |
|---|---|---|
| 43541200 | Bat Man | locosdeperros3030@gmail.com |
| 43541207 | Homer Spo | elmiguelortega009@gmail.com |
| 43541208 | El Batman | locosdeperros3090@gmail.com |
| 43541209 | Elbarto Malo | josecastroo12343@gmail.com |

Cuatro cuentas en rango 43541200–43541209 registradas en la misma operación. Nombres referencian personajes de ficción (Batman DC, Homer Simpson, Bart Simpson).

---

## 5. Evidencia de Coordinación — Mismo Operador

| Fecha | Evento | Cuenta A | Cuenta B |
|---|---|---|---|
| May 14, 2026 23:08–23:10 | Dos hubs envían al mismo destino con 2 min de diferencia | El Batman → Guzman -8.000 | Elbarto Malo → Guzman -30.000 |
| Apr 19, 2026 16:12–16:14 | Envíos paralelos simultáneos | Elbarto Malo → Pereyra -30.000 | El Batman → Castro Ortega -30.000 |
| Jun 7, 2026 14:48–14:53 | Pump coordinado a Huanca (5 cuentas, 6 min) | El Batman -8.000 y -22.000 | Castro Ortega -8.000 × 3 |
| Email | Tres cuentas mismo patrón email | locosdeperros3030 | locosdeperros3080 / locosdeperros3090 |
| DNIs | Cuatro cuentas en rango de 9 dígitos | 43541200, 43541207 | 43541208, 43541209 |
| Destinos compartidos | Castro Ortega, Pereyra, Guzman, Choque — receptores de múltiples hubs | El Batman | Elbarto Malo / Eustacio Castro |

---

## 6. Detección Previa Sin Suspensión

| Campo | Valor |
|---|---|
| Fecha | 2024-12-20 13:18 ARG |
| Operador | GSLCEBALLOS |
| Acción | ManualAssignPoints −62.475 pts (CompensationalPoints negativo) |
| Nota | "Puntos Compensación de Calidad" |
| Cuenta afectada | Eustacio Cirilo Castro (DNI 92623449) |
| Resultado | Saldo anulado a cero |
| Falla | Cuenta no suspendida — tres semanas después recibe nuevas transferencias (ene 2025) |

La red continuó operando 18 meses adicionales tras la detección. El mecanismo de reversión existe pero no se acompañó de suspensión de cuenta ni alerta sistémica.

---

## 7. Saldos Recuperables — Prioridad de Reversión

| Cuenta | DNI | Saldo | Tipo | Prioridad |
|---|---|---|---|---|
| Esteban J. Huanca | 38973061 | **74.000** | 100% fraudulento — 0 canjes | **INMEDIATA** |
| Elbarto Malo | 43541209 | **109.354** | Hub confirmado — 0 actividad legítima | **INMEDIATA** |
| El Batman | 43541208 | **41.385** | Hub primario — 0 actividad legítima | **INMEDIATA** |
| Bat Man | 43541200 | **37.149** | Alias confirmado | **INMEDIATA** |
| Eustacio C. Castro | 92623449 | **~32.499** | Hub/relay — DNI imposible | **INMEDIATA** |
| Angel Pereyra | 48016024 | **~48.500** | Reversión parcial — descontar earn legítimo | ALTA |
| Valentina A. Choque | 47813765 | **~42.140** | Reversión parcial — descontar earn legítimo | ALTA |
| Juana De Torres | 13883289 | 3.690 | Alias confirmado por email | MEDIA |

**Total prioridad inmediata:** ~294.387 pts
**Total con reversiones parciales:** ~384.027 pts estimados

---

## 8. Acciones Propuestas

### Inmediatas
- [ ] Suspender cuentas hub: DNI 43541208, 43541200, 43541209, 92623449
- [ ] Revertir saldo Huanca (38973061): −74.000 pts — sin cashout, 100% recuperable
- [ ] Revertir saldos hubs: Batman, Bat Man, Elbarto Malo, Eustacio Castro (~220.000 pts)
- [ ] Notificar a Agustina Guzman (46403467): cliente real posiblemente coaccionada
- [ ] Bloquear cluster DNI 43541185–43541220 pendiente auditoría

### Técnicas (prevención)

**Correcciones de código — bugs confirmados (ver `ANALISIS_SEGURIDAD_FRAUDE_2026-06-03.md`)**
- [ ] **[CRÍTICO] Hallazgo 1** — Restaurar bifurcación `if (isCustomerContributor)` en `CustomerService.cs:550–590`. Corrige la aplicación del límite colaborador a clientes regulares. Commit a revertir: `667bc6877` (FedericoLovera, 29 ago 2025). Asignar a FedericoLovera o responsable de dominio.
- [ ] **[CRÍTICO] Hallazgo 2** — Retirar endpoint `POST /Customer/PointsTransfer` (`CustomerController.cs:183–215`). Endpoint marcado `[Obsolete]` pero enrutado y sin validación de límites — permite vaciado directo de saldo. Confirmar si algún cliente activo aún lo llama antes de eliminar. Commit de reactivación: `b0f284100` (raulcSF, 14 jun 2024, GITSML-2465).
- [ ] **[ALTA] Hallazgo 3** — Mover contador de intentos fallidos de sesión ASP.NET a cache de aplicación o base de datos, keyed por IP y/o nombre de usuario. Bloqueo debe ocurrir en servidor antes de invocar autenticación. Origen: `AccountController.cs:2847–2857` (SabrinaB, dic 2017, SML-3157 — nunca tuvo enforcement por IP).
- [ ] **[MEDIA] Hallazgo 4** — Restringir `GET /Account/GetSecurityCaptcha` a usuarios autenticados. Agregar log de auditoría al cambio del parámetro `SecurityCaptcha` en `Sml.Param`. Commit que introdujo el problema: `3a01a2a19` (raulcSF, 23 sep 2025, GITSML-4202).

**Controles preventivos adicionales**
- [ ] Alertar saldo acumulado >50.000 pts sin historial POS proporcional
- [ ] Bloquear registro con DNIs secuenciales o fuera de rango nacional (AR: 1M–50M)
- [ ] Bloquear dominios desechables confirmados: yopmail.com, hilostar.com, datehype.com
- [ ] Establecer protocolo obligatorio de suspensión al ejecutar reversiones administrativas

### Auditoría
- [ ] Investigar cluster completo 43541185–43541220 (Homer Spo 43541207 — 22.001 pts)
- [ ] Identificar feeders de Valentina Choque: Feb 10 +22.500 pts, Oct 26 tres × 8K
- [ ] Identificar feeders de Angel Pereyra: Dec 7 dos × 8K, Mar 30 tres × 8K en 27 seg
- [ ] Trazar destino Sandoval May 23 send (−5.000 pts) — capa adicional
- [ ] Contactar GSLCEBALLOS para contexto detección dic. 2024
- [ ] Investigar Lucas Riquelme (44238411) y Carlos Barrionuevo (44679076)
- [ ] **[Pendiente — Detección]** Análisis de logs Graylog (fuente `ServiceName:"SF-CLUBS"`, stream IIS W3C de `SFCG-CLUB-01`) para detección de timing attack vía credential stuffing sin cookie de sesión. El contador `MaxInvalidLoginAttempts = 3` (`AccountController.cs:2847`) es por sesión ASP.NET: sin cookie entrante el servidor crea sesión nueva con contador cero — curl/Postman explotan esto por defecto. Vector identificado previamente por Operations. Campo IP real: `X-Forwarded-For` (no `c-ip`, que es siempre el proxy `192.168.60.6`). `cs(Cookie)` no está en el log configurado — la detección es frecuencia + timing. Dos señales: (A) Rate: `ServiceName:"SF-CLUBS" AND cs-uri-stem:"/Account/LoginUser" AND cs-method:"POST"` → COUNT por `X-Forwarded-For` en ventana 5 min, alerta >10. (B) Timing: mismo query + STDDEV(`time-taken`) por `X-Forwarded-For` — distribución bimodal (~50 ms vs ~200 ms) indica enumeración de usuarios (rápido = username inexistente, lento = hash bcrypt ejecutado). Objetivo: re-ejecutar query sobre ventana 2026-06-03 y confirmar si el ataque del Patrón A usó este bypass; producir alerta Graylog para operación continua.

### Franquicias
- [ ] Notificar comercialmente a Angelelli (Sucursal 3385, San Pedro, Jujuy) — víctima del abuso, sin complicidad detectada
- [ ] Notificar comercialmente a Funes (Sucursal 5182, Chos Malal, Neuquén) — víctima del abuso, sin complicidad detectada
- [ ] Alertar a franquiciados sobre identidades conocidas de la red para bloquear futuros canjes

---

## 9. Investigación de Franquicias

Se identificaron dos sucursales de canje donde los actores de la red cobraron puntos fraudulentos. La investigación de staff de franquicia (7 cuentas consultadas) descartó complicidad interna: ningún empleado coincide con actores de la red en DNI, email o nombre.

### 9.1 Clusters Geográficos de Canje

| Sucursal | Cod. | Ciudad | Provincia | Franquiciado | Actores de canje | Pts canjeados aprox. |
|---|---|---|---|---|---|---|
| SAN PEDRO JUJUY | 3385 | San Pedro | Jujuy | Angelelli, Franco | Choque, Pereyra, Barrionuevo | ~129.400 |
| CHOS MALAL | 5182 | Chos Malal | Neuquén | Funes, Cristian | Guzman, Sandoval, Jenifer Riquelme | ~47.100 |

**Total canjeado en franquicias identificadas:** ~176.500 pts

### 9.2 Investigación de Staff — Sin Señales de Insider

Se consultaron las cuentas de `sml.FranchiseStaff` para ambas franquicias. Resultado: 7 cuentas (staff + gerentes), ninguna con superposición con la red Batman.

| Conclusión | Detalle |
|---|---|
| Complicidad interna | No detectada — staff de ambas franquicias sin vinculación con la red |
| Patrón identificado | Mulas físicas que viajan a las sucursales para canjear; franquiciados son víctimas |
| Acción recomendada | Notificación comercial a ambos franquiciados — no denuncia contra ellos |

### 9.3 Distribución de Canje por Actor y Franquicia

| Actor | DNI | Franquicia / Sucursal | Pts canjeados aprox. |
|---|---|---|---|
| Valentina A. Choque | 47813765 | Angelelli / SAN PEDRO JUJUY (3385) | ~61.300 |
| Angel Pereyra | 48016024 | Angelelli / SAN PEDRO JUJUY (3385) | ~45.800 |
| Carlos Barrionuevo | 44679076 | Angelelli / SAN PEDRO JUJUY (3385) | ~22.300 |
| Agustina Sandoval Sobarzo | 45978514 | Funes / CHOS MALAL (5182) | ~22.700 |
| Agustina Guzman | 46403467 | Funes / CHOS MALAL (5182) | ~14.500 |
| Jenifer Riquelme | 40960742 | Funes / CHOS MALAL (5182) | ~9.900 |

---

## 10. Archivos de Evidencia

| Archivo | Contenido | Filas |
|---|---|---|
| `01_queries.sql` | Todas las consultas SQL de la investigación | — |
| `02_actores_red.csv` | Todos los actores: DNI, email, rol, pts, saldo, flags | 20 |
| `03_transferencias_hubs.csv` | Transfers salientes de Batman, Bat Man, Elbarto, Eustacio | 31 |
| `04_inbound_batman.csv` | Transfers entrantes a El Batman (59 filas) | 59 |
| `05_historial_elbarto_malo.csv` | Historial completo Elbarto Malo | 36 |
| `06_historial_eustacio_castro.csv` | Historial completo Eustacio Castro | 26 |
| `07_historial_angel_pereyra.csv` | Historial completo Angel Pereyra | 31 |
| `08_historial_valentina_choque.csv` | Historial completo Valentina Choque | 38 |
| `09_historial_agustina_guzman.csv` | Historial completo Agustina Guzman | 37 |
| `10_historial_sandoval_sobarzo.csv` | Historial completo Agustina Sandoval Sobarzo | 21 |
| `11_franquicias_canje.csv` | Transacciones de canje por sucursal y actor — Angelelli y Funes | 11 |
| `12_historial_lucas_riquelme.csv` | Historial completo Lucas Riquelme (pendiente escritura) | 10 |
| `13_historial_jenifer_riquelme.csv` | Historial completo Jenifer Riquelme (pendiente escritura) | 6 |
| `ANALISIS_SEGURIDAD_FRAUDE_2026-06-03.md` | Análisis de código ClubSiteG2: 4 hallazgos — bugs de límites de transferencia, endpoint obsoleto, credential stuffing, CAPTCHA | — |

---

## 11. Mejoras de Observabilidad y Seguridad

### 11.1 Registro de Presencia de Cookie en NXLog — SFCG-CLUB-01

**Estado:** Implementado — 2026-06-12

El campo `cs(Cookie)` del log IIS W3C era descartado por NXLog antes de la transmisión a Graylog — decisión correcta para evitar almacenar tokens de autenticación activos. El campo contiene credenciales de sesión que no deben persistirse en ningún log store:

| Cookie presente en el request | Motivo para no loguear el valor |
|---|---|
| `ASP.NET_SessionId` | Token de sesión activo — replay permite secuestro de sesión |
| `.ASPXAUTH` | FormsAuthentication ticket — autenticación sin re-login |
| `.AspNet.ApplicationCookie` | OWIN Identity cookie — mismo vector que `.ASPXAUTH` |
| `__RequestVerificationToken` | Token anti-CSRF — explotable dentro de su ventana de validez |

**Mejora implementada en `nxlog.d/iis.conf` (NXLog CE 3.2.2329):**

Se agregó registro del campo como booleano de presencia (`cs_cookie_present`), habilitando detección de requests sin cookie sin almacenar datos sensibles. Campo renombrado de `cs(Cookie)` a `csCookie` en la definición `xm_csv` — NXLog CE 3.2 no soporta `${"fieldname"}` para campos con paréntesis en bloques Exec:

```nxlog
if $csCookie != "-"
{
    $cs_cookie_present = "true";
}
else
{
    $cs_cookie_present = "false";
}
```

`cs_cookie_present: "true"/"false"` llega a Graylog. El valor crudo del campo nunca se transmite ni almacena. Verificado con evento de prueba post-deploy.

**Pendiente:**
- [ ] Migrar transporte de `om_udp` a `om_ssl` — logs transmitidos sin cifrado ni garantía de entrega

---

### 11.2 Query de Detección — Timing Attack / Credential Stuffing sin Cookie

**Estado:** Definido — pendiente configuración de alerta en Graylog

El contador `MaxInvalidLoginAttempts = 3` (`AccountController.cs:2847`) es por sesión ASP.NET. Clientes sin cookie (curl, Postman, scripts automatizados) obtienen sesión nueva por request: el contador siempre parte de cero. Vector identificado previamente por Operations.

**Query base:**
```
ServiceName:"SF-CLUBS" AND cs-uri-stem:"/Account/LoginUser" AND cs-method:"POST" AND sc-status:"200"
```

Filtro `sc-status:"200"` requerido: los `400` (token CSRF expirado, body malformado) son rechazados antes de la lógica de autenticación con `time-taken` ~37ms, contaminando el análisis de timing. Solo los `200` reflejan ejecución real del hash bcrypt.

| Señal | Campo Graylog | Método de detección | Umbral sugerido |
|---|---|---|---|
| Volumen por IP real | `X-Forwarded-For` | COUNT / ventana 5 min | > 10 |
| Ausencia de cookie (ataque directo) | `cs_cookie_present` | valor `"false"` | cualquier ocurrencia |
| Enumeración de usuarios por timing | `time-taken` | STDDEV por `X-Forwarded-For` | STDDEV > 80ms con COUNT > 5 |

> `c-ip` es siempre la IP del proxy (`192.168.60.5` / `192.168.60.6` — pool). Toda correlación por IP real usa `X-Forwarded-For`.

---

### 11.3 GeoIP — Corrección de Campo Objetivo

**Estado:** Pendiente

El enriquecimiento GeoIP en Graylog está aplicado sobre `gl2_remote_ip` / `source` (`52.234.224.34` — IP del servidor Azure que reenvía logs). El campo del cliente real es `X-Forwarded-For`. Sin la corrección, el dashboard muestra geografía del servidor, no del atacante.

Regla de pipeline a crear en `System → Pipelines`:

```
rule "geoip_client_ip"
when
  has_field("X-Forwarded-For")
then
  let geo = lookup(lookup_table: "geoip", value: to_string($message."X-Forwarded-For"));
  set_field("client_geo_country", geo["country_code"]);
  set_field("client_geo_city",    geo["city"]);
  set_field("client_geo_lat",     geo["latitude"]);
  set_field("client_geo_lon",     geo["longitude"]);
end
```

---

## 12. Contabilidad de Puntos

Datos confirmados por Q_VALIDATE_BALANCES_ALL y Q_VALIDATE_SPENT_TRANSFERRED (2026-06-13).

| Actor | DNI | Rol | Email_Flag | Pts Recibidos (fraude) | Gastados | Transferidos (salientes) | Activos | Retenidos |
|---|---|---|---|---|---|---|---|---|
| Lucas Castro Ortega | 45253012 | relay_cashout | NO_EN_MAILING | **437.380** (71 transf.) | **230.000** (53 canjes) | 152.000 (19 envíos) | **55.730** | — |
| El Batman | 43541208 | hub_primario | NO_EN_MAILING | 297.385 (59 transf.) | 0 | 256.000 (22 envíos) | **41.385** | — |
| Elbarto Malo | 43541209 | hub_paralelo | NO_EN_MAILING | 234.353 (30 transf.) | 0 | 129.999 (5 envíos) | **109.354** | — |
| Eustacio Cirilo Castro | 92623449 | relay_hub | NO_EN_MAILING | 127.214 (22 transf.) | 0 | 32.240 (3 envíos) + 62.475 revertido | **32.499** | — |
| Valentina Ayelen Choque | 47813765 | cashout_mula | NO_EN_MAILING | 102.740 (10 transf.) | **61.300** (26 canjes) | 0 | **42.140** | — |
| Angel Pereyra | 48016024 | cashout_mula | NO_EN_MAILING | 94.000 (9 transf.) | **45.800** (18 canjes) | 0 | **48.500** | — |
| Esteban Joel Huanca | 38973061 | cashout | NO_EN_MAILING | 74.000 (6 transf.) | **0** | 0 | **74.000** | — |
| Lucas Riquelme | 44238411 | pass_through | NO_EN_MAILING | 68.000 (4 transf.) | **0** | 29.000 (6 envíos) | **39.000** | — |
| Juana De Torres | 13883289 | cashout (takeover?) | **OK** | 0 (POS orgánico) | **72.300** (13 canjes) | 0 | **3.690** | — |
| Bat Man | 43541200 | hub_alias | NO_EN_MAILING | 57.149 (13 transf.) | 0 | 20.000 (1 envío) | **37.149** | — |
| Agustina Guzman | 46403467 | relay_mula | NO_EN_MAILING | 45.000 (3 transf.) | **17.500** (6 canjes) | 16.000 (2 envíos) | **17.050** | — |
| Carlos Barrionuevo | 44679076 | cashout_mula | NO_EN_MAILING | 38.000 (5 transf.) | **27.300** (8 canjes) | 8.000 (1 envío → dest. pendiente) | **7.700** | — |
| Agustina Sandoval Sobarzo | 45978514 | cashout_mula | NO_EN_MAILING | 30.000 (6 transf.) | **22.700** (8 canjes) | 5.000 (1 envío → dest. pendiente) | **2.850** | — |
| Homer Spo | 43541207 | hub_feeder | NO_EN_MAILING | 60.001 (12 transf.) | 0 | 38.000 (2 envíos: 30K→Riquelme + 8K→dest. pendiente) | **22.001** | — |
| Karina Taduyo | 41218806 | cashout_mula | NO_EN_MAILING | 8.000 (1 transf. de Barrionuevo, abr 2025) | pendiente | pendiente | pendiente | — |
| Jenifer Riquelme | 40960742 | cashout_mula | NO_EN_MAILING | 11.000 (2 transf.) | **9.900** (3 canjes) | 0 | **1.300** | — |
| Juana De Torres (ver arriba) | — | — | — | — | — | — | — | — |
| 79C680B6 (desactivada) | — | relay | — | 37.000 | 0 | — | — | **(pendiente smlst)** |

**Nota — Juana De Torres (13883289):** Email_Flag = OK (presente en CustomerMailing) — único actor con flag OK. Cero puntos recibidos vía transferencia. Todos sus puntos son de acumulación POS propia. Diagnóstico probable: **cuenta tomada** — el operador accedió a una cuenta legítima y realizó 72.300 pts de canje sobre el saldo propio del titular. El saldo activo de 3.690 pts es del titular real. Requiere investigación de acceso y contacto al titular.

**Pendiente crítico:** 79C680B6 desactivada — confirmar held status en smlst: `SELECT Points FROM smlst.CustomerPointsLog WHERE CustomerId = '79C680B6-5EAC-C58D-D81E-08DD68DA7039'`.

**Resumen por estado (confirmado):**

| Estado | Puntos | Acción |
|---|---|---|
| Gastados — irrecuperables confirmados | **~486.800 pts** | Sin acción posible |
| Activos — recuperables confirmados | **~533.073 pts** | Suspender + revertir |
| Retenidos — 79C680B6 desactivada | pendiente smlst | Reversión administrativa por CustomerId |
| **Prioridad inmediata** (Huanca + hubs puros + Lucas Riquelme) | **~322.388 pts** | Acción sin demora |

> Prioridad inmediata: Huanca 74.000 + Elbarto 109.354 + El Batman 41.385 + Bat Man 37.149 + Eustacio 32.499 + Lucas Riquelme 39.000 (cero canjes) = **333.387 pts**
