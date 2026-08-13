-- GITIN-1816 — WebServiceCG AccountRecovery no envía email
-- DB: SmartFran.Solution.SmartLoyalty

-- Q1: Solicitudes de recupero de cuenta recientes vía canal BOT (WebServiceCG),
-- con el resultado real del intento de envío de email (SendEmailError NULL = envío OK).
-- Ajustar el filtro de fecha / UidCode-UidSerie según el caso reportado.
SELECT
    car.Id,
    car.UidCode,
    car.UidSerie,
    car.Email,
    car.CreatedDate,
    car.SourceChannel,
    car.AcceptedDate,
    car.SendEmail        AS SendEmailAttemptedAt,
    car.SendEmailError,
    car.FinishedDate,
    car.ManagedUser
FROM Sml.CustomerAccountRecovery car
WHERE car.SourceChannel = 'BOT'
  AND car.CreatedDate >= DATEADD(DAY, -7, GETUTCDATE())
ORDER BY car.CreatedDate DESC;

-- Q2: Solo las que tuvieron error real en el envío (evidencia directa de la causa).
SELECT
    car.Id,
    car.UidCode,
    car.UidSerie,
    car.Email,
    car.CreatedDate,
    car.SendEmail        AS SendEmailAttemptedAt,
    car.SendEmailError
FROM Sml.CustomerAccountRecovery car
WHERE car.SendEmailError IS NOT NULL
  AND car.CreatedDate >= DATEADD(DAY, -7, GETUTCDATE())
ORDER BY car.CreatedDate DESC;

-- Q3: Caso puntual reportado — Sofilualbornoz@icloud.com, solicitud ~2026-08-10T02:08:20 UTC.
-- CreatedDate es DateTimeOffset; se amplía la ventana ±2h por si el timestamp reportado
-- corresponde a otro punto del flujo (AcceptedDate / SendEmail) y no a CreatedDate.
SELECT
    car.Id,
    car.UidCode,
    car.UidSerie,
    car.Email,
    car.CreatedDate,
    car.SourceChannel,
    car.AcceptedDate,
    car.SendEmail        AS SendEmailAttemptedAt,
    car.SendEmailError,
    car.FinishedDate,
    car.ManagedUser
FROM Sml.CustomerAccountRecovery car
WHERE car.Email = 'Sofilualbornoz@icloud.com'
  AND car.CreatedDate BETWEEN '2026-08-10T00:08:20.58776+00:00' AND '2026-08-10T04:08:20.58776+00:00'
ORDER BY car.CreatedDate DESC;
