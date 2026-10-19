# GITIN-1606 — parent ticket (title not seen)

- Jira: https://smartit-ar.atlassian.net/browse/GITIN-1606
- Opened (this folder): 2026-10-07. The folder name says "secretos-aws-por-ambiente" because I first scoped this ticket as a secrets ticket; that was wrong and is corrected here. Folder names are fixed at creation, so it keeps its name.
- The title of GITIN-1606 itself was not available. The phrase "Investigar como ofuscar / ocultar el ID de las colas" that the user pasted first is the title of its subtask GITIN-1607.
- Status: 50% complete according to Jira (user paste, 2026-10-07). Scope below is a proposal for `ops.md`, not agreed with the user.

## Subtasks (user paste, 2026-10-07; all assigned to the user)

| Key | Title | Priority | Status |
|---|---|---|---|
| GITIN-1607 | [SP] Investigar como ofuscar / ocultar el ID de las colas | High | Finalizada |
| GITIN-1701 | [SP] Creacion de Infra de prueba | Medium | Finalizada |
| GITIN-1703 | [SP] Nuevo analisis de costos | Medium | Finalizada |
| GITIN-1715 | [SP] Platform: Implementacion de KeyVault | Medium | En curso |
| GITIN-2198 | [SP] Concentrador: Implementacion de KeyVault | Medium | Backlog |
| GITIN-2169 | [SP] Credenciales por DEV | not shown | status not shown (paste was cut) |

- GITIN-2129 / 2130 / 2131 (credentials in code) are not in this list, although the 2129 notes call 1606 their parent; that link looks wrong or lives elsewhere (not verified).
- There is no subtask for building the real entry point (API Gateway) described below; the earlier ARQ sub-tasks were tracked inside the July event, not as Jira subtasks of 1606.

## Linked issue (user paste, 2026-10-07)

- "Actividades vinculadas — está relacionado con": **GITSFP-1664**, issue type Historia (Story), status "Inicio", priority Medium. Its title is not in the paste: the word "Agentes" follows it and may be its title or the next Jira section. GITSFP-1664 is on a different Jira board, the SmartPedidos board (user, 2026-10-07), not the GITIN board that holds 1606 and its subtasks; branches such as `GITSFP-1706` in the Backoffice repo come from that same board. It may be the POS-agent side of this work (ARQ-003: the agent moving from direct SQS to the new entry point), but that is an inference from the word "Agentes" and the ticket's content, not something the paste says.

## What the finished subtasks established (from `20260720_ocultar-account-id-sqs-urls/` and related July events)

- The POS agents receive SQS queue URLs containing the AWS account ID, and the `login` response of Concentrador (`POST /branches/login`) hands out static AWS keys (`aws_id`/`aws_secret`) that are the same for every branch.
- Chosen design, proven in a proof of concept (ARQ-009, 2026-07-28, `us-west-2`, disposable queues): API Gateway REST API (v1) with native SQS integration, custom domain (`colas.smartpedidos.com`), one parametrized resource `/{branchId}`, and a Lambda TOKEN authorizer validating the existing branch JWT (HS256 with `token.secret`) with mandatory `user.branchId` = path parameter binding. The agent can then drop its embedded AWS keys. The ARQ-010 cost analysis became its own ticket (GITIN-1703).
- Cost at the real volume (June 2026: 147.76 million SQS FIFO requests, US$73.49 per month today): REST-only about US$517 per month, HTTP API plus a light Lambda about US$180, CloudFront plus REST about US$665; no variant is cheaper than direct SQS.
- Remaining design/decision items recorded in the July ticket doc: ARQ-001 (document the design), ARQ-003 (agent-side migration effort; POS agent repo is outside this monorepo), ARQ-004 (Route 53 ALIAS vs CNAME), ARQ-005 (relation with SEC-006), ARQ-006 (dedicated custom domain), ARQ-008 (REST-only vs HTTP API plus Lambda).
- The authorizer needs its signing secret from Secrets Manager or SSM (not a literal), which is why the vault tickets are subtasks here. The PoC secret `poc-arq009/jwt-secret` (`us-west-2`) still holds the real production signing key (INFRA-005, teardown pending).

## Open items

- The title and description of GITIN-1606 (user to paste), the status of GITIN-2169, and the title and content of GITSFP-1664 to confirm whether it is the POS-agent work.
- Whether a subtask for building the entry point should exist, since none is listed.
- The ARQ-008, ARQ-004, ARQ-006 and ARQ-003 decisions above.
