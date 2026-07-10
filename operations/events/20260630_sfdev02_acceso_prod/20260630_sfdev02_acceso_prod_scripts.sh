#!/bin/bash
# Investigación: sfdev02 — Acceso no autorizado a red de producción 192.168.50.0/24
# Fecha: 2026-06-30
# Suscripción prod: 0190fa7d-4ccf-4e3d-beb1-323b5780bfc8

# CX-01 — Reglas NSG de producción (sfcgnetsec01)
az network nsg rule list \
  --subscription 0190fa7d-4ccf-4e3d-beb1-323b5780bfc8 \
  --resource-group DefaultGroup01 \
  --nsg-name sfcgnetsec01 \
  --output json \
  --query "sort_by([].{Priority:priority, Name:name, Access:access, Direction:direction, Source:sourceAddressPrefix, SourcePrefixes:sourceAddressPrefixes, DestPort:destinationPortRange}, &Priority)"

# OUTPUT (2026-06-30): Ver hallazgos en ticket. Reglas críticas: P110 Allow 192.168.50.0/24 ALL, P126 Allow */ALL, P1400 Allow */3389, P1500 Allow 192.168.50.0/24:1433.

# CX-02 — Localizar NSG de dev
az network nsg list \
  --subscription 0190fa7d-4ccf-4e3d-beb1-323b5780bfc8 \
  --output json \
  --query "[?name=='sfdev02-nsg'].{name:name, resourceGroup:resourceGroup}"

# OUTPUT (2026-06-30): sfdev02-nsg en RG SFCG-REGR-DEV

# CX-03 — Reglas NSG de dev (sfdev02-nsg)
az network nsg rule list \
  --subscription 0190fa7d-4ccf-4e3d-beb1-323b5780bfc8 \
  --resource-group SFCG-REGR-DEV \
  --nsg-name sfdev02-nsg \
  --output json \
  --query "sort_by([].{Priority:priority, Name:name, Access:access, Direction:direction, Source:sourceAddressPrefix, DestPort:destinationPortRange}, &Priority)"

# OUTPUT (2026-06-30): P100 Subredes_out Allow Outbound */ALL — causa raíz confirmada.

# CX-04/07 — NIC y subred de sfdev02
az network nic show \
  --subscription 0190fa7d-4ccf-4e3d-beb1-323b5780bfc8 \
  --resource-group SFCG-REGR-DEV \
  --name sfdev0256_z1 \
  --output json \
  --query "{privateIp:ipConfigurations[0].privateIPAddress, subnet:ipConfigurations[0].subnet.id, nicNsg:networkSecurityGroup.id}"

# OUTPUT (2026-06-30): IP 10.2.0.4, VNet SmartFran-vnet/default, NSG sfdev02-nsg

# CX-05 — RBAC del usuario dantep@smartfran.com (suscripción prod)
az role assignment list \
  --subscription 0190fa7d-4ccf-4e3d-beb1-323b5780bfc8 \
  --assignee dantep@smartfran.com \
  --output json \
  --query "[].{Role:roleDefinitionName, Scope:scope}"

# OUTPUT (2026-06-30): Cost Management Reader + Billing Reader — solo lectura de facturación, descartado como vector.

# CX-06 — Identidad administrada de sfdev02
az vm show \
  --subscription 0190fa7d-4ccf-4e3d-beb1-323b5780bfc8 \
  --resource-group SFCG-REGR-DEV \
  --name sfdev02 \
  --output json \
  --query "identity"

# CX-08b — VNet peering de SmartFran-vnet
az network vnet show \
  --subscription 0190fa7d-4ccf-4e3d-beb1-323b5780bfc8 \
  --resource-group SFCG-REGR-DEV \
  --name SmartFran-vnet \
  --output json \
  --query "{name:name, prefixes:addressSpace.addressPrefixes, peerings:virtualNetworkPeerings[].{name:name, state:peeringState, remoteVnet:remoteVirtualNetwork.id, allowForwardedTraffic:allowForwardedTraffic, allowGatewayTransit:allowGatewayTransit, useRemoteGateways:useRemoteGateways}}"

# OUTPUT (2026-06-30): Peering smartfran-to-sfcgvnet01 → sfcgvnet01 (DefaultGroup01), estado Connected, allowForwardedTraffic=true, allowGatewayTransit=true

# CX-09 — Tabla de rutas efectivas en sfdev0256_z1
az network nic show-effective-route-table \
  --subscription 0190fa7d-4ccf-4e3d-beb1-323b5780bfc8 \
  --resource-group SFCG-REGR-DEV \
  --name sfdev0256_z1 \
  --output json \
  --query "value[].{source:source, state:state, prefix:addressPrefix, nextHopType:nextHopType, nextHop:nextHopIpAddress}"

# OUTPUT (2026-06-30): 192.168.0.0/16 → VNetPeering (confirma ruta a prod via peering).
#                      192.168.50.17/32 y 192.168.50.191/32 → InterfaceEndpoint (Private Endpoints a recursos prod).
