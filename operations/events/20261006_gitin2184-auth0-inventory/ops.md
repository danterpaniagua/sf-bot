# [OPE] Inventario Auth0

**Tags:** `SmartCloud`, `SRE`

## Resumen

No existía un inventario documentado de lo que contienen los tenants de Auth0 de SmartCloud (dev `dev-wzt4q1xqoe7cwz0f` y prod `smartfran-cloud`): APIs y sus permisos, aplicaciones, permisos delegados, usuarios, roles y organizaciones. Se relevó el contenido de ambos tenants mediante llamadas de solo lectura a la Management API y se consolidó en este ticket. El relevamiento no modifica ningún recurso de Auth0. Queda pendiente el análisis del detalle de permisos delegados por aplicación y de la membresía de roles/organizaciones de los usuarios internos.

## Tabla resumen

| Campo | Valor |
|---|---|
| Ticket Jira | [GITIN-2184](https://smartit-ar.atlassian.net/browse/GITIN-2184) |
| ID alerta | N/A |
| Sistema | Auth0 — tenants `dev-wzt4q1xqoe7cwz0f` y `smartfran-cloud` |
| Severidad | N/A (relevamiento) |
| Detectado | 2026-10-06 |
| Resuelto | Relevamiento completado; análisis de detalle pendiente |
| Responsable | SRE — Operaciones |

## Causa raíz

NA

## Hallazgos

Inventario por tenant:

| # | Entidad | Dev | Prod |
|---|---|---|---|
| H1 | APIs (resource servers) | 9 (1 de sistema: Management API) | 3 (1 de sistema: Management API) |
| H2 | Aplicaciones / clients | 57 | 13 |
| H3 | Client grants (permisos delegados) | 71 sobre 39 clients | 11 sobre 9 clients |
| H4 | Roles | 15 | 8 |
| H5 | Organizaciones | 7 | 4 |
| H6 | Usuarios | 89 | 1235 |
| H7 | Conexiones | `google-oauth2`, `Username-Password-Authentication` | las mismas dos |

Detalle relevante:

| # | Hallazgo | Riesgo |
|---|---|---|
| H8 | APIs de negocio. Dev: `SmartFran.Cloud.Catalog.API_*` por ambiente (LOCAL, DEV, DEV2, TEST, STG, DEMO; entre 107 y 155 permisos cada una), `SmartFran.Cloud.API Pruebas Locales` (12) y `SmartFran.Loyalty.WebServiceCG` (0 permisos). Prod: `SmartFran.Cloud.API_PROD` (139 permisos) y `SmartFran.Loyalty.WebServiceCG` (0 permisos). | Bajo |
| H9 | Aplicaciones. Prod: 2 SPA (`SFC Manager`, `SFC PoS`) y 11 aplicaciones M2M (`client_credentials`), incluida `Default App` con `client_credentials` e `implicit` habilitados. Dev: SPAs por ambiente (`Client.Web_*`, `POS_*`, Delegated Admin) y M2M por servicio y ambiente; varios nombres están duplicados (p. ej. dos `SmartFran.Cloud.Business.API_LOCAL (Test Application)`). | Medio |
| H10 | Roles (permisos / miembros). Prod: Collaborator 31/146, Franchisee 55/72, FranchiseeExecutive 2/0, Franchisor 56/1, FranchisorExecutive 5/2, Kitchen 12/2, Owner 107/36, Wholesale 31/2. Dev: 15 roles, incluidos 4 `Delegated Admin - *` y roles de prueba. | Bajo |
| H11 | Organizaciones (miembros). Prod: grido 1114, jacinto 19, ultracai 23, weiss 114. Dev: demo 10, grido 80, jacinto 23, mayorista 25, otro 13, subway 1, weiss 47. En dev, la organización `subway` no tiene conexión habilitada; el resto tiene `Username-Password-Authentication`. La suma de miembros en prod (1270) supera los usuarios (1235), por lo que algunos usuarios pertenecen a más de una organización (sin verificar cuáles). | Bajo |
| H12 | Usuarios. Prod: 1226 con `Username-Password-Authentication` y 9 con `google-oauth2`; 99 nunca iniciaron sesión; 83 con email sin verificar; 0 bloqueados. Dev: 77 / 12; 4 nunca iniciaron sesión; 8 sin verificar; 0 bloqueados. Emails distintos: 82 de 89 (dev) y 1230 de 1235 (prod); no se investigó la causa de los repetidos. | Bajo |
| H13 | Usuarios con dominio `@smartfran.com`: 64 de 89 en dev y 62 de 1235 en prod. No existen otras variantes de dominio `smartfran`. | Bajo |

## Recursos afectados

| Recurso | Detalle |
|---|---|
| Tenant Auth0 dev | `dev-wzt4q1xqoe7cwz0f` |
| Tenant Auth0 prod | `smartfran-cloud` |
| Aplicación M2M de relevamiento | Una aplicación M2M por tenant con permisos de lectura sobre la Management API (solo lectura) |

## Comandos ejecutados

Detalle en `scripts.sh` y `scripts-users.sh`; salidas en `data/`. Todas las llamadas son de solo lectura. Los emails se guardan solo en archivos locales excluidos del repositorio.

| # | Comando / Script | Propósito |
|---|---|---|
| C1 | `resource-servers` | APIs y sus permisos |
| C2 | `clients` (sin secretos) | Aplicaciones |
| C3 | `client-grants` | Permisos delegados por aplicación |
| C4 | `roles` | Roles |
| C5 | `organizations` | Organizaciones |
| C6 | `users` (metadata, sin datos personales) | Muestra de usuarios |
| C7 | `connections` | Conexiones de identidad |
| C8 | `users` con búsqueda v3 | Total de usuarios (el listado simple se trunca en 1000) |
| C9 | `roles/{id}/permissions` y `roles/{id}/users` | Permisos y cantidad de miembros por rol |
| C10 | `organizations/{id}/members` y `enabled_connections` | Miembros y conexiones por organización |
| C11 | `scripts-users.sh` | Listado completo de usuarios por ventanas mensuales de alta |
| C12 | Filtro local por dominio `@smartfran.com` | Identificar usuarios internos |

## Acciones propuestas

1. (SRE) Relevar el detalle de permisos delegados por aplicación (qué aplicación M2M tiene qué permisos sobre qué API) a partir de `client-grants`.
2. (SRE) Cruzar los usuarios `@smartfran.com` con roles y organizaciones, y con su existencia en dev y prod.
3. (SRE) Revisar con el equipo las aplicaciones con nombre duplicado en dev, la `Default App` y las aplicaciones "(Test Application)" para decidir si corresponde su baja o ajuste. Es una revisión, no una decisión tomada.
4. (SRE) Revisar la causa de los emails repetidos (7 en dev, 5 en prod).
