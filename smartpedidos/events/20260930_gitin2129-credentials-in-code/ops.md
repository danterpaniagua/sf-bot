# [SP] Credenciales en Codigo

**Tags:** SmartPedidos, Platform, Concentrador

| Campo | Valor |
|---|---|
| Ticket Jira | [GITIN-2129](https://smartit-ar.atlassian.net/browse/GITIN-2129) |
| Subtareas | [GITIN-2130](https://smartit-ar.atlassian.net/browse/GITIN-2130) Credenciales Platform · [GITIN-2131](https://smartit-ar.atlassian.net/browse/GITIN-2131) Credenciales Concentrador |
| Relacionado | [GITIN-1715](https://smartit-ar.atlassian.net/browse/GITIN-1715) (padre [GITIN-1606](https://smartit-ar.atlassian.net/browse/GITIN-1606)) |
| Sistema | platforms-service, concentrador-service |
| Detectado | 2026-09-30 (relevamiento de archivos de configuración; hallazgo de credenciales AWS en un escaneo Trivy, ver GITIN-2116) |
| Responsable | SRE / Dev |

## Resumen

Los archivos de configuración por ambiente (`api/src/config/env/*.js`) de platforms-service y concentrador-service contienen campos de credenciales (`secret`, `password`, `client_secret`, `AWS_SECRET`, `MERCADOPAGO_DELIVERY_TOKEN`, `tokenEncryption`, entre otros) definidos como valores literales, incluyendo `production.js`. Este ticket define el plan de acción para adoptar una práctica estándar de manejo de credenciales y sirve como registro histórico del tratamiento aplicado en cada repositorio.

Aún no se ha verificado cuáles de esos literales son secretos reales y cuáles son valores no sensibles (URLs, placeholders), ni cuáles están versionados en la rama de producción (`develop`).

## Alcance

**Desarrollo local:** hoy las credenciales no se leen desde variables de entorno sino desde literales en `config/env/*.js`. El alcance de este ticket es que pasen a cargarse por variables de entorno (archivo `.env` local excluido de git y un `.env.example` sin valores), de modo que los desarrolladores no compartan credenciales ni existan en el código.

**Fuera de alcance:** el almacenamiento de credenciales en los ambientes desplegados con el Key Vault de AWS (GITIN-1715); cambios de lógica de negocio; la actualización de dependencias npm (GITIN-2116).

**Por definir:** si la rotación de credenciales ya expuestas forma parte de este ticket.

## Estado por repositorio (historial de tratamiento)

Una fila por acción aplicada a cada repositorio; se agregan filas a medida que avanza el tratamiento.

| Fecha | Repositorio | Subtarea | Acción | Estado |
|---|---|---|---|---|
| 2026-09-30 | platforms-service | GITIN-2130 | Relevamiento de campos de credenciales en `config/env/*.js` (solo nombres de campo, valores redactados) | ✅ Realizado |
| 2026-09-30 | concentrador-service | GITIN-2131 | Relevamiento de campos de credenciales en `config/env/*.js` (solo nombres de campo, valores redactados) | ✅ Realizado |
| — | platforms-service | GITIN-2130 | Verificar qué literales están versionados en `develop` y cuáles son secretos reales | ⚠️ Pendiente |
| — | concentrador-service | GITIN-2131 | Verificar qué literales están versionados en `develop` y cuáles son secretos reales | ⚠️ Pendiente |
| — | platforms-service | GITIN-2130 | Migrar credenciales a variables de entorno (local) | ⚠️ Pendiente |
| — | concentrador-service | GITIN-2131 | Migrar credenciales a variables de entorno (local) | ⚠️ Pendiente |
| — | backOffice | — | Sin revisar en este ticket | ⚠️ Pendiente |

## Hallazgos

| # | Hallazgo | Riesgo |
|---|---|---|
| H1 | Ambos servicios definen campos de credenciales como literales en `config/env/*.js` en todos los ambientes, incluido `production.js`. | Alto |
| H2 | En platforms-service, `tokenEncryption.key`/`iv` ya leen de `process.env`, pero con un literal como valor por defecto. | Medio |
| H3 | Un escaneo Trivy de la imagen local de platforms-service detectó una clave de acceso AWS en `staging.js`. Es un cambio local sin commitear: no está en `origin/ope` (verificado el 2026-09-29). | Medio |

Evidencia: relevamiento de nombres de campo con valores redactados, persistido en `data/env_credential_fields_redacted_20260930.txt`.

## Acciones propuestas

1. (SRE) Determinar qué literales son secretos reales y cuáles están versionados en `develop` en cada repositorio.
2. (Dev) Reemplazar los literales de `config/env/*.js` por lectura desde variables de entorno, sin valores por defecto sensibles.
3. (Dev) Documentar la configuración local (`.env.example`, `.gitignore`).
4. (SRE) Coordinar con GITIN-1715 la provisión de las mismas credenciales en los ambientes desplegados, ya que al quitar los literales el servicio dejará de arrancar allí sin otra fuente.
5. (SRE) Agregar una verificación automática de secretos en el pipeline (Trivy ya detecta secretos en la imagen).
6. (SRE) Evaluar la rotación de las credenciales que resulten haber estado versionadas.

## Criterios de aceptación

- No hay credenciales en `config/env/*.js` ni en la imagen Docker (verificable con Trivy).
- Un desarrollador puede levantar cada servicio en local usando solo variables de entorno.
- La tabla "Estado por repositorio" refleja el tratamiento aplicado en cada repositorio.
