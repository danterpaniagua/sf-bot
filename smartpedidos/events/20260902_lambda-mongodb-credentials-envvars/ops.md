# 02-09-2026_lambda-mongodb-credentials-envvars

**Tags:** SmartPedidos, MongoDB, AWS, SEGURIDAD

## Resumen

La cadena de conexión a MongoDB de `mongo-to-s3-CFN-ScheduledMongoToS3-1EZXBGD94CJVO` estaba originalmente hardcodeada en texto plano en el código fuente de la Lambda, y fue migrada a variables de entorno (`MONGO_USER`, `MONGO_PASSWD`, `HOST`, `DATABASE`). Este ticket registra esa migración. No se cuenta en este repositorio con evidencia independiente de la versión original en texto plano — se documenta según lo reportado, sin verificación propia vía diff o snapshot de código anterior.

## Tabla resumen

| Campo | Valor |
|---|---|
| Ticket Jira | [GITIN-1973](https://smartit-ar.atlassian.net/browse/GITIN-1973) |
| Ticket padre | GITIN-1872 |
| ID alerta | — |
| Sistema | mongo-to-s3-CFN-ScheduledMongoToS3-1EZXBGD94CJVO (Lambda, SmartPedidos) |
| Severidad | — (remediación ya completada, reportada) |
| Detectado | No establecido — anterior a esta sesión |
| Resuelto | Reportado como ya migrado a variables de entorno; fecha exacta no establecida |
| Responsable | Dante Paniagua, SRE (registro), migración original de autoría no confirmada |

## Causa raíz

No investigada en esta sesión — la migración de texto plano a variables de entorno se reporta como ya realizada antes de este trabajo. Todo el código fuente de la Lambda revisado durante GITIN-1970 ya usa `process.env.MONGO_USER`/`MONGO_PASSWD`/`HOST`/`DATABASE`, consistente con la migración reportada.

## Hallazgos

| # | Hallazgo | Riesgo |
|---|---|---|
| H1 | Migración de credencial de MongoDB en texto plano a variables de entorno, reportada como completa. Sin evidencia propia de la versión original — no verificado de forma independiente en esta sesión. | — (mejora reportada, sin riesgo activo confirmado) |
| H2 | Nota de alcance: existe un bug distinto y no relacionado en la misma línea de código (interpolación de template literal faltante, corregido bajo GITIN-1970) — bug en el código *ya migrado* a variables de entorno, no una regresión al patrón de texto plano. No confundir ambos hallazgos. | — |

## Recursos afectados

| Componente | Impacto |
|---|---|
| mongo-to-s3-CFN-ScheduledMongoToS3-1EZXBGD94CJVO (Lambda) | Credenciales de MongoDB actualmente en variables de entorno, confirmado en el código revisado durante GITIN-1970 |

## Comandos ejecutados

Ninguno — ticket de registro, sin verificación técnica propia en esta sesión.

## Acciones propuestas

1. **(SRE, opcional)** Si se necesita evidencia formal de la versión original en texto plano (por ejemplo para una auditoría de seguridad), buscarla en historial de git o de despliegues — no disponible en este repositorio.

## Hallazgos secundarios

Se descartó inicialmente una conexión con la investigación `20260720_credenciales-mongodb-hardcodeadas/` (credenciales hardcodeadas en `concentrador-service`/`platforms-service`) — confirmado que son temas distintos, no relacionados.
