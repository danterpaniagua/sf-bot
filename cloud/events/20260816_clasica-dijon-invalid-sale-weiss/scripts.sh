# Queries run during this investigation (Business_WEISS / Catalog_WEISS, Azure SQL)
# Results pasted back by user, findings recorded in investigation.md

# 1. Locate "compartir"/"Dijon" promotion by name (Business_WEISS)
SELECT Id, Name, Description, PromotionType, MandatoryForAll,
       ValidSinceDate, ValidToDate, ActivatedDate, DeactivatedDate
FROM Promotions
WHERE Name LIKE '%compartir%' OR Description LIKE '%compartir%'
   OR Name LIKE '%Dijon%' OR Description LIKE '%Dijon%';

# 2. Groups + eligible articles for PromotionId=212 (Business_WEISS)
SELECT g.Id AS GroupId, g.Amount, g.Type AS GroupType, g.HasAdditionals, g.MultipleSelection,
       d.ArticleId
FROM PromotionGroups g
LEFT JOIN PromotionDetails d ON d.PromotionGroupId = g.Id
WHERE g.PromotionId = 212
ORDER BY g.Id, d.ArticleId;

# 3. Item identity for ArticleId 85/12 (Catalog_WEISS)
SELECT i.Id, i.Name, i.GroupId, g.FinancialModify, g.Name AS GroupName, i.ForSale
FROM Items i
LEFT JOIN Groups g ON g.Id = i.GroupId
WHERE i.Id IN (85, 12);

# 4. "Signature Burgers" catalog group contents (Catalog_WEISS) -- ruled out as source of "3 options"
SELECT Id, Name, GroupId, ForSale
FROM Items
WHERE GroupId = 1
ORDER BY Name;

# 5. Schema introspection for Oversales tables (Business_WEISS)
SELECT t.name AS TableName, c.name AS ColumnName, ty.name AS DataType
FROM sys.tables t
JOIN sys.columns c ON c.object_id = t.object_id
JOIN sys.types ty ON ty.user_type_id = c.user_type_id
WHERE t.name LIKE '%Oversale%'
ORDER BY t.name, c.column_id;

# 6. Oversale trigger check for ArticleId 85 (Business_WEISS) -- ruled out, no rows
SELECT ot.Id AS TriggerId, ot.SaleAmount, ot.Amount, ot.ItemId, ot.ItemType, ot.OversaleId,
       o.Name AS OversaleName, o.ActivatedDate, o.DeactivatedDate, o.ValidSinceDate, o.ValidToDate
FROM OversaleTriggers ot
JOIN Oversales o ON o.Id = ot.OversaleId
WHERE ot.ItemId = 85 AND ot.Deleted = 0;

# 7. PromotionApplies scoping for Promotions 39, 52, 212 (Business_WEISS)
SELECT p.Id AS PromotionId, p.Name, a.Include, a.FranchiseId, a.FranchiseeId, a.PriceListId
FROM Promotions p
LEFT JOIN PromotionGroups g ON g.PromotionId = p.Id
LEFT JOIN PromotionGroupsApplies ga ON ga.PromotionGroupId = g.Id
LEFT JOIN PromotionApplies a ON a.Id = ga.PromotionApplyId
WHERE p.Id IN (39, 52, 212)
ORDER BY p.Id;

# 8. Local repo maintenance (cloud/repo/SmartFran.Cloud) -- confirm/refresh against production
git fetch origin
git pull --ff-only origin dev
git diff origin/main origin/dev --stat -- \
  "Source/Pos/SmartFran.Cloud.Pos/SmartFran.Cloud.Pos.Component/Pages/Component/Dialog/DialogBuildCombo.razor.cs" \
  "Source/Pos/SmartFran.Cloud.Pos/SmartFran.Cloud.Pos.Component/Pages/Pos/Sale.razor.cs" \
  "Source/Services/Business/SmartFran.Cloud.Business.Application/Services/PromotionService.cs"

# 9. Source search for PedidosYa catalog/menu integration -- none found beyond order-receiving enums
grep -rli "pedidosya" --include="*.cs" --include="*.razor*" --include="*.json" .
