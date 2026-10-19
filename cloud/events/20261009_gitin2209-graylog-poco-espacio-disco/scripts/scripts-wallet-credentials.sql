-- Event: 20261009_gitin2209-graylog-poco-espacio-disco
-- C5 — SOLO LECTURA, contra la base de Business del tenant afectado. No selecciona tokens ni correos.
-- Salida sugerida: data/business/detail-wallet-credentials.txt (excluida del control de versiones por contener identificadores).

-- (a) Credenciales activas que estan en la ventana de renovacion (vencen en <= 7 dias o ya vencieron):
--     son las que RequiresRenewal() manda a refrescar contra MercadoPago en cada GET /api/v1/WalletCredentials/{userId}.
SELECT acc.WalletUserId, acc.FranchiseeId, acc.Provider, acc.Deleted AS AccountDeleted,
       app.[Type] AS AppType, app.IsActive AS AppActive,
       cred.Id AS CredentialId, cred.[Status], cred.LinkedAt, cred.ExpiresAt,
       DATEDIFF(day, SYSUTCDATETIME(), cred.ExpiresAt) AS DaysToExpire
FROM dbo.WalletCredentials AS cred
JOIN dbo.WalletAccounts     AS acc ON acc.Id = cred.WalletAccountId
JOIN dbo.WalletApplications AS app ON app.Id = cred.ApplicationId
WHERE cred.Deleted = 0 AND cred.[Status] = 'Active'
  AND cred.ExpiresAt <= DATEADD(day, 7, SYSUTCDATETIME())
ORDER BY cred.ExpiresAt;

-- (b) Cuantas credenciales activas hay por tramo de vencimiento (las que entren a la ventana de 7 dias
--     podrian sumarse al mismo bucle si su refresh token tambien es rechazado).
SELECT CASE WHEN cred.ExpiresAt <= SYSUTCDATETIME() THEN '0_vencidas'
            WHEN cred.ExpiresAt <= DATEADD(day, 7,  SYSUTCDATETIME()) THEN '1_vencen_en_7d'
            WHEN cred.ExpiresAt <= DATEADD(day, 30, SYSUTCDATETIME()) THEN '2_vencen_en_30d'
            ELSE '3_mas_de_30d' END AS Tramo,
       COUNT(*) AS Credenciales
FROM dbo.WalletCredentials AS cred
WHERE cred.Deleted = 0 AND cred.[Status] = 'Active'
GROUP BY CASE WHEN cred.ExpiresAt <= SYSUTCDATETIME() THEN '0_vencidas'
              WHEN cred.ExpiresAt <= DATEADD(day, 7,  SYSUTCDATETIME()) THEN '1_vencen_en_7d'
              WHEN cred.ExpiresAt <= DATEADD(day, 30, SYSUTCDATETIME()) THEN '2_vencen_en_30d'
              ELSE '3_mas_de_30d' END
ORDER BY Tramo;
