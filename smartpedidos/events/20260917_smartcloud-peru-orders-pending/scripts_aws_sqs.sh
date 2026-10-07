#!/usr/bin/env bash
# Event: 20260917_smartcloud-peru-orders-pending (GITIN-2068)
# Read-only AWS SQS checks. Queue naming: concentrador-service config
# CREATE_NAME template is "##_PRD_PlatformMessages.fifo" — the "##_"
# placeholder (including the underscore) is fully replaced by branchId via
# .replace('##_', branchId), so branch 5610's queue is
# "5610PRD_PlatformMessages.fifo", NOT "5610_PRD_PlatformMessages.fifo"
# (my first guess was wrong — corrected here after a real
# AWS.SimpleQueueService.NonExistentQueue error on the wrong name).

# C1 — queue attributes for branch 5610 (Cercado Bertello, one of the 12
# genuinely-stuck Peru orders traced in investigation.md)
aws sqs get-queue-attributes \
  --queue-url https://sqs.us-east-1.amazonaws.com/382381053403/5610PRD_PlatformMessages.fifo \
  --attribute-names ApproximateNumberOfMessages ApproximateNumberOfMessagesNotVisible ApproximateNumberOfMessagesDelayed \
  --region us-east-1 \
  > /home/dpaniagua/Documentos/git/bots/smartpedidos/events/20260917_smartcloud-peru-orders-pending/data/sqs_branch5610_attributes.json
