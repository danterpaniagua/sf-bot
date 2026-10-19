# Eventos — 20261007_gitin1715-keyvault-aws-ohio-stg

## 2026-10-07 16:37 — Identidad de AWS, init y validate del Terraform

**Comando:** C1 — Identidad de AWS; C2 — `terraform init` y `validate` (`scripts.sh`)
**Resultado:**
Cuenta `382381053403`, usuario IAM. `terraform init` correcto y `validate` con `Success! The configuration is valid.` Salidas en `data/aws-caller-identity.txt`, `data/tf-init.txt` y `data/tf-validate.txt`.

He confirmado la cuenta y que la configuración inicial del módulo de secretos en `us-east-2` es válida.

## 2026-10-07 17:00 — Intento de carga de valores en los secretos

**Comando:** Carga de secretos de staging (script de carga, `APPLY=1`)
**Resultado:**
Todas las llamadas `PutSecretValue` fallaron con `UnrecognizedClientException` (el token de seguridad no es válido). Salida en `data/loader-apply.txt`.

He comprobado que no se escribió ningún valor y que el fallo es de credenciales de la CLI, no del módulo.

## 2026-10-07 17:07 — Primer plan del módulo

**Comando:** C3 — `terraform plan` (`scripts.sh`)
**Resultado:**
`Plan: 22 to add, 0 to change, 0 to destroy.` y `validate` correcto tras ajustar el módulo. Salidas en `data/tf-plan.txt` y `data/tf-validate-3.txt`.

## 2026-10-07 17:09 — Aplicación inicial del módulo

**Comando:** C4 — `terraform apply` (`scripts.sh`) ⚠️
**Resultado:**
No he guardado la salida de esta aplicación. El `terraform.tfstate` local se escribió a las 17:09 y la consola de Secrets Manager muestra secretos creados a las 17:09:15 (hora local), todos sin recuperaciones (`Last retrieved` en blanco).

He aplicado la configuración con 19 secretos de los dos servicios, una política de lectura y la clave KMS. He vuelto a revisar ese estado al día siguiente, al estrechar el alcance a Platform.

## 2026-10-08 10:22 — Lista de secretos de la consola

La consola mostró 10 filas (lista parcial) con nombres de la primera distribución: `platforms-service/{cloud,mercadopago,token,database}` y seis de `concentrador-service`. He guardado la lista, sin valores, en `data/secretsmanager-console-list.txt`.

## 2026-10-08 10:25 — Estado y plan tras estrechar el alcance a Platform

**Comando:** `terraform state list` y `terraform plan` (`data/tf-state-list.txt`, `data/tf-plan-2.txt`)
**Resultado:**
El state tenía la clave KMS, el alias, la política y 19 secretos (11 de Concentrador y 8 de Platform). El plan dio `10 to add, 0 to change, 20 to destroy`: destruía los 19 secretos y la política, y creaba 9 secretos con claves cortas y la política nueva.

He detectado que 7 secretos de Platform conservaban el mismo nombre completo con otra clave de `for_each`; con un periodo de recuperación de 7 días, destruir y crear el mismo nombre en un solo apply habría fallado.

## 2026-10-08 10:27 — Movimiento de 7 recursos en el state

**Comando:** `terraform state mv` ×7 (`data/tf-state-mv.txt`) ⚠️
**Resultado:**
Siete `Successfully moved 1 object(s).` (`cloud`, `database`, `mercadopago`, `peya`, `sendgrid`, `sml` y `token-encryption`).

He movido en el state local las 7 direcciones a las claves nuevas, sin tocar AWS.

## 2026-10-08 10:28 — Plan tras mover el state

**Comando:** `terraform plan` (`data/tf-plan-3.txt`)
**Resultado:**
`Plan: 3 to add, 7 to change, 13 to destroy.` Los 7 cambios son solo de descripción; los 13 destruidos son los 11 secretos de Concentrador, `platforms-service/token` y la política antigua.

## 2026-10-08 10:43 — Aplicación del plan estrechado

**Comando:** `terraform apply` (`data/tf-apply.txt`, `data/tf-apply-2.txt`) ⚠️
**Resultado:**
El primer intento quedó en `Apply cancelled.` porque la redirección ocultó el prompt de confirmación. El segundo, con `-auto-approve`, terminó con `Apply complete! Resources: 3 added, 7 changed, 13 destroyed.` Quedaron 9 secretos de Platform, la política recreada y la clave KMS sin cambios.

He aplicado el alcance de solo Platform. Los 12 secretos eliminados pasaron a la ventana de recuperación de 7 días y siguen vacíos.

## 2026-10-08 11:13 — Refactor por ambiente y plan de tst

**Comando:** `terraform show` del plan guardado (`data/tf-plan-4.txt`)
**Resultado:**
`Plan: 8 to add, 0 to change, 0 to destroy`, con 14 objetos de stg solo reasignados de dirección (`moved.tf`) y 8 recursos nuevos de tst (clave KMS, alias, política y 5 secretos).

He separado los archivos por ambiente con el esquema `<ambiente>_NN_nombre.tf` y he verificado que stg no cambia.

## 2026-10-08 11:15 — Aplicación del ambiente tst

**Comando:** `terraform apply tfplan.plan` (`data/tf-apply-3.txt`) ⚠️
**Resultado:**
`Apply complete! Resources: 8 added, 0 changed, 0 destroyed.` Salidas de stg sin cambios.

He creado la clave KMS `bf198ffc-...`, el alias `alias/smartpedidos-tst-secrets`, la política `smartpedidos-tst-secrets-read` y 5 secretos vacíos bajo `smartpedidos/tst/platforms-service/`.

## 2026-10-08 12:12 — Carga de valores de tst

**Comando:** Carga de secretos de tst (`scripts/load_secrets.sh`, dry run y `APPLY=1`; `data/tst-loader-dry-run.txt`, `data/tst-loader-apply.txt`) ⚠️
**Resultado:**
`OK` para `database`; `SKIP` para `token-signing`, `static-token`, `peya` y `sml`, porque comparten valor con otro ambiente.

He cargado la credencial de base de datos de tst y no he copiado las otras cuatro, cuyo valor es igual al de producción o staging. Siguen vacías.
