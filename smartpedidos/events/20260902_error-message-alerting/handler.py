"""
GITIN-1979 - SNS -> Google Chat bridge, broadcasting to more than one team's space.

Subscribed to an SNS topic that receives failure notifications (CloudWatch Alarm
state-change messages for grido-redacted-etl / mongo-to-s3-CFN-ScheduledMongoToS3-
1EZXBGD94CJVO, plus whatever else is already on that topic - see investigation.md
for which topic: SNS-SmartPedidosTeam-PROD, confirmed 2026-09-03). Reformats each
SNS message into Google Chat's webhook payload shape and posts the SAME message to
every configured webhook - more than one team needs to see these, not just one
space. Uses only the stdlib (urllib) - no extra dependency layer needed, same
approach as grido-redacted-etl's handler.py using only boto3/botocore.

Delivery is best-effort per webhook: a failure posting to one team's space doesn't
block delivery to the others, but if ANY webhook failed, the function still raises
at the end (after attempting all of them) so the failure is visible in this
function's own CloudWatch metrics/logs - not silently swallowed. A retry after a
partial failure will re-post to webhooks that already succeeded too (no
idempotency built in) - an accepted tradeoff for a low-volume alerting path.

Env vars:
  GOOGLE_CHAT_WEBHOOK_URLS   required - comma-separated list of Google Chat
                              incoming webhook URLs, one per team/space. Each is a
                              secret (carries an embedded token) - set only as a
                              Lambda environment variable, never hardcoded here or
                              written into any file in this repo.
"""

import json
import os
import urllib.error
import urllib.request

GOOGLE_CHAT_WEBHOOK_URLS = [
    url.strip() for url in os.environ["GOOGLE_CHAT_WEBHOOK_URLS"].split(",") if url.strip()
]


def format_message(sns_record):
    sns = sns_record["Sns"]
    subject = sns.get("Subject") or "Alerta"
    message = sns.get("Message", "")
    timestamp = sns.get("Timestamp", "")

    # CloudWatch Alarm notifications arrive as a JSON string in Message; other
    # sources already on this topic (e.g. the existing ECS InputTransformer) send
    # plain text instead - handle both explicitly rather than assuming one shape
    # holds for every message on the topic.
    try:
        parsed = json.loads(message)
    except (json.JSONDecodeError, TypeError):
        parsed = None

    if isinstance(parsed, dict) and "AlarmName" in parsed:
        alarm_name = parsed.get("AlarmName", "?")
        new_state = parsed.get("NewStateValue", "?")
        reason = parsed.get("NewStateReason", "")
        text = (
            f"*{subject}*\n"
            f"Alarma: `{alarm_name}`\n"
            f"Estado: *{new_state}*\n"
            f"Motivo: {reason}\n"
            f"Hora: {timestamp}"
        )
    else:
        text = f"*{subject}*\n{message}"

    return text


def post_to_google_chat(text, webhook_url):
    payload = json.dumps({"text": text}).encode("utf-8")
    req = urllib.request.Request(
        webhook_url,
        data=payload,
        headers={"Content-Type": "application/json; charset=UTF-8"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=10) as res:
        return res.status


def handle(event, context=None):
    results = []
    failures = []
    for record in event.get("Records", []):
        text = format_message(record)
        for webhook_url in GOOGLE_CHAT_WEBHOOK_URLS:
            try:
                status = post_to_google_chat(text, webhook_url)
                results.append({"status": status})
            except urllib.error.HTTPError as err:
                print(f"Google Chat webhook returned {err.code}: {err.read().decode('utf-8', 'ignore')}")
                failures.append(str(err))
            except urllib.error.URLError as err:
                print(f"Failed to reach Google Chat webhook: {err.reason}")
                failures.append(str(err))

    if failures:
        raise RuntimeError(
            f"{len(failures)}/{len(results) + len(failures)} webhook posts failed: {failures}"
        )
    return {"processed": len(results)}
