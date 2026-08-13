# Eventos — 20260802_promocion-invalida-weiss-franui

## 2026-08-02 — Apertura del caso

He recibido el reporte: en el POS de WEISS (Punta del Este), al vender 2 hamburguesas + franui con el descuento "influencer" aplicado, la venta se rechaza como inválida al momento de cobrar. Quitando franui (y dejando solo el combo de hamburguesas) la venta pasa. He creado el archivo de investigación para este evento.

## 2026-08-02 — Descarte de la hipótesis de cálculo de redondeo en el POS

He revisado el código fuente (`cloud/repo/SmartFran.Cloud/`, commit `0ed6784`) y confirmado que el mensaje "La venta es invalida" corresponde al código genérico `SaleIsInvalid` (12000), disparado cuando la regla `payments >= total` de `SaleCreateCmdValidator` falla. Inicialmente he sospechado un problema de redondeo en cascada en el cálculo del POS (`Sale.razor.cs`), agravado por combinar el combo con franui.

## 2026-08-02 — C6(a): prueba con pago por Transferencia

He confirmado con el usuario que la venta se pagó por Transferencia. Esto encajaba con la hipótesis de que el auto-ajuste del monto en el cliente POS solo corrige pagos en Efectivo.

## 2026-08-02 — C6(b): prueba con pago en Efectivo — hipótesis refutada

He solicitado repetir la misma venta pagando en Efectivo. El resultado fue el mismo rechazo, lo que descarta el método de pago como variable determinante.

## 2026-08-02 — C6(c): totales de la venta con descuento

He recibido los montos finales: 2 hamburguesas + franui con todos los descuentos aplicados da un total de $0.17 (falla); 2 hamburguesas solas da $0.14 (pasa). He identificado que ambos totales son cercanos a cero, lo cual soporta un descuento de porcentaje muy alto sobre el ítem "Descuento Influencers".

## 2026-08-02 — C6(d): franui solo, sin el combo, también falla

He confirmado que una venta con franui únicamente (sin las hamburguesas) y el mismo descuento también es rechazada. Esto descarta que el problema dependa de combinar dos líneas promocionales y traslada el foco a franui y/o al propio ítem de descuento.

## 2026-08-02 — C1: estructura de "franui" como promoción en Business_WEISS

He ejecutado la consulta sobre la tabla `Promotions` de `SmartFran.Cloud.Business_WEISS` buscando "franui". He encontrado 4 filas: dos promociones "Promo Cheeseburguer+Picker+Helado" (id 86/87) desactivadas desde febrero 2026, y dos filas "Ruleta Articulo Bonificado" (id 183, activada pero con `ValidToDate` vencido el 2026-07-31; id 186, vigente hasta 2028 pero nunca activada). He registrado esto último como hallazgo secundario, sin relación aparente con la falla principal.

## 2026-08-02 — C3: identificación del ítem "Descuento Influencers" en Catalog_WEISS

He localizado el ítem 430 "Descuento Influencers 100%" en `SmartFran.Cloud.Catalog_WEISS`, perteneciente al grupo 243 "Descuento" con `FinancialModify = 1` (Descuento). Confirmo que es un descuento del 100%, no simplemente "alto".

## 2026-08-02 — C4: precio real del ítem 430 — causa raíz confirmada

He consultado `PriceDetails` para el ítem 430 y encontrado que las 8 listas de precio tienen `PublishedPrice` y `NewPrice` en **99.99**, no en 100.00. He verificado que el cálculo del POS usa este valor directamente como porcentaje de descuento, por lo que el descuento real aplicado es del 99.99%, dejando un residuo del 0.01% del total sin cubrir en cada venta que usa este ítem. He verificado que este residuo coincide con los montos reportados ($0.14 y $0.17) para subtotales estimados de $1.400 y $1.700 respectivamente.

## 2026-08-02 — C5: descarte de franui como promoción/combo propio

He buscado "franui" en `Items`/`Groups` de Catalog_WEISS y confirmado que tanto el ítem 386 ("Franui") como el 423 ("Franui c/Combo") son ítems de catálogo normales, con `FinancialModify = 0`. Descarto la hipótesis de que franui tuviera una estructura de promoción/combo propia con múltiples líneas de cuerpo.

## 2026-08-02 — C6(e): diferencia entre "Franui c/Combo" y "Franui" simple

He recibido confirmación de que la venta con "Franui c/Combo" pasa, mientras que con "Franui" simple falla. He explicado que esto es consistente con la causa raíz: las líneas de tipo combo recalculan y redondean su precio unitario (Total/Cantidad), lo que absorbe el residuo del 0.01% sin que nadie lo note; las líneas de producto simple no tienen ese recálculo y el residuo llega intacto a la validación de pago, provocando el rechazo. Esto implica que WEISS probablemente viene perdiendo ese 0.01% también en las ventas de combo que usan este descuento, sin que hasta ahora generara un error visible.

## 2026-08-02 — C6(f): franui sin descuento funciona correctamente

He recibido confirmación de que franui solo, sin el descuento "influencer" aplicado, se vende sin problemas. Esto termina de aislar la causa al ítem de descuento: franui en sí mismo no tiene ningún problema; la falla depende exclusivamente de que la venta pase por el ítem 430 con su precio mal cargado.

## 2026-08-02 — Cierre de la investigación, propuesta de fix

He convergido en la causa raíz: error de carga de datos en el catálogo, no un defecto de código. He redactado la consulta de corrección (`UPDATE PriceDetails ... SET PublishedPrice = 100.00, NewPrice = 100.00 WHERE ItemId = 430`) como remediación propuesta, pendiente de confirmación con el responsable de precios/promociones de WEISS antes de ejecutarla. He generado el ticket de cierre (`_ops.md`) y el correo para PMs con este estado.

## 2026-08-02 — Simulación numérica de la fórmula real del descuento

He escrito un script (`_scripts.py`) que replica exactamente la fórmula del código fuente (`CalcAmountWithOutIva`) con los montos reales. He confirmado que el residuo calculado coincide de forma exacta, no aproximada, con los montos reportados: $1.400,00 × 0,0001 = $0,14 y $1.700,00 × 0,0001 = $0,17.

## 2026-08-02 — Brecha detectada en la simulación: no explica por qué el combo pasa

Al modelar también la validación de aceptación/rechazo (`payments >= total`) asumiendo cobro $0, la simulación predijo rechazo para ambos casos — pero el caso de combo solo había sido aceptado en la realidad. He identificado que esto se debe a que estoy usando la fórmula del total mostrado en pantalla, que es distinta de la fórmula que realmente valida el backend (`SaleCreateCmdValidator`, basada en `UnitPrice × Quantity`, no en `Total`). No pude cerrar esta brecha solo con los datos de Catalog/Business — queda pendiente revisar el payload real en Application Insights.

## 2026-08-03 — Confirmación: el cajero no cobra nada en estas ventas

He recibido confirmación de que el descuento es genuinamente del 100% y que el cajero no realiza ninguna cobranza. Esto descarta la posibilidad de que el caso de combo haya pasado porque el cajero cobró el residuo mostrado en pantalla — el cobro $0 es real, no una suposición. Esto profundiza la brecha detectada en la simulación en vez de resolverla: sigue sin explicarse por qué una venta con un residuo teórico de $0,14 y cobro $0 fue aceptada por el sistema. He actualizado el archivo de investigación y el ticket para reflejar este punto como pendiente de confirmar con datos reales, en vez de dar por válida una explicación no verificada.

## 2026-08-03 — Intento de obtener el documento real de la venta vía Graylog + CosmosDB

He intentado cerrar la brecha pendiente extrayendo los valores de partición (FranchiseeCode/FranchiseCode/PosCode) desde líneas de log en Graylog para consultar directamente el documento de venta real en CosmosDB. He confirmado el contenedor (`Sales`), la base (`Sales-WEISS`) y la partition key (`[FranchiseeCode, FranchiseCode, PosCode]`) correctos por código y por Azure CLI. Sin embargo, tres intentos de consulta —incluso usando valores de una venta con respuesta 200 confirmada— devolvieron cero documentos. He identificado que `SMARTFRAN-CLOUD-SALES-PRO` es un App Service compartido entre todos los tenants y sus logs no tienen ningún campo que identifique el tenant, por lo que los valores extraídos probablemente correspondían a otra franquicia, no a WEISS. He dejado este punto sin resolver y he documentado el hallazgo en la skill `/cloud-invalid-sale` para no repetir el mismo camino en el futuro sin la salvedad correspondiente.

## 2026-08-03 — Intento alternativo vía SQL de Business_WEISS — también sin resultado

He intentado ubicar los códigos opacos de franquicia/POS directamente en `Business_WEISS`. He identificado el franchise correcto (Id=5, "Weiss Punta del Este", FranchiseeId=3) entre varios candidatos (había franchises de test y otro local, "Weiss Ensenada", con el mismo nombre parcial). He consultado `RelatedCode` para ese franchise/franchisee y solo encontré códigos fiscales de facturación electrónica de Uruguay (FE-PVTA, FEUY-IDCOMERCIO, etc.), no los códigos opacos de ruteo cloud. He consultado `RelatedCode` para los 5 `SalePoint` de esa franquicia (Mostrador 1/2/3, KDS, Peya, Pick-Up) y no encontré ninguna fila. Concluyo que estos códigos no están almacenados en el esquema SQL de Business_WEISS accesible desde estas tablas, y dejo este punto como pendiente permanente (no bloqueante), a resolver únicamente si se consigue acceso en vivo al POS o a alguien que ya conozca estos códigos.

## 2026-08-03 — Respuesta del PM: regla de negocio de monto mínimo de facturación electrónica — el fix propuesto queda invalidado

He recibido respuesta del PM: existe una regla de negocio transversal a toda la plataforma (SF Cloud, SmartLoyalty, Pedidos, Plataformas) que exige un monto mínimo facturable por Facturación Electrónica en cada tenant — Argentina $0.01, Perú $0.30, Uruguay $0.01. Como WEISS es Uruguay (confirmado antes por los códigos fiscales FEUY-* en Business_WEISS), esto responde directamente la pregunta abierta que había dejado en la investigación: el precio 99.99 (en vez de 100.00) del ítem "Descuento Influencers 100%" es deliberado, no un error de carga — existe justamente para no dejar la venta en $0.00, que violaría esta regla.

He identificado que esto invalida el fix que tenía propuesto (cambiar 99.99 a 100.00 en `PriceDetails`) — aplicarlo generaría exactamente el resultado ($0.00) que la regla prohíbe. También he identificado que el mecanismo actual (99.99% de descuento, un porcentaje fijo) tampoco implementa correctamente la regla: deja un residuo proporcional al subtotal ($0.14 y $0.17 en los casos observados), muy por encima del piso de $0.01 que corresponde a Uruguay, en vez de dejar siempre ese piso fijo. He dejado esto documentado como una decisión de producto pendiente (mecanismo de descuento a monto fijo vs. tolerancia en el validador), no resuelta unilateralmente desde esta investigación. He marcado el fix original como superado y pendiente de revisión en `_ops.md` y en el email al PM antes de cualquier envío o cierre.
