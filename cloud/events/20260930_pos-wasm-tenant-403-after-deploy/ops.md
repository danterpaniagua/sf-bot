# [CLOUD] Error 403 SFC-POSWASMRELAY-PRO — GITIN-2134

**Tags:** `SmartCloud`, `CloudPOS`, `Graylog`, `Auth0`, `PROD`

## Resumen

Tras el despliegue a PRO de la versión v02.46.00 (2026-09-30), los logs del cliente POS (Blazor WASM) que reenvía el Function App `SFC-POSWASMRELAY-PRO` a Graylog muestran respuestas HTTP 403 a `GET /api/Tenant/{id}`. En los últimos 7 días hay 70 mensajes con 403 del POS; 69 corresponden a la misma ruta (`/api/Tenant/d3186bc6d7b2`). El primer 403 es del 2026-09-30 a las 11:59 UTC y no hay ninguno en los 6 días previos. En las últimas 24 horas otros clientes de la misma ruta (Client.Web, Platform API, Business API) reciben 200.

La causa aún no está determinada. La hipótesis principal y los puntos pendientes de verificación se detallan abajo.

## Tabla resumen

| Campo | Valor |
|---|---|
| Ticket Jira | GITIN-2134 |
| ID alerta | N/A |
| Sistema | SmartFran Cloud — POS (Blazor WASM), Platform API, Auth0 (tenant PRO), Graylog |
| Severidad | Por definir |
| Detectado | 2026-09-30 |
| Resuelto | No — causa raíz pendiente de confirmar |
| Responsable | SRE |

## Causa raíz

Pendiente de confirmar.

**Hipótesis principal:** el release v02.46.00 (GSFC-1005) rehabilitó `[Authorize]` a nivel de clase en `TenantController` (estaba comentado desde el origen) y agregó `[RequiredScope("read:tenant")]` a `GET /api/Tenant/{identifier}`. Una llamada con token válido pero sin el scope `read:tenant` recibe 403. Es coherente con un 403 (y no un 401) y con que otros clientes reciban 200, pero no se observó el token de una llamada fallida.

**Explicaciones posibles, ninguna confirmada:**
1. El cliente POS de PRO no solicita `read:tenant` (o no usa el audience `smartfran-cloud-prod`) en su configuración de PRO.
2. El usuario afectado no tiene rol, o lo tiene solo por membresía a una Organization.
3. Sesiones del POS abiertas desde antes de que el cliente solicitara `read:tenant` siguen usando tokens emitidos sin ese scope.

## Hallazgos

| # | Hallazgo | Riesgo |
|---|---|---|
| H1 | 70 mensajes 403 del servicio `smartfran-pos-wasm` en 7 días (69 en `/api/Tenant/d3186bc6d7b2`); primer 403 a las 11:59 UTC del 2026-09-30; ninguno previo. | Por evaluar |
| H2 | Commit del release v02.46.00 en `main` (`d969856fa`) incluye el cambio de autorización de GSFC-1005 en `GET /api/Tenant/{identifier}` (`[Authorize]` + `read:tenant`); los endpoints `Organization/*` siguen anónimos. | Por evaluar |
| H3 | La ruta responde 200 a otros llamadores en las últimas 24 h: Client.Web (6.156), Platform API (504), Business API (8). El 403 es específico del POS. | Por evaluar |
| H4 | El servicio `smartfran-pos-wasm` solo envía a Graylog llamadas fallidas (404, 500, 408, 400, 403; ningún 2xx en 7 días). Graylog no permite saber qué usuarios funcionan. | Bajo |
| H5 | La llamada fallida llegó a la Platform API (hay un mensaje suyo bajo el mismo `TraceKey`), pero sin código de estado ni motivo de autorización. `UserId` no está disponible en estos logs (vacío en todas las muestras). | Bajo |
| H6 | Tenant Auth0 PRO (`smartfran-cloud`): API `SmartFran.Cloud.API_PROD` (audience `smartfran-cloud-prod`, RBAC activo, 139 permisos). Los 8 roles incluyen `read:tenant`; solo Owner tiene `write:tenant`. El rol Collaborator (uso del POS, 146 miembros) incluye `read:tenant`. Los roles no explican el 403 para usuarios que los tengan. | Bajo |
| H7 | La configuración de scopes y audience del cliente POS en PRO no está en el repositorio (existen archivos de configuración de DEV, STG y TEST, todos con `read:tenant`). | Por evaluar |

## Recursos afectados

| Componente | Participación |
|---|---|
| POS Blazor WASM (PRO) | Origen de las llamadas con 403 |
| SFC-POSWASMRELAY-PRO | Reenvía los logs del cliente a Graylog |
| Platform API (`GET /api/Tenant/{id}`) | Recibe la llamada; ruta con `read:tenant` desde v02.46.00 |
| Auth0 (tenant `smartfran-cloud`) | Emite los tokens; roles y permisos de la API |

## Comandos ejecutados

| # | Comando / Script | Propósito |
|---|---|---|
| C1 | Consultas de agregación en Graylog (API de búsqueda) sobre `smartfran-pos-wasm`: 403 por ruta, por tenant y por código de estado (24 h y 7 días) | Volumen, inicio y alcance de los 403 |
| C2 | Búsqueda en Graylog por `TraceKey` de la llamada de muestra | Ver qué registró cada servicio para esa llamada |
| C3 | Consulta en Graylog de `/api/Tenant/` en todos los servicios, agrupada por servicio y código | Comparar con los demás llamadores |
| C4 | `scripts.sh` (Auth0 Management API, solo lecturas) | Roles, permisos, APIs y organizaciones del tenant PRO |
| C5 | Revisión del código de `main` (`TenantController`, configuración del cliente POS) | Cambio de autorización del release |

La salida de cada consulta está en la carpeta `data/` del evento.

## Acciones propuestas

1. (SRE) Obtener de una llamada fallida en el navegador del usuario afectado el encabezado `WWW-Authenticate` de la respuesta y los nombres de los claims del token (`aud`, `scope`, `permissions`, `iss`), sin copiar el token.
2. (SRE) Verificar los scopes y el audience que solicita el cliente POS en PRO (configuración de PRO; no está en el repositorio).
3. (SRE) Pedir a un usuario afectado que cierre sesión, recargue el POS e inicie sesión otra vez, y reintentar la llamada, para evaluar la hipótesis de sesiones abiertas previas.
4. (SRE) Revisar en Auth0 los roles asignados por membresía a Organization y los usuarios sin rol (requiere el permiso `read:organization_member_roles` en la aplicación de consulta).
5. (SRE) Revisar los logs de Auth0 de la aplicación `SFC PoS` desde las 11:59 UTC para identificar los usuarios (requiere `read:logs`).
6. (Dev) Evaluar registrar en la Platform API el motivo del 403 (usuario y scope faltante) para poder diagnosticarlo desde Graylog. Propuesta sin decisión tomada.
