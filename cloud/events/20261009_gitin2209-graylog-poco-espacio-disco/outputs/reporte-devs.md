# Reporte para desarrollo — errores que llenan el disco de Graylog (GITIN-2209)

Ticket: https://smartit-ar.atlassian.net/browse/GITIN-2209

## Resumen

Desde el 2026-10-07 a las ~22:30 (hora local, UTC-3) el servicio Business de SmartCloud escribe unos 4,5 millones de mensajes por día en Graylog, contra unos 170 mil por día antes. Casi todo es un bucle de errores `invalid_grant` al refrescar tokens de MercadoPago de la aplicación QR: en una muestra de 44 segundos fallaban 2 cuentas de billetera (credenciales 31 y 66) de las 5 que consultan el endpoint. Es lo que hace crecer el disco de Graylog (el disco de datos se amplió de 512 a 768 GB el 2026-10-09; con el ritmo actual se llenaría alrededor del 2026-10-20 al 22, estimación).

## Entorno

Producción: los 30 mensajes de error de muestra (de 5.297 en los últimos 10 minutos) traen `Environment: Production` y `Service: SmartFran.Cloud.Business.API`; los logs están en el stream `PROD-Business-AppServicePlan` (index set `SFC-Business-prod`). No se agrupó el volumen total por `Environment` ni se verificó el entorno de los errores del lado del Concentrador de SmartPedidos.

## El error

- Logger: `SmartFran.Cloud.Provider.External.VirtualWallet.MercadoPago.Clients.MpOAuthClient`
- Mensaje: `MP API error: endpoint=/oauth/token statusCode=400 mainErrorCode=invalid_grant message=...`
- Ruta que dispara los intentos: `GET /api/v1/WalletCredentials/{userId}?applications=Delivery&applications=QR` (servicio Business). Lo consultan 5 `userId` distintos (unos 530 mil, 330 mil, 150 mil, 60 mil y 21 mil requests por día); los 2 primeros son los que fallan en la muestra y suman más del 85% de los requests. Falla el refresco de la credencial de la aplicación QR (`ApplicationType=QR`); en la muestra no aparecen fallos de la de Delivery.
- `invalid_grant` en OAuth significa que el token de refresco presentado no es válido (vencido, revocado, ya usado o cuenta desvinculada). El log no indica cuál de esos casos es.

## Magnitud (stream `PROD-Business-AppServicePlan`)

| Dato | Antes (2026-10-01 a 10-06) | Después |
|---|---|---|
| Mensajes por día | ~172 mil | ~4,54 millones (10-08: 3,54 M; 10-09: 4,34 M hasta las 17:41) |
| Nivel Error por día | 350–760 | 380.725 (10-08), 559.599 (10-09 hasta las 17:41) |
| Nivel Warning por día | 60–360 | 380.659 (10-08), 559.611 (10-09): casi idéntico al de Error, es decir, un Warning y un Error por cada fallo |
| Errores por hora | ~144 | ~25.980 desde las 23:00 del 10-07; ~31.700 desde las 23:00 del 10-08 (≈ 8,8 por segundo, constante de día y de noche) |

Mensajes por día por logger (nuevos desde el 10-07; antes, cero):

| Logger | Por día |
|---|---|
| `Microsoft.AspNetCore.Hosting.Diagnostics` (logs de request) | ~1,30 M |
| `...Business.Application.Services.VirtualWallet.MercadoPag...` | ~1,08 M |
| `...Provider.External.VirtualWallet.MercadoPago.Clients...` (`MpOAuthClient`) | ~1,08 M |
| `...Services.VirtualWallet.Abstractio...` | ~541 mil |
| `System.Net.Http.HttpClient.IWalletOAuthClient.ClientHandler` y `.LogicalHandler` | ~221 mil cada uno |

Cada llamada fallida genera unas seis líneas en Cloud.

## Relación con SmartPedidos

Los 2 `userId` que fallan en Cloud figuran entre los `user_id` de los errores `mercadopago_token_fetch failed` / `mercadopago_token_invalid_response` del Concentrador de SmartPedidos (GITIN-2208). El llamador, según los logs de Cloud, es un cliente máquina a máquina de Auth0 (sujeto `<client_id>@clients`), y ese mismo `client_id` figura como literal en la configuración de producción tanto del Concentrador como de Platform, así que cualquiera de los dos puede ser el llamador (no se distingue por el token). Dato no confirmado: el Concentrador registra muchas menos líneas de error que las ~8,8 por segundo que ve Cloud, así que falta verificar quién llama y con qué frecuencia.

## Observaciones sobre el código (rama `main` de SmartFran.Cloud, `WalletCredentialsService`)

- `ProcessCredentialAsync` renueva la credencial cuando `RequiresRenewal()` es verdadero (`ExpiresAt <= now + 7 días`). Si el refresco falla con `MpApiException`, registra un Warning (`WalletCredentials: refresh failed. credentialId=... mpStatusCode=400 mpErrorCode=invalid_grant`) y devuelve `null`; el comentario aclara que no se transiciona el estado de la credencial. La credencial queda Activa y vencida o por vencer, de modo que cada `GET` vuelve a intentar el mismo refresco con el mismo refresh token rechazado.
- El endpoint responde 204 cuando todas las credenciales pedidas fallan, y el llamador reintenta sin pausa.
- Hipótesis, sin verificar: el inicio escalonado (22:30 del 10-07 y escalones hasta las 23:00 del 10-08) coincidiría con el momento en que el `ExpiresAt` de cada credencial entró en la ventana de 7 días. Se confirma con una consulta de solo lectura a `WalletCredentials` (`ExpiresAt`, `LinkedAt`, `Status`).

## Cómo verlo en Graylog

Stream `PROD-Business-AppServicePlan`, consulta `AppLevel:Error`, rango desde el 2026-10-07 22:00. Agrupar por `SourceContext` y por `Path` muestra los números de arriba.

## Qué se pide a desarrollo

1. (Dev, Business) Cuando MercadoPago responda `invalid_grant`, no volver a intentar el refresco en cada `GET /api/v1/WalletCredentials/{userId}`: responder rápido con un error claro y recordar el resultado negativo por un tiempo (por ejemplo, minutos), y marcar la credencial como que necesita volver a vincularse.
2. (Dev, Business) Registrar un solo mensaje por fallo (hoy se registran un Warning y un Error por el mismo hecho) y, por credencial, limitar la frecuencia del log.
3. (Dev, Concentrador) Agregar espera creciente entre reintentos cuando falla la obtención del token de MercadoPago.
4. (Dev / Operaciones) Identificar a los titulares de las 2 cuentas que fallan (credenciales 31 y 66; verificar también las otras 3) para que vuelvan a autorizar la vinculación con MercadoPago.
5. (Dev) Definir si, mientras tanto, se sube el nivel mínimo de log de `Microsoft.AspNetCore.Hosting.Diagnostics` y `System.Net.Http.HttpClient.*` a Warning en Business (unos 1,5 millones de mensajes por día entre ambos). Es una medida provisoria.

## Datos que faltan

La causa de los `invalid_grant` (qué cambió el 2026-10-07 a las ~22:30); quién llama al endpoint y con qué frecuencia; qué ocurrió entre las 10:00 y las 15:00 del 10-08, cuando el bucle casi se detuvo.
