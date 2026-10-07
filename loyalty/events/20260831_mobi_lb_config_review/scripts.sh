#!/bin/bash
# GITIN-1967 — SFCG-MOBI-LB config review
# Subscription: Smart IT - Grido, RG: DefaultGroup01

SUB=0190fa7d-4ccf-4e3d-beb1-323b5780bfc8
RG=DefaultGroup01
LB=SFCG-MOBI-LB

# C1 — re-verify rules (10 days old since GITIN-1909, don't trust without checking)
az network lb rule list --lb-name $LB --resource-group $RG --subscription $SUB \
  --query "[].{name:name, protocol:protocol, frontendPort:frontendPort, backendPort:backendPort, idleTimeoutInMinutes:idleTimeoutInMinutes, loadDistribution:loadDistribution, probe:probe.id, backendPool:backendAddressPool.id}" -o table

# C2 — re-verify probes (which one is live, numberOfProbes, orphans)
az network lb probe list --lb-name $LB --resource-group $RG --subscription $SUB \
  --query "[].{name:name, protocol:protocol, port:port, intervalInSeconds:intervalInSeconds, numberOfProbes:numberOfProbes, requestPath:requestPath}" -o table

# C3 — re-verify backend pool membership
az network lb address-pool list --lb-name $LB --resource-group $RG --subscription $SUB \
  --query "[].{name:name, backendIps:backendIPConfigurations[].id}" -o json

# C4 — NEW: outbound rules / SNAT config — Standard LB has no default outbound (unlike Basic),
# needs an explicit outbound rule or a NAT Gateway or the backend VMs have no outbound path at all.
az network lb outbound-rule list --lb-name $LB --resource-group $RG --subscription $SUB -o table

# C5 — NEW: frontend IP config zones (frontend redundancy) and the public IP's own zone config
az network lb frontend-ip list --lb-name $LB --resource-group $RG --subscription $SUB \
  --query "[].{name:name, zones:zones, publicIp:publicIPAddress.id}" -o table

az network public-ip show --name SFCG-MOBI-LB-publicip --resource-group $RG --subscription $SUB \
  --query "{name:name, zones:zones, sku:sku.name, allocationMethod:publicIPAllocationMethod}" -o json

# C6 — NEW: diagnostic settings on the LB (is anything actually logging LB-level events/metrics
# beyond the ad-hoc az monitor metrics list queries done reactively in GITIN-1909?)
LB_ID=$(az network lb show --name $LB --resource-group $RG --subscription $SUB --query id -o tsv)
az monitor diagnostic-settings list --resource "$LB_ID" --subscription $SUB -o table

# C7 — NEW: NAT gateway / any explicit outbound path attached to the DMZ subnet, in case
# outbound connectivity relies on subnet-level NAT rather than the LB's own outbound rules
az network vnet subnet list --resource-group $RG --subscription $SUB \
  --query "[].{name:name, natGateway:natGateway.id}" -o table
