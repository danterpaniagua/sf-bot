#!/usr/bin/env bash
# Event: 20260917_smartpedidos-peru-orders-pending (GITIN-2068)
# Checking the "deployer" field for today's 2 production deployments on
# Orders-PRO -- distinguishes a GitHub Actions deploy (deployer: "OneDeploy")
# from a direct Visual Studio publish (different deployer string), in case
# someone deployed straight from VS rather than through the pipeline.

az webapp log deployment list \
  --name SmartFran-Cloud-Orders-PRO \
  --resource-group SmartFran.Cloud.PRO \
  --subscription 85c76dea-3304-4310-8656-bf21b28e4f4b \
  --query "[?starts_with(start_time, '2026-09-17')].{start:start_time, deployer:deployer, author:author, message:message, active:active}" \
  -o json \
  > data/orders_pro_today_deployer.json
