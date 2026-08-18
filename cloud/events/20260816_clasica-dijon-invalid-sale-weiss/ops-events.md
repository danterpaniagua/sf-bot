# Eventos — 20260816_clasica-dijon-invalid-sale-weiss

## 2026-08-16 23:39 — Apertura de investigación

He recibido el reporte de CaC: en Weiss Punta del Este, la promo para compartir de Dijon muestra 3 opciones de hamburguesa en lugar de dos. He abierto la investigación y ubicado la promoción correspondiente.

**Comando:** C1 — Localizar promoción por nombre
**Resultado:**
Encontré `Promotions.Id = 212`, "Promo para compartir - Dijon", activa desde 2026-07-29, junto con otras promociones de nombre similar ("Hamburguesa/Combo - Clasica Dijon Con Papas", Id 39/52/67/81/122/136).

He identificado la Promoción 212 como la correspondiente al reporte.

## 2026-08-16 23:44 — Verificación de grupos y artículos de la promoción

**Comando:** C2 — Grupos y artículos elegibles
**Resultado:**
4 grupos (`Type=FixedPrice`, `MultipleSelection=False`), cada uno con un único `ArticleId`: dos grupos con ArticleId 85, dos con ArticleId 12.

He confirmado que la promoción tiene exactamente 4 grupos fijos, sin duplicados a nivel de `PromotionDetails`. Con esto he descartado que la causa esté en la cantidad de grupos configurados.

**Comando:** C3 — Identidad de artículos
**Resultado:**
ArticleId 85 = "Clasica con Dijon" (Signature Burgers); ArticleId 12 = "Papas Fritas" (Sides).

He confirmado que la promoción es 2 hamburguesas fijas + 2 papas fijas, sin mecanismo de selección múltiple a este nivel.

## 2026-08-16 23:50 — Descarte de hipótesis alternativas en Business/Catalog

**Comando:** C4 — Contenido del grupo "Signature Burgers"
**Resultado:**
30 artículos en el grupo, no 3.

He descartado la hipótesis de que el POS arme la selección de hamburguesas a partir de todo el grupo de catálogo.

**Comando:** C5/C6 — Introspección de `Oversales` y verificación de trigger para ArticleId 85
**Resultado:**
La tabla `Oversales` no tiene columna `PromotionId`; no existe trigger de upsell para ArticleId 85.

He descartado el sistema de upsell (`Oversales`) como causa.

**Comando:** C7 — Alcance de `PromotionApplies`
**Resultado:**
Las Promociones 39, 52 y 212 tienen `Include=True`, `PriceListId=912`, sin restricción de franquicia.

He confirmado que las tres promociones conviven activas sin restricción de franquicia, aunque no encontré relación directa con el defecto reportado.

## 2026-08-17 00:05 — Verificación de código fuente del armador de combo

**Comando:** C8 — Actualización y verificación del repo local
**Resultado:**
El clon local estaba 13 commits detrás de `origin/dev`; lo actualicé. Confirmé que `DialogBuildCombo.razor.cs` y `PromotionService.cs` son idénticos entre `main` (producción) y `dev`.

He verificado que el mecanismo de armado de combo (`GetItems`/`GetPriceDetails` en `DialogBuildCombo.razor.cs`) construye las opciones de cada grupo estrictamente a partir de `PromotionDetails.ArticleId`, lo cual es consistente con lo hallado en la base de datos. Con esto he confirmado que el POS interno no puede estar mostrando 3 opciones para esta promoción tal como está configurada.

## 2026-08-17 00:15 — Capturas de pantalla aportadas por el usuario

**Resultado:**
El usuario aportó dos capturas: una del POS interno mostrando el armado correcto de la promoción (2 grupos de hamburguesa + 2 de guarnición), y otra de una app móvil mostrando 5 grupos con "Clasica con Dijon 2" duplicado.

He identificado que la segunda captura corresponde a la app de PedidosYa, no al POS interno de SmartFran Cloud, y que el defecto real está ahí: "Clasica con Dijon 2" aparece dos veces y "Clasica con Dijon 1" una sola vez.

## 2026-08-17 00:20 — Descarte de causa en SmartPedidos

**Comando:** C9 — Búsqueda de integración de catálogo con PedidosYa
**Resultado:**
Sin resultados para código de exportación de menú en `repo/SmartFran.Cloud` (solo enums de logging de pedidos entrantes). Sin resultados para "menu" en los repositorios de `platforms-service` y `concentrador-service` de SmartPedidos.

He descartado que la duplicación se origine en SmartFran Cloud o en SmartPedidos. La integración de SmartPedidos con PedidosYa cubre únicamente el ciclo de vida de pedidos, no la publicación del catálogo/menú.

## 2026-08-17 00:25 — Cierre de la investigación

He concluido que la causa raíz es una configuración duplicada en el catálogo propio de PedidosYa, externa a los sistemas de SmartFran. He documentado el hallazgo en `ops.md` con el ticket Jira como placeholder `GSFC-XXX`, pendiente de reemplazo por el ID real.
