# Actor Notes

Extended context for known fraud actors. Keyed by DNI.

---

**DNI 46845173 — Simon Brizuela (hub)**
Hub en esquema circular con Dimon Briz (DNI 123456) y feeder DNI 46845174. DNIs 46845173/46845174 consecutivos, mismo nombre — misma persona, cuentas duplicadas. Email: `simonnnn123@yopmail.com` — dominio desechable. Ausente de CustomerMailing. Saldo al cierre: 9.565 pts intactos.

**DNI 46845174 — Simon Brizuela (feeder)**
DNI consecutivo a 46845173, mismo nombre — duplicado deliberado. Email: `simon12366@yopmail.com` — desechable. Recibió 10.000 pts de Dimon Briz el 2026-05-25 vía WEB (staging). Inyectó 8.000 pts al hub el 2026-06-04 vía APP. Cambio WEB→APP entre sesiones = ofuscación. Saldo al cierre: 3.300 pts.

**DNI 123456 — Dimon Briz (relay)**
Cuenta falsa. "Dimon" = anagrama de "Simon" (Brizuela). DNI inválido (6 dígitos, secuencial). Email: `keyavi4022@hilostar.com` — desechable. Ausente de CustomerMailing. CustomerId configurado como cliente por defecto en POS de múltiples franquicias: 730+ ventas en 21 sucursales de 7 franquiciados entre 2026-05-16 y 2026-06-03. Actividad simultánea en múltiples provincias el mismo día (imposibilidad física confirmada). Franquiciado dominante: Cura, Juan Cruz (ORAN ×4, 253 ventas) — insider sospechoso: `luiscura29@yahoo.com.ar` (luis ignacio cura, 5 roles de staff bajo el mismo email). Infracción previa: -10.000 pts el 2026-05-25 → DNI 46845174. Sondas 490 pts el 2026-05-30. Saldo al cierre: 0 pts.

**DNI 43541207 — Homer Spo (hub_primario)**
Hub credential stuffing 2026-06-03. Recibió 60.001 pts de 12 cuentas comprometidas en 3 sesiones (2026-05-25, 2026-05-27, 2026-06-02). Cero actividad orgánica. Descargó 30.000 pts a Lucas Riquelme 01:52 UTC-3. Violación de límite: 30.000 pts vs. límite cliente 8.000. CustomerId pendiente.

**DNI 46374837 — Nahir Niz (beneficiario_crónico)**
Receptora crónica de transferencias de empleados Grido. ~132.000 pts recibidos en 14 meses desde marzo 2025. Cuenta creada 2022-12-25 — legítima en origen. Beneficiaria confirmada de Carlos Andrés Roldan (Colaborador Permanente). 4 transfers en 93 seg el 2026-06-03 — cadencia automatizada. Saldo al cierre 2026-06-03: 40.005 pts intactos.

**DNI 44238411 — Lucas Riquelme (pass_through)**
Pass-through del vector credential stuffing 2026-06-03. Creado 2026-05-15 APP — un día antes de Dimon Briz (2026-05-16 WEB): creación en lote coordinada. Recibió 30.000 pts de Homer Spo. Historial previo: +38.000 pts en 30 seg el 2026-05-16, redistribuyó 18.000 pts entre 2026-05-20 y 2026-05-25. Saldo al cierre 2026-06-03: 50.000 pts intactos.

**DNI 43541207 — Homer Spo (hub_primario)**
Hub credential stuffing 2026-06-03. Creado 2026-05-26 WEB — al día siguiente de la primera transferencia Dimon Briz → feeder (2026-05-25). Recibió 60.001 pts de 12 cuentas comprometidas en 3 sesiones (2026-05-25, 2026-05-27, 2026-06-02). Cero actividad orgánica. Descargó 30.000 pts a Lucas Riquelme 01:52 UTC-3. Violación de límite: 30.000 pts vs. límite cliente 8.000.

**DNI 24545466 — Carlos Daniel Sancho (receptor_recurrente)**
Creado 2026-06-02 APP — 2 días antes de la investigación del 2026-06-04. Receptor en dos investigaciones consecutivas. Recibió de Julia Roquelina Cuccaro (Colaboradora Temporal) el 2026-06-03 (TransfId 286300, 8.000 pts) y el 2026-06-04 (08:03 UTC-3, 8.000 pts). Misma empleada → mismo receptor externo en días consecutivos. Patrón de desvío sistemático de beneficio de empleado.
