#!/bin/bash
# Evento: 20260802_promocion-invalida-weiss-franui
# Todas las consultas son de solo lectura salvo la marcada con ⚠️ (propuesta de fix, aun no ejecutada)
# DB destino segun consulta: SmartFran.Cloud.Business_WEISS (promociones) / SmartFran.Cloud.Catalog_WEISS (items, precios)

# === C1 — Buscar promocion/combo "franui" y su estructura en Business_WEISS ===
SELECT Id, Name, Description, PromotionType, MandatoryForAll,
       ValidSinceDate, ValidToDate, ValidSinceMinute, ValidToMinute,
       ActivatedDate, DeactivatedDate
FROM Promotions
WHERE Name LIKE '%franui%' OR Description LIKE '%franui%';
# OUTPUT (2026-08-02):
# Id 86/87 "Promo Cheeseburguer+Picker+Helado" (PromotionType 0/1) -> DeactivatedDate 2026-02-16, fuera de vigencia (periodo Feb 2026)
# Id 183 "Ruleta Articulo Bonificado" -> Activada (ActivatedDate 2026-06-19), ValidToDate 2026-07-31 (EXPIRADA, 2 dias antes de este evento)
# Id 186 "Ruleta Articulo Bonificado" -> ValidToDate 2028-03-31 (vigente), pero ActivatedDate NULL (NUNCA activada)
# -> hallazgo secundario: gap de activacion en la promo "Ruleta Articulo Bonificado" (ver Hallazgos secundarios en el ticket)
# Consultas complementarias (PromotionGroups/PromotionDetails/PromotionGroupsApplies para estas promociones) no arrojaron
# datos adicionales relevantes para la causa raiz final.

# === C2 — Confirmar base de datos real conectada, tras error "Invalid object name 'PriceDetails'" ===
SELECT DB_NAME() AS CurrentDatabase;
SELECT TABLE_NAME FROM INFORMATION_SCHEMA.TABLES ORDER BY TABLE_NAME;
# OUTPUT (2026-08-02): confirma conexion a SmartFran.Cloud.Catalog_WEISS; existen Items, Groups, PriceDetails, PriceLists.
# El error inicial se debio a estar conectado a Business_WEISS en el intento anterior.

# === C3 — Buscar item "Descuento Influencers" en Catalog_WEISS ===
SELECT i.Id, i.Name, i.GroupId, g.FinancialModify, g.Name AS GroupName
FROM Items i
LEFT JOIN Groups g ON g.Id = i.GroupId
WHERE i.Name LIKE '%influencer%';
# OUTPUT (2026-08-02):
# Id 430, Name "Descuento Influencers 100%", GroupId 243, GroupName "Descuento", FinancialModify = 1 (Discount)

# === C4 — Precio configurado del item 430 en PriceDetails ===
# Primer intento fallo: "Invalid column name 'Price'" (la columna real es PublishedPrice/NewPrice, no Price)
SELECT pd.ItemId, pd.PriceListId, pd.PublishedPrice, pd.NewPrice, pd.Enabled
FROM PriceDetails pd
JOIN Items i ON i.Id = pd.ItemId
WHERE i.Name LIKE '%influencer%';
# OUTPUT (2026-08-02): 8 filas (PriceListId 908, 910, 914-919), TODAS con PublishedPrice = NewPrice = 99.99, Enabled = True
# -> CAUSA RAIZ: el item deberia estar a 100.00 (su propio nombre indica "100%"); 99.99 deja un residuo del 0.01% sin descontar.

# === C5 — Buscar item "franui" en Catalog_WEISS ===
SELECT i.Id, i.Name, i.GroupId, i.ForSale, g.FinancialModify
FROM Items i
LEFT JOIN Groups g ON g.Id = i.GroupId
WHERE i.Name LIKE '%franui%';
# OUTPUT (2026-08-02):
# Id 386 "Franui", GroupId 59, ForSale=True, FinancialModify=0 (item de venta normal, no combo ni modificador financiero)
# Id 423 "Franui c/Combo", GroupId 59, ForSale=True, FinancialModify=0 (idem)
# -> descarta la hipotesis de que "franui" fuera en si mismo una promocion/combo con multiples lineas de cuerpo

# === C6 — Pruebas manuales en POS (sin script, reportadas por el usuario) ===
# a) 2 hamburguesas + franui + Descuento Influencers, pago Transferencia -> venta invalida
# b) 2 hamburguesas + franui + Descuento Influencers, pago Efectivo -> venta invalida (descarta el metodo de pago como variable)
# c) Total con descuento: 2 hamburguesas + franui = $0.17 (falla) vs 2 hamburguesas solas = $0.14 (pasa)
# d) Solo franui (sin combo de hamburguesas) + descuento -> venta invalida
# e) Item "Franui c/Combo" (linea tipo combo) + descuento -> pasa; item "Franui" simple + descuento -> falla
# -> (e) explica por que el mismo defecto de precio no se manifiesta en todas las ventas: las lineas tipo combo
#    recalculan y redondean su UnitPrice (Total/Quantity), lo que absorbe el residuo del 0.01%; las lineas de
#    producto simple no tienen ese recalculo y el residuo llega intacto a la validacion payments >= total.

# === REMEDIACION (propuesta, NO ejecutada) ===
# ⚠️ C7 — Corregir precio del item 430 de 99.99 a 100.00 en las 8 listas de precio (Catalog_WEISS)
-- Previsualizacion antes de aplicar
SELECT ItemId, PriceListId, PublishedPrice, NewPrice, Enabled
FROM PriceDetails
WHERE ItemId = 430;

-- Fix propuesto
UPDATE PriceDetails
SET PublishedPrice = 100.00,
    NewPrice = 100.00
WHERE ItemId = 430
  AND PublishedPrice = 99.99;
