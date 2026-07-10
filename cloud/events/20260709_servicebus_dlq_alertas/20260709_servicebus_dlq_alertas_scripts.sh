#!/bin/bash
# Evento: 20260709_servicebus_dlq_alertas
# Service Bus: SmartFran-Cloud-ServiceBus-Grido-PRO
# Suscripción: SmartIT Cloud (85c76dea-3304-4310-8656-bf21b28e4f4b)

# === INVESTIGATION ===

# CX-01 — Alert rules existentes sobre el Service Bus
az monitor alert list \
  --subscription 85c76dea-3304-4310-8656-bf21b28e4f4b \
  --resource-group SmartFran.Cloud.PRO.GRIDO \
  --output json \
  --query "[?contains(scopes[0], 'SmartFran-Cloud-ServiceBus-Grido-PRO')].{name:name, condition:condition.allOf[0].metricName, severity:severity, enabled:enabled}"

# CX-02 — Action groups en el RG
az monitor action-group list \
  --subscription 85c76dea-3304-4310-8656-bf21b28e4f4b \
  --resource-group SmartFran.Cloud.PRO.GRIDO \
  --output json \
  --query "[].{name:name, emails:emailReceivers[].emailAddress}"

# CX-03 — Colas y DLQ count actual
az servicebus queue list \
  --subscription 85c76dea-3304-4310-8656-bf21b28e4f4b \
  --resource-group SmartFran.Cloud.PRO.GRIDO \
  --namespace-name SmartFran-Cloud-ServiceBus-Grido-PRO \
  --output json \
  --query "[].{name:name, dlqCount:countDetails.deadLetterMessageCount}"
