# Investigation — 20260902_error-message-alerting

**Jira:** [GITIN-1979](https://smartit-ar.atlassian.net/browse/GITIN-1979), subtask of GITIN-1872 (parent, "[SP] Envío de datos de SP a Grido"). Title: "[SP] Envío de mensaje de error" — confirmed 2026-09-02 as the actual ticket for this work, which started as an ad-hoc request inside GITIN-1874's session before its Jira identity was known (this folder didn't exist until the URL was confirmed; earlier research happened without a local home — reconstructed here from conversation, not re-derived).

**Status: in progress — researching existing alerting infrastructure before building anything new.**

## Scope (as understood so far)

Add failure notification for the GITIN-1872 data pipeline — specifically raised in the context of two Lambda functions:
- `grido-redacted-etl` (GITIN-1874) — reads `-3` files, filters/redacts, writes to `smartpedidos-orders`.
- `mongo-to-s3-CFN-ScheduledMongoToS3-1EZXBGD94CJVO` (GITIN-1970) — the upstream source Lambda `grido-redacted-etl` depends on.

Not yet confirmed whether GITIN-1979's actual Jira scope is limited to just these two functions, or is broader (the whole GITIN-1872 pipeline, or something else entirely) — the ticket itself hasn't been read yet, only inferred from the conversation that raised it.

## Existing alerting infrastructure found (2026-09-02)

**This account already has ECS-event alerting wired up** — found via `aws events list-rules --query "Rules[?EventPattern!=null]"` (`data/eventbridge_rules_all.json` — copied over from where it was first pulled, `20260901_grido-redacted-etl-lambda/data/`). Two categories of rules exist:

- **Custom, purpose-built rules** (not third-party), all targeting `smartfran-pedidos-production`:
  - `ECS-ServiceAction-Team` — "Rule que avisa en cambios del Service" (ECS Service Action events)
  - `ECS-Task-ECSTaskStateChange-Team` — "Alerta EventBridge ECS Task State Change"
  - `ECS-ContainerInstanceStateChange-Team` — "Rule que informa los estados de los contenedores"
  - `ECS-Task-ECSDeploymentStateChange` — "Regla que envia mensajes cuando se hace un deploy en PROD"
  - `ECS-Task-Definition-Version-Created` — new task definition versions in prod
  - `ECR-Registry-Events-Alert` — ECR image push/action alerts
- **`MontyCloud-*` rules** — a large set (8 rules) belonging to a third-party cloud-management SaaS (MontyCloud), not built in-house — unrelated to this ticket's scope, not investigated further.

**All six rules' targets pulled directly (2026-09-02/03) — two different SNS topics, not one, corrected after initially only checking one rule and assuming the rest matched by naming convention alone (exactly the mistake `feedback_convergent_evidence_shared_assumption` warns about):**

| Topic | Rules targeting it |
|---|---|
| `arn:aws:sns:us-east-1:382381053403:Alertas-EventBridge-PROD` | `ECS-ServiceAction-Team`, `ECS-Task-Definition-Version-Created`, `ECR-Registry-Events-Alert` |
| `arn:aws:sns:us-east-1:382381053403:SNS-SmartPedidosTeam-PROD` | `ECS-Task-ECSTaskStateChange-Team`, `ECS-ContainerInstanceStateChange-Team`, `ECS-Task-ECSDeploymentStateChange` |

Both invoked via the same role, `arn:aws:iam::382381053403:role/service-role/Amazon_EventBridge_Invoke_Alerts_Prod`, each with its own `InputTransformer` producing a readable Spanish message (`data/eventbridge_targets_all_rules.txt`). `SNS-SmartPedidosTeam-PROD` — named specifically for this team, not a generic account-wide alert bucket — carries the task-state/container-resource/deployment alerts, closer in nature to a Lambda failure notification than `Alertas-EventBridge-PROD`'s mix (task-def versioning, ECR pushes).

**Subscriptions confirmed (2026-09-03), settles which topic to reuse:**

| Topic | Subscribers (all `email` protocol) |
|---|---|
| `Alertas-EventBridge-PROD` | `dantep@smartfran.com` only |
| `SNS-SmartPedidosTeam-PROD` | `smartpedidos@smartfran.com` (team distribution list) **+** `dantep@smartfran.com` |

**Decision: reuse `SNS-SmartPedidosTeam-PROD`** — reaches the whole team, not one individual, appropriate for a production pipeline failure. Both the new CloudWatch Alarms and the Google Chat bridge Lambda's SNS subscription will target this topic.

**Important scope mismatch, not yet resolved:** these existing rules fire on **ECS cluster events** (concentrador-service/platforms-service on `smartfran-pedidos-production`) — they would not catch a failure in `grido-redacted-etl` or `mongo-to-s3-CFN-ScheduledMongoToS3-1EZXBGD94CJVO`, since those are **Lambda functions, not ECS services**. Lambda failures need a different trigger mechanism (most likely a CloudWatch Alarm on each function's `Errors` metric), but the existing `Alertas-EventBridge-PROD` SNS topic could still be reused as the *destination* for those alarms, rather than building a separate topic — assuming its existing subscriptions (email, presumably) are appropriate for this too.

**Not yet confirmed:** what's actually subscribed to `Alertas-EventBridge-PROD` (`aws sns list-subscriptions-by-topic` was requested but not yet returned as of this entry).

## Proposed approach (not yet built, pending the subscription check above)

1. Confirm `Alertas-EventBridge-PROD`'s existing subscriptions.
2. Create a CloudWatch Alarm on each Lambda's `Errors` metric (`grido-redacted-etl`, `mongo-to-s3-CFN-ScheduledMongoToS3-1EZXBGD94CJVO`), alarm action = publish to `Alertas-EventBridge-PROD` (reusing the existing topic) rather than a new one, unless the existing subscriptions turn out to be unsuitable.
3. **Google Chat notification also requested** (2026-09-02) — SNS has no native Google Chat integration. Needs a small bridge Lambda subscribed to the SNS topic that reformats the message and POSTs to a Google Chat incoming-webhook URL. The webhook URL will be stored as a Lambda environment variable (confirmed by the user) — never hardcoded, never written into this repo as a literal value, referenced by name/purpose only, same as any other credential (per root `CLAUDE.md`).

## Google Chat bridge Lambda built and locally validated (2026-09-03)

**Language: Python**, confirmed by the user (matches `grido-redacted-etl`, unlike the Node.js `mongo-to-s3` source Lambda). `handler.py` — subscribes to `SNS-SmartPedidosTeam-PROD` (see topic decision above), reads `GOOGLE_CHAT_WEBHOOK_URLS` from an env var (never hardcoded, never written into this repo as a literal value — the user confirmed the URL(s) will be set as a Lambda env var), and posts a formatted message to Google Chat's webhook using only the stdlib (`urllib`) — no extra dependency layer needed, same approach as `grido-redacted-etl`'s `handler.py` (only `boto3`/`botocore`, both runtime-provided).

**Broadcasts to more than one team, not just one space** (confirmed by the user, 2026-09-03): **Operations and SmartPedidos** both need to see these alerts. `GOOGLE_CHAT_WEBHOOK_URLS` is a comma-separated list, parsed into individual webhook URLs at import time; `handle()` posts the same formatted message to every configured URL. Delivery is best-effort per webhook — a failure posting to one team's space doesn't block delivery to the others, but if any webhook failed, the function still raises at the end (after attempting all of them) so the failure is visible in this function's own CloudWatch metrics/logs rather than silently swallowed. A retry after a partial failure will re-post to webhooks that already succeeded too — no idempotency built in, an accepted tradeoff for a low-volume alerting path.

**Handles two message shapes on the same topic, not just one** — deliberately, given this session's `feedback_convergent_evidence_shared_assumption` lesson (don't assume one format holds for everything on a shared resource): a CloudWatch Alarm notification (JSON in `Sns.Message`, has `AlarmName`) gets parsed into a structured Spanish message (`Alarma`/`Estado`/`Motivo`/`Hora`); anything else (e.g. the existing ECS `InputTransformer` plain-text messages, if this ends up on the same topic as those) falls back to `Subject` + raw `Message` instead of crashing on a JSON-parse failure.

**Validated locally** (`test_local.py`, `data/handler_local_validation.txt`) against two synthetic SNS records matching each shape — both format correctly, no real webhook call made yet (no URL exists to test against).

## CloudWatch Alarms created and confirmed (2026-09-03)

Two alarms, both on the `AWS/Lambda` `Errors` metric, `Sum` statistic, period 300s, threshold ≥1, `TreatMissingData: notBreaching` (these functions don't run continuously — no data most of the day is normal, not a failure), both publishing to `SNS-SmartPedidosTeam-PROD`:

- `grido-redacted-etl-errors` → `grido-redacted-etl` (GITIN-1874)
- `mongo-to-s3-scheduled-errors` → `mongo-to-s3-CFN-ScheduledMongoToS3-1EZXBGD94CJVO` (GITIN-1970)

Confirmed via `describe-alarms` (`data/cloudwatch_alarms_confirm.json`): both `ActionsEnabled: true`, `StateValue: OK`, correctly wired to the SNS topic. Cross-referenced in GITIN-1970's own `ops-events.md`, since the second alarm is a real operational change to that function even though the work itself is tracked here.

## Webhook URLs (2026-09-03) — received, not recorded by value

- **Operations (`NOTIFY_OPERATIONS`)** — received from the user. Not written here or anywhere else in this repo by value, per root `CLAUDE.md`'s secret-handling rule (it carries an embedded `key` and `token`). Will be set directly as part of the deployed function's `GOOGLE_CHAT_WEBHOOK_URLS` env var when we deploy; the user pastes the real value into that step themselves.
- **SmartPedidos (`NOTIFY_SMARTPEDIDOS`)** — received from the user. Same handling — not recorded by value anywhere in this repo.

Both webhook URLs are now in hand. Proceeding to deployment.

**Security review before deploying, requested by the user (2026-09-03):** confirmed no inbound exposure (no Function URL/API Gateway), the SNS invoke permission will be scoped to the specific `SNS-SmartPedidosTeam-PROD` topic ARN (not account-wide), and the execution role has zero AWS resource access beyond writing its own CloudWatch logs. One accepted tradeoff, not a gap: the webhook URLs sit as plaintext-visible Lambda env vars (same pattern already used for `MONGO_USER`/`MONGO_PASSWD` on the source Lambda) — anyone with `lambda:GetFunctionConfiguration` on this function can read them. **Decision: plain env vars for now**, not SSM Parameter Store `SecureString` — the user explicitly chose to keep this simple/consistent with the existing account pattern rather than add the extra IAM/fetch-code complexity.

## Bridge Lambda deployed and end-to-end tested (2026-09-03)

Deployed `sp-pipeline-alerts-chat-bridge` (role `sp-pipeline-alerts-chat-bridge-role`, `python3.12`, `Timeout=30`, `MemorySize=128`). Real webhook URLs set as `GOOGLE_CHAT_WEBHOOK_URLS` (comma-separated, Operations + SmartPedidos) via a JSON file created **outside the repo** (`~/tmp-sp-alerts/environment.json`) specifically to avoid ever writing the real secret values into a git-tracked file — deleted after use. Spanish `Description` added to both this function and `grido-redacted-etl`.

**One real deployment mistake caught and fixed:** the first `create-function` call actually used the JSON file while it still had literal placeholder text (`PASTE_..._URL_HERE`) — the user's "yes edited it" didn't match what was actually deployed. Caught by checking the deployed function's own `Environment.Variables` after creation, not by trusting the report that it was done. Fixed via `update-function-configuration` with the real values.

**Tested via direct invoke** with a synthetic SNS-shaped test payload (plain-text fallback path, explicitly labeled "TEST" in the message so it wouldn't be mistaken for a real alarm) — `StatusCode: 200`, clean CloudWatch log with no exception traceback (`data/lambda_test_invoke_log_tail.txt`), and **confirmed directly by the user: the test message appeared in both the Operations and SmartPedidos Google Chat spaces.**

**Wired to the SNS topic and confirmed (2026-09-03):** `add-permission` granted `sns.amazonaws.com` invoke rights on this function, scoped via `ArnLike` condition to `SNS-SmartPedidosTeam-PROD`'s ARN specifically (`data/lambda_add_permission_sns.json`). `sns subscribe` with `--protocol lambda` added this function as a subscriber (auto-confirmed, real `SubscriptionArn` returned immediately — Lambda subscriptions don't need the email-link confirmation step). Confirmed via `list-subscriptions-by-topic`: the topic now has 3 subscriptions — the pre-existing `smartpedidos@smartfran.com` and `dantep@smartfran.com` emails, plus this Lambda (`data/sns_subscriptions_smartpedidosteam_prod_final.json`).

**Full production path confirmed end-to-end (2026-09-03).** Direct-invoke testing had already confirmed the Lambda's own logic works; the remaining gap was whether a real CloudWatch Alarm state transition actually reaches Google Chat through the full path (Alarm → SNS → Lambda subscription invoke), not just a synthetic direct invoke. Forced `grido-redacted-etl-errors` into `ALARM` via `aws cloudwatch set-alarm-state` (`data/cloudwatch_set_alarm_state_test.json`) — **confirmed by the user: the test alert arrived in both Google Chat spaces (Operations, SmartPedidos) and both team emails** (`smartpedidos@smartfran.com`, `dantep@smartfran.com`). Reset back to `OK` immediately after (`data/cloudwatch_set_alarm_state_reset.json`, confirmed via `describe-alarms`: `data/cloudwatch_alarm_state_check.json`).

**This closes out the core GITIN-1979 deliverable for the two pipeline Lambdas** (`grido-redacted-etl`, `mongo-to-s3-CFN-ScheduledMongoToS3-1EZXBGD94CJVO`): a failure in either now reaches Operations and SmartPedidos via Google Chat, in addition to the existing team email subscribers.

## Google Chat leg deactivated (2026-09-03) — too verbose

The user found the Google Chat notifications too verbose and asked to deactivate them, keeping email only. Unsubscribed `sp-pipeline-alerts-chat-bridge` from `SNS-SmartPedidosTeam-PROD` (`aws sns unsubscribe` on its subscription ARN) — chosen over deleting the function/role, since it's fully reversible (re-subscribe later if the formatting is made less verbose) without losing any of the built infrastructure. Confirmed via `list-subscriptions-by-topic`: back down to exactly the two pre-existing email subscriptions (`smartpedidos@smartfran.com`, `dantep@smartfran.com`). The two `CloudWatch Alarm`s are untouched and continue publishing to the topic — only the Chat leg stopped. The bridge Lambda, its IAM role, and its code remain deployed but idle (unreachable — nothing publishes to it directly, and it's no longer subscribed to the topic).

## Open questions / next steps

1. Read GITIN-1979's actual Jira ticket body/comments — scope has only been inferred from conversation so far, not confirmed against the ticket itself.
2. ~~Get subscription lists, decide which topic to reuse~~ — **done**: `SNS-SmartPedidosTeam-PROD` chosen (team DL + individual, vs. `Alertas-EventBridge-PROD`'s single individual subscriber).
3. ~~Build the two CloudWatch Alarms~~ — **done and confirmed**, see above.
4. Deploy the Google Chat bridge Lambda (IAM role, `create-function`, SNS subscription to `SNS-SmartPedidosTeam-PROD`) — code built and locally validated, not yet deployed. Needs the real webhook URL from the user first (to set as the deployed function's env var — never to be pasted into chat).
5. Confirm whether GITIN-1979's actual scope is just these two pipeline Lambdas, or broader — still only inferred from conversation.
6. No `ops.md`/`ops-events.md` created yet for this ticket — real infra changes have already happened (SNS/EventBridge lookups, two CloudWatch Alarms created); worth formalizing into the standard ticket format once the Google Chat bridge is also deployed, rather than piecemeal.
