Query_Text
SELECT
    P.FirstName AS CustomerFirstName,
    P.LastName AS CustomerLastName,
    P.Id,
	GenderCode =(CASE 
			 WHEN p.gendercode ='Male' THEN 'Masculino'
			 WHEN p.gendercode ='Female' THEN 'Femenino'
			 else 'Otro'
			 END)	,
	AddressCustomer = (select top 1 
					 AddressCustomer  = ISNULL(b.street + ' - ', '') +   ISNULL( b.StreetNumber + ' - ', '') + ISNULL(b.neighborhood + ' - ','') 
					 + c.name + ' - ' + d.name 
					from Sml.person a
					inner join sml.address b on a.addressid= b.id
					inner join Sml.Location c on b.locationid= c.id 
					inner join Sml.Location d on c.ParentLocationId = d.Id 
					where a.id = P.Id),
    PP.CountryCode AS CountryCode,
    PP.AreaCode AS AreaCode,
    PP.Number AS PhoneNumber,
    ISNULL(PP.Mobile, 0) AS IsMobile,
    P.Email,
    Convert(Date , P.BirthDate) AS BirthDate,
    DATEDIFF(YEAR, P.BirthDate, GETUTCDATE()) AS Age,
    ISNULL(customerpoints.Points, 0) AS Points,
	AmountDayFromLastExchange= ISNULL( DATEDIFF(day,customerExchange.UltimoCanje, GETUTCDATE()), '0'),
    AmountDayFromLastPurchase= ISNULL (DATEDIFF(day,customerSale.UltimaCompra, GETUTCDATE()),'0') ,
    ISNULL(customerCantidadCompras.CantidadCompras, 0) AS AmountPurchaseLastYear,
	AmountExchangeLastYear = ISNULL(customerCantidadCanjes.CantidadCanjes, 0),
    ISNULL(KilosAnual.Kilocomprado, 0) AS KgPurchaseLastYear,
    AverageWeightInGr = Cast(KilosAnual.Gramoscomprado / customerCantidadCompras.CantidadCompras as decimal(10,2)),
    FavoriteProduct = (SELECT TOP 1 FavoriteProduct FROM @TempRankedProducts WHERE CustomerId = P.Id AND Ranking = 1),	
	PreferredPurchaseHour = ( 
        (SELECT TOP 1 
		 CASE 
			 WHEN PreferredPurchaseHour = 0 THEN '00:00 a 01:00'
			 WHEN PreferredPurchaseHour = 1 THEN '01:00 a 02:00'
			 WHEN PreferredPurchaseHour = 2 THEN '02:00 a 03:00'
			 WHEN PreferredPurchaseHour = 3 THEN '03:00 a 04:00'
			 WHEN PreferredPurchaseHour = 4 THEN '04:00 a 05:00'
			 WHEN PreferredPurchaseHour = 5 THEN '05:00 a 06:00'
			 WHEN PreferredPurchaseHour = 6 THEN '06:00 a 07:00'
			 WHEN PreferredPurchaseHour = 7 THEN '07:00 a 08:00'
			 WHEN PreferredPurchaseHour = 8 THEN '08:00 a 09:00'
			 WHEN PreferredPurchaseHour = 9 THEN '09:00 a 10:00'
			 WHEN PreferredPurchaseHour = 10 THEN '10:00 a 11:00'
			 WHEN PreferredPurchaseHour = 11 THEN '11:00 a 12:00'
			 WHEN PreferredPurchaseHour = 12 THEN '12:00 a 13:00'
			 WHEN PreferredPurchaseHour = 13 THEN '13:00 a 14:00'
			 WHEN PreferredPurchaseHour = 14 THEN '14:00 a 15:00'
             WHEN PreferredPurchaseHour = 15 THEN '15:00 a 16:00'
			 WHEN PreferredPurchaseHour = 16 THEN '16:00 a 17:00'
			 WHEN PreferredPurchaseHour = 17 THEN '17:00 a 18:00'
			 WHEN PreferredPurchaseHour = 18 THEN '18:00 a 19:00'
			 WHEN PreferredPurchaseHour = 19 THEN '19:00 a 20:00'
			 WHEN PreferredPurchaseHour = 20 THEN '20:00 a 21:00'
			 WHEN PreferredPurchaseHour = 21 THEN '21:00 a 22:00'
			 WHEN PreferredPurchaseHour = 22 THEN '22:00 a 23:00'
			 WHEN PreferredPurchaseHour = 23 THEN '23:00 a 00:00'			 
             ELSE CAST(PreferredPurchaseHour AS VARCHAR(2))
            END
        FROM @TempPreferredPurchaseHours
        WHERE CustomerId = P.Id
        ORDER BY SaleCount DESC)),
		 PreferredPurchaseDay = 
        (SELECT TOP 1 
		CASE 
			 WHEN PreferredPurchaseDay = 'Sunday' THEN 'Domingo'
			 WHEN PreferredPurchaseDay = 'Monday' THEN 'Lunes'
			 WHEN PreferredPurchaseDay = 'Tuesday' THEN 'Martes'
			 WHEN PreferredPurchaseDay = 'Wednesday' THEN 'Miercoles'
			 WHEN PreferredPurchaseDay = 'Thursday' THEN 'Jueves'
			 WHEN PreferredPurchaseDay = 'Friday' THEN 'Viernes'
			 WHEN PreferredPurchaseDay =  'Saturday' THEN 'Sabado'
            END
        FROM @TempPreferredPurchaseDay
        WHERE CustomerId = P.Id
        ORDER BY SaleCount DESC)
	
FROM
    Sml.BranchOffice B (NOLOCK) 
    INNER JOIN SmlSt.CustomerFavoriteBranchOffice CB (NOLOCK) ON B.Id = CB.BranchOfficeId and CB.BranchOfficeId = @BranchOfficeId
    INNER JOIN Sml.Person P (NOLOCK) ON CB.CustomerId = P.Id     
	inner join Sml.Customer customer on P.Id=customer.Id and customer.deativateddate is null and customer.createddate is not null --ESTO QUITAR LUEGO DE MODIFICAR EL SCRIPT QUE INSERTA EN LA SMLST.CUSTOMERFAVORITE   
  LEFT JOIN (
        SELECT PersonID, Number, AreaCode, CountryCode, Mobile,
               ROW_NUMBER() OVER (PARTITION BY PersonID ORDER BY Id DESC) AS rn
        FROM sml.PersonPhone (NOLOCK)
    ) AS PP ON P.Id = PP.PersonId AND (PP.Number IS NOT NULL AND PP.AreaCode IS NOT NULL AND PP.CountryCode IS NOT NULL) AND PP.rn = 1


    LEFT JOIN  Smlst.CustomerPointsLog as customerpoints ON P.Id = customerpoints.CustomerId  
    LEFT JOIN (
        SELECT MAX(saleDate) UltimoCanje, CustomerId FROM Sml.Sale s
        INNER JOIN Sml.SalePromotion AS sp ON s.Id = sp.SaleId
        INNER JOIN Sml.Promotion AS p on sp.PromotionId = p.Id
        WHERE p.Points < 0
        GROUP BY CustomerId
    ) AS customerExchange ON P.Id = customerExchange.CustomerId
	
    LEFT JOIN (
        SELECT MAX(SaleDate) UltimaCompra, CustomerId FROM Sml.Sale s
        INNER JOIN Sml.SalePromotion AS sp ON s.Id = sp.SaleId
        INNER JOIN Sml.Promotion AS p on sp.PromotionId = p.Id
         WHERE SaleDate >= DATEADD(MONTH, -6, GETDATE())and BranchOfficeId=@BranchOfficeId and p.Points < 0
        GROUP BY CustomerId
    ) AS customerSale ON P.Id = customerSale.CustomerId

    LEFT JOIN (
        SELECT COUNT(s.Id) CantidadCompras, CustomerId FROM Sml.Sale s
        INNER JOIN Sml.SalePromotion AS sp ON s.Id = sp.SaleId
        INNER JOIN Sml.Promotion AS p on sp.PromotionId = p.Id
        WHERE SaleDate >= DATEADD(MONTH, -6, GETDATE()) and BranchOfficeId=@BranchOfficeId and p.Points < 0 
        GROUP BY CustomerId
    ) AS customerCantidadCompras ON P.Id = customerCantidadCompras.CustomerId
	---------nuevo: cantidad de canjes--------------
	LEFT JOIN (
        SELECT COUNT(s.Id) CantidadCanjes, CustomerId FROM Sml.Sale s
        INNER JOIN Sml.SalePromotion AS sp ON s.Id = sp.SaleId
        INNER JOIN Sml.Promotion AS p on sp.PromotionId = p.Id
        WHERE SaleDate >= DATEADD(MONTH, -6, GETDATE()) and BranchOfficeId=@BranchOfficeId and p.Points < 0
        GROUP BY CustomerId
    ) AS customerCantidadCanjes ON P.Id = customerCantidadCanjes.CustomerId
	---------------------------------------
    LEFT JOIN (

        SELECT SUM(b.Amount * c.WeightGrams) AS Gramoscomprado, SUM(b.Amount * c.WeightGrams * 0.001) AS Kilocomprado, a.CustomerId
        FROM Sml.Sale a
        INNER JOIN Sml.SaleDetail b ON a.Id = b.SaleId
        INNER JOIN Sml.Product c ON b.ArticleId = c.Id
        WHERE SaleDate >= DATEADD(MONTH, -6, GETDATE()) and BranchOfficeId=@BranchOfficeId
        GROUP BY a.CustomerId
    ) AS KilosAnual ON P.Id = KilosAnual.CustomerId	
ORDER BY
    P.FirstName, P.UidCode ASC   , PP.Mobile DES

(1 row affected)


Completion time: 2026-06-01T00:13:26.8512158+00:00
