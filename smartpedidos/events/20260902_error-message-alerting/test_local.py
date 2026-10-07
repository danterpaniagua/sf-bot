"""
GITIN-1979 - local validation of format_message() against both message shapes this
bridge needs to handle, without calling the real Google Chat webhooks (no real URLs
exist yet). Run: python3 test_local.py
"""
import os

os.environ.setdefault(
    "GOOGLE_CHAT_WEBHOOK_URLS",
    "https://example.invalid/operations-placeholder,https://example.invalid/smartpedidos-placeholder",
)

from handler import format_message, GOOGLE_CHAT_WEBHOOK_URLS  # noqa: E402

CLOUDWATCH_ALARM_SNS_RECORD = {
    "Sns": {
        "Subject": "ALARM: \"grido-redacted-etl-errors\" in US East (N. Virginia)",
        "Message": (
            '{"AlarmName":"grido-redacted-etl-errors",'
            '"NewStateValue":"ALARM",'
            '"NewStateReason":"Threshold Crossed: 1 datapoint [1.0] was greater than'
            ' or equal to the threshold (1.0).",'
            '"StateChangeTime":"2026-09-03T04:05:00.000+0000"}'
        ),
        "Timestamp": "2026-09-03T04:05:00.123Z",
    }
}

ECS_PLAIN_TEXT_SNS_RECORD = {
    "Sns": {
        "Subject": None,
        "Message": (
            "A las 2026-09-03T03:31:00Z se ha detectado un cambio "
            "(ECS Service Action) en el cluster "
            "arn:aws:ecs:us-east-1:382381053403:cluster/smartfran-pedidos-production"
        ),
        "Timestamp": "2026-09-03T03:31:00.456Z",
    }
}

print(f"=== Parsed {len(GOOGLE_CHAT_WEBHOOK_URLS)} webhook URL(s) from GOOGLE_CHAT_WEBHOOK_URLS ===")
for url in GOOGLE_CHAT_WEBHOOK_URLS:
    print(f"  {url}")
print()
print("=== CloudWatch Alarm shape ===")
print(format_message(CLOUDWATCH_ALARM_SNS_RECORD))
print()
print("=== Plain-text (ECS-style) shape ===")
print(format_message(ECS_PLAIN_TEXT_SNS_RECORD))
