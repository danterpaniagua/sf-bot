**Tags:** SmartCloud, CloudPOS

## Resumen

En el POS de la franquicia WEISS (Punta del Este) las ventas que incluyen el ítem "Descuento Influencers 100%" junto con un producto de venta simple (por ejemplo "Franui") se rechazan como venta inválida al momento de cobrar. El ítem de descuento está cargado al 99.99% en lugar de 100% — **esto es deliberado, no un error de carga**: el PM confirmó una regla de negocio transversal a toda la plataforma que exige un monto mínimo facturable por Facturación Electrónica en cada tenant (Uruguay $0.01, Argentina $0.01, Perú $0.30), y WEISS es Uruguay. El problema real es que el mecanismo actual (un descuento de **porcentaje fijo**, 99.99%) deja un residuo **proporcional al subtotal** de cada venta ($0.14 y $0.17 en los casos observados) en vez del piso fijo de $0.01 que exige la regla para Uruguay — y ese residuo, cuando cae en una línea de producto simple, la validación de pago del sistema no lo tolera. El impacto es funcional (bloqueo de venta) y no compromete infraestructura ni disponibilidad de otros servicios.

## Tabla resumen

| Campo | Valor |
|---|---|
| ID alerta | N/A — reporte directo de franquicia |
| Sistema | SmartFran Cloud — POS / Catalog (tenant WEISS, `tenantId kt76igzny9ql`) |
| Severidad | Media — bloquea ventas puntuales con este descuento, sin afectar el resto de la operación |
| Detectado | 2026-08-02 |
| Resuelto | Pendiente — corrección de datos propuesta, no aplicada aún |
| Responsable | SRE (investigación) + responsable de precios/promociones de WEISS (aplicación del fix) |

## Causa raíz

El ítem de catálogo 430 ("Descuento Influencers 100%", grupo "Descuento", `FinancialModify = 1`) tiene cargado un `PublishedPrice`/`NewPrice` de **99.99** en sus 8 listas de precio, en lugar de **100.00**. Esto es **intencional, confirmado por el PM**: existe una regla de negocio de monto mínimo facturable por Facturación Electrónica (Uruguay $0.01, Argentina $0.01, Perú $0.30), y una venta no puede cerrar en $0.00 exacto. El POS usa el valor de `PublishedPrice` directamente como porcentaje de descuento, por lo que aplica un 99.99% en vez de un 100%, dejando un residuo equivalente al 0.01% del subtotal de la venta — esta parte del cálculo está confirmada de forma exacta contra los montos reales reportados (ver "Ejemplo con datos reales").

**El defecto real no es el valor de precio, sino el mecanismo.** Un descuento de porcentaje fijo (99.99%) deja un residuo que escala con el subtotal de la venta, no un piso fijo de $0.01 como exige la regla para Uruguay — por eso los residuos observados ($0.14 y $0.17) están muy por encima de $0.01. El mecanismo correcto debería dejar siempre el piso exacto del país, independientemente del tamaño de la venta.

Ese residuo llega intacto a la validación `payments >= total` del backend de Ventas cuando la línea afectada es un producto de venta simple (como "Franui"), provocando el rechazo genérico de venta inválida — esto también está confirmado. Lo que **todavía no está confirmado** es el mecanismo exacto por el cual una venta con el mismo descuento pero con una línea de tipo combo (como "Franui c/Combo" o el combo de hamburguesas) se acepta pese al mismo residuo teórico: la hipótesis de trabajo es que el propio recálculo interno del POS para líneas de combo hace que el monto que efectivamente valida el backend llegue a $0 (no solo que el residuo quede oculto visualmente), pero esto no se pudo verificar con los datos disponibles en las bases de Catalog/Business — requiere revisar el payload real de una venta de prueba en Application Insights, pendiente.

## Ejemplo con datos reales

Caso reportado por la franquicia: 2 hamburguesas + Franui, con el descuento "Descuento Influencers 100%" aplicado a toda la venta.

| Escenario | Línea de Franui | Total final cobrado | Resultado |
|---|---|---|---|
| 2 hamburguesas (combo) sola, con descuento | — | $0.14 | Venta aceptada |
| 2 hamburguesas + Franui, con descuento | Ítem 386 "Franui" (línea de producto simple) | $0.17 | **Venta rechazada** ("La venta es invalida") |
| 2 hamburguesas + Franui c/Combo, con descuento | Ítem 423 "Franui c/Combo" (línea tipo combo) | — | Venta aceptada |
| Solo Franui, con descuento (sin hamburguesas) | Ítem 386 "Franui" | — | **Venta rechazada** |
| Solo Franui, sin descuento | Ítem 386 "Franui" | — | Venta aceptada |

Con el ítem de descuento cargado al 99.99% en vez de 100.00%, esto deja sin cubrir exactamente un 0.01% del subtotal antes de descuento — no es una aproximación: para un subtotal de $1.400,00 el cálculo da un residuo de $0,14 exacto, y para $1.700,00 da $0,17 exacto, coincidiendo al centavo con los montos reales reportados (validado con una simulación numérica que replica la fórmula real del sistema). Se probó tanto pago en Efectivo como por Transferencia para el escenario que falla, con el mismo resultado en ambos casos, y se confirmó que el cajero no realiza ninguna cobranza en estas ventas (el descuento es del 100%, sin cobro esperado al cliente) — el residuo de cobro es real, no un problema de método de pago.

La diferencia entre "Franui" y "Franui c/Combo" no se debe a una diferencia de configuración de promoción entre ambos ítems (los dos son ítems de catálogo comunes, `FinancialModify = 0`, sin estructura de combo propia). La hipótesis de trabajo es que se debe a cómo el POS recalcula el precio unitario en líneas de tipo combo, pero al intentar verificar esta hipótesis con una simulación numérica el resultado no fue concluyente: con cobro $0 confirmado en ambos casos, el modelo simple no explica por qué la venta de combo se acepta pese a tener el mismo residuo teórico. Este punto sigue bajo investigación (ver Acciones propuestas).

## Hallazgos

| # | Hallazgo | Riesgo |
|---|---|---|
| H1 | Ítem 430 "Descuento Influencers 100%" cargado al 99.99% (no 100.00%) en las 8 listas de precio de WEISS — **confirmado deliberado** (regla de monto mínimo facturable), pero el mecanismo de porcentaje fijo deja un residuo proporcional al subtotal en vez del piso fijo de $0.01 que exige la regla para Uruguay | Alto |
| H5 | Regla de negocio confirmada por el PM (2026-08-03): monto mínimo facturable por Facturación Electrónica, transversal a toda la plataforma (SF Cloud, SmartLoyalty, Pedidos, Plataformas) — Uruguay $0.01, Argentina $0.01, Perú $0.30. No implementada consistentemente en el mecanismo de descuento actual | Alto |
| H2 | El residuo de cobro (0.01% del subtotal) provoca rechazo de venta cuando el descuento se aplica junto a un producto de venta simple, independientemente del método de pago | Alto |
| H3 | En ventas con líneas de tipo combo, el mismo descuento mal cargado no provoca rechazo — pero no está confirmado si esto significa que el sistema efectivamente cobra $0 igual (sin impacto real) o si representa una pérdida de cobro silenciosa del 0.01%. Pendiente de confirmar con datos de Application Insights | Medio |
| H4 | Hallazgo secundario, fuera del alcance de esta causa raíz: la promoción "Ruleta Articulo Bonificado" que incluye a franui como artículo bonificado tiene un gap de vigencia — la fila activada (id 183) venció el 2026-07-31 y su reemplazo (id 186, vigente hasta 2028) nunca fue activado | Bajo |

## Recursos afectados

| Recurso | Detalle |
|---|---|
| `SmartFran.Cloud.Catalog_WEISS` | Base SQL, elastic pool `t102-smartfran-cloud-weiss` — tabla `PriceDetails`, ítem `Id=430` |
| POS WEISS | `SmartFran-Cloud-Pos-PRO` (app compartida), tenant WEISS — ventas con el ítem "Descuento Influencers 100%" |
| `SmartFran.Cloud.Business_WEISS` | Hallazgo secundario únicamente — tabla `Promotions`, ids 183/186 |

## Comandos ejecutados

| # | Comando / Script | Propósito |
|---|---|---|
| C1 | Buscar promoción/combo "franui" en `Promotions` (Business_WEISS) | Descartar regla de negocio de promoción como causa |
| C2 | Confirmar base de datos conectada (`DB_NAME` + `INFORMATION_SCHEMA.TABLES`) | Corregir conexión tras error de tabla inexistente |
| C3 | Buscar ítem "Descuento Influencers" en `Items`/`Groups` (Catalog_WEISS) | Identificar el ítem de descuento y su tipo |
| C4 | Consultar precio real del ítem 430 en `PriceDetails` | Confirmar el valor de precio cargado (causa raíz) |
| C5 | Buscar ítem "franui" en `Items`/`Groups` (Catalog_WEISS) | Descartar que franui fuera en sí mismo una promoción/combo |
| C6 | Pruebas manuales en POS (métodos de pago, franui con/sin combo, franui con/sin descuento, "Franui" vs "Franui c/Combo") | Aislar la variable determinante de la falla |
| ⚠️ C7 | `UPDATE PriceDetails SET PublishedPrice=100.00, NewPrice=100.00 WHERE ItemId=430 AND PublishedPrice=99.99` | **Superado — NO ejecutar.** Dejaría la venta en $0.00 exacto, violando la regla de monto mínimo facturable confirmada por el PM (H5). Se mantiene en el script solo como referencia histórica. |

Detalle completo de cada comando y su salida en `20260802_promocion-invalida-weiss-franui_scripts.sh`.

## Acciones propuestas

1. ~~Confirmar con el responsable de precios/promociones si 99.99 fue error o deliberado~~ — **respondido por el PM**: deliberado, por la regla de monto mínimo facturable (H5).
2. **Decisión de producto pendiente** (Dev + responsable de Facturación Electrónica): definir el mecanismo correcto para garantizar el piso fijo por país ($0.01 UY/AR, $0.30 PE) en vez del actual descuento de porcentaje fijo. Dos alternativas a evaluar, no decididas acá: (a) rediseñar el descuento como monto fijo restante (deja siempre el piso exacto, cualquiera sea el subtotal), o (b) mantener el descuento por porcentaje pero que la validación `payments >= total` tolere específicamente un residuo igual al piso configurado del país.
3. **No ejecutar la corrección `UPDATE ... 100.00` (C7)** — superada, ver H1/H5.
4. Una vez definido el mecanismo (paso 2), verificar que una venta de "Franui" simple + "Descuento Influencers 100%" se procese correctamente en WEISS sin violar el piso de $0.01.
5. Revisar en Application Insights (Sales, `SmartFran-Cloud-Sales-PRO_new`) el payload real de una venta de combo aceptada con este descuento, para confirmar si el sistema efectivamente cobra el piso mínimo en esos casos o si hay una pérdida de cobro silenciosa (H3) que amerite revisión retroactiva.
6. Confirmar si esta misma discrepancia (mecanismo de porcentaje fijo vs. piso fijo por país) existe en otros tenants/países más allá de WEISS (Uruguay), dado que la regla es transversal a Argentina y Perú también.

## Hallazgos secundarios

La promoción "Ruleta Articulo Bonificado" (que incluye a franui como artículo bonificado) presenta un gap de activación: la fila id 183 quedó activada pero venció el 2026-07-31, y su reemplazo (id 186, vigente hasta 2028-03-31) nunca fue activado. Se recomienda notificar al responsable de promociones de WEISS para que revise y active la fila correspondiente si corresponde continuar con esa promoción. Esto no guarda relación con la causa raíz de este ticket.
