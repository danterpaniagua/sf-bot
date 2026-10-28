# [GITIN-2329](https://smartit-ar.atlassian.net/browse/GITIN-2329) — [OPE] Graylog: Problemas cont Token Creation

**Tags:** SmartCloud, Graylog, Obserbavilidad, SRE, PROD

## Qué pasó

- Usuarios de Graylog SmartCloud (`sfcloud-monitoreo`, versión 7.1.3) no veían la opción para crear un token de acceso a la API.
- Dos cuentas con los roles `Reader` y `Dashboard Creator` presentaban el mismo síntoma.
- La necesidad es una integración con IA a través de la API REST de Graylog (MCP queda fuera de alcance por ahora).

## Resumen

Los usuarios no administradores de Graylog SmartCloud no podían crear tokens de acceso, lo que impedía preparar una integración con IA vía API REST. Se detectó el 2026-10-27. Se revisaron los permisos de las cuentas afectadas, los roles de la instancia y la configuración global de usuarios, y se encontró que la configuración `restrict_access_token_to_admins` estaba en `true`. Se cambió a `false` y se verificó que una cuenta no administradora ya tiene `users:tokencreate` sobre sí misma.

## Tabla resumen

| Campo | Valor |
|---|---|
| Ticket Jira | [GITIN-2329](https://smartit-ar.atlassian.net/browse/GITIN-2329) |
| ID alerta | NA |
| Sistema | Graylog SmartCloud (`sfcloud-monitoreo`, 7.1.3) |
| Severidad | Baja |
| Detectado | 2026-10-27 |
| Resuelto | 2026-10-27 (cambio aplicado y permisos verificados) |
| Responsable | SRE |

## Causa raíz

La configuración global `restrict_access_token_to_admins` de `org.graylog2.users.UserConfiguration` estaba en `true`, de modo que solo los administradores podían crear tokens. Los usuarios afectados conservaban `users:tokenlist` y `users:tokenremove` sobre su propia cuenta, pero no tenían `users:tokencreate`. Tras cambiar la configuración a `false`, una cuenta no administradora muestra `users:tokencreate` sobre sí misma y se reportó la creación de un token desde esa cuenta. No se capturó el estado previo de esa misma cuenta, por lo que la relación entre la configuración y la aparición del permiso es consistente con los datos pero no se aisló con una prueba aparte. No se identificaron ocurrencias anteriores del mismo síntoma.

## Hallazgos

| # | Hallazgo | Riesgo |
|---|---|---|
| H1 | `restrict_access_token_to_admins` estaba en `true` en la configuración global de usuarios | Bajo |
| H2 | Ningún rol de la instancia otorga `users:tokencreate`, salvo `Sidecar Manager` y solo para el usuario `graylog-sidecar`; los 16 roles son de solo lectura (integrados) | Bajo |
| H3 | Con la restricción en `false`, cualquier usuario puede crear tokens que actúan como esa cuenta | Medio |
| H4 | Una cuenta consultada tiene permisos `streams:read` directos sobre 10 streams (`Default Stream`, `DEV` y los 8 `PROD-*-AppServicePlan`), independientes de los roles | Bajo |

## Acciones Tomadas

| # | Hora (UTC) | Acción |
|---|---|---|
| 1 | 2026-10-27 | Revisados permisos de usuario y roles de las cuentas afectadas y la configuración global de usuarios (solo lectura) |
| 2 | 2026-10-27 21:15 | Creado el rol personalizado `AI Integration Streams` con `streams:read` sobre 12 streams de logs de aplicación |
| 3 | 2026-10-27 21:19 | Cambiado `restrict_access_token_to_admins` de `true` a `false`; guardado el objeto original para revertir |
| 4 | 2026-10-27 21:25 | Creados los roles `AI Integration Streams DEV` y `AI Integration Streams HTTP` |
| 5 | 2026-10-27 21:37 | Eliminados los tres roles personalizados (ninguno tenía miembros); respaldos de su definición guardados |

## Recursos afectados

| Recurso | Detalle |
|---|---|
| Graylog SmartCloud | `sfcloud-monitoreo.smartfran.com`, configuración de clúster `org.graylog2.users.UserConfiguration` |

## Acciones propuestas

| # | Responsable | Acción | Estado |
|---|---|---|---|
| 1 | SRE | Eliminar los tokens de prueba creados durante las verificaciones | Pendiente |
| 2 | SRE | Revisar más adelante si `restrict_access_token_to_admins` debe volver a `true` (revertir con el respaldo del objeto original) | Por decidir |
| 3 | SRE | Definir la cuenta que usará la integración con IA (cuenta dedicada o cuenta personal) y los streams que debe leer | Por decidir |
