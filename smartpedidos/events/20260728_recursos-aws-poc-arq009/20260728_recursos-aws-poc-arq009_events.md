# Eventos — 20260728_recursos-aws-poc-arq009

## 2026-07-28 — Apertura: registro de infraestructura real creada durante el PoC ARQ-009

**Autor:** Dante Paniagua

Se abrió este ticket para registrar y trackear la limpieza de los recursos AWS reales creados en la cuenta `382381053403` (región `us-west-2`) durante la construcción del PoC de ARQ-009, documentado en [20260720_ocultar-account-id-sqs-urls](../20260720_ocultar-account-id-sqs-urls/20260720_ocultar-account-id-sqs-urls.md).

**Recursos registrados:** 2 colas SQS FIFO (`poc-arq009-branchA.fifo`, `poc-arq009-branchB.fifo`), 2 roles IAM (`poc-arq009-apigw-sqs-role`, `apigateway-cloudwatch-logs-poc`), 2 REST API de API Gateway (`o0o4lrn2hg` funcional, `5t5c2si3s3` duplicado vacío pendiente de borrado), y un cambio de configuración a nivel de cuenta (`cloudwatchRoleArn`). Detalle completo con IDs, ARNs y timestamps en `investigation.md`.

**Estado:** ningún recurso fue dado de baja todavía. Sub-tareas de limpieza (INFRA-001 a INFRA-004) creadas, todas pendientes.

**Archivo principal:** `20260728_recursos-aws-poc-arq009.md`

---

## 2026-07-28 — INFRA-001: borrado del REST API duplicado vacío

**Autor:** Dante Paniagua

**Comando ejecutado:**
```bash
aws apigateway delete-rest-api --rest-api-id 5t5c2si3s3 --region us-west-2
```

Se confirmó por el usuario: borrado exitoso. Sin impacto — el API era un duplicado vacío (sin método adjunto), creado por un doble-`create-rest-api` accidental durante la sesión de PoC. El REST API funcional (`o0o4lrn2hg`) no se vio afectado.

Se marcó INFRA-001 como resuelto en la tabla de sub-tareas y en la tabla de recursos del ticket.

---

## 2026-07-28 — Nuevos recursos: authorizer Lambda para ARQ-002

**Autor:** Dante Paniagua

Se agregaron a este registro los recursos creados para implementar y validar el Lambda TOKEN authorizer de ARQ-002 (detalle funcional en [20260720_ocultar-account-id-sqs-urls_events.md#2026-07-28-3](../20260720_ocultar-account-id-sqs-urls/20260720_ocultar-account-id-sqs-urls_events.md#2026-07-28-3)): secreto `poc-arq009/jwt-secret` (contiene el `token.secret` real de producción, por decisión explícita del usuario), rol IAM `poc-arq009-authorizer-lambda-role`, función Lambda `poc-arq009-jwt-authorizer`, y authorizer `1arn20` sobre el REST API existente.

Se agregó INFRA-005 (borrado del secreto con `--force-delete-without-recovery`, no la baja por defecto que deja recuperación de 7-30 días) como sub-tarea de máxima prioridad, independiente de si el resto del PoC se mantiene vivo.
