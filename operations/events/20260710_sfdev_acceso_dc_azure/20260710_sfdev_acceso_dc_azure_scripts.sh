#!/bin/bash
# sfdev — Sin acceso a los controladores de dominio de Azure AD DS
# Fecha: 2026-07-10
# Suscripción: Smart IT - Grido (0190fa7d-4ccf-4e3d-beb1-323b5780bfc8)

# CX-01 — Localizar recurso AADDS en suscripción
az resource list \
  --resource-type "Microsoft.AAD/domainServices" \
  --subscription 0190fa7d-4ccf-4e3d-beb1-323b5780bfc8 \
  --query "[].{name:name, rg:resourceGroup}" -o table
# OUTPUT (2026-07-10):
# Name           Rg
# -------------  --------------
# smartit.azure  DefaultGroup01

# CX-02 — Obtener IPs de los controladores de dominio
az resource show \
  --resource-group DefaultGroup01 \
  --resource-type "Microsoft.AAD/domainServices" \
  --name smartit.azure \
  --subscription 0190fa7d-4ccf-4e3d-beb1-323b5780bfc8 \
  --query "properties.replicaSets[].domainControllerIpAddress" -o table
# OUTPUT (2026-07-10):
# Column1       Column2
# ------------  ------------
# 192.168.40.4  192.168.40.5

# CX-03 — Crear regla Allow-AADDS-Outbound en sfdev02-nsg
az network nsg rule create \
  --resource-group SFCG-REGR-DEV \
  --nsg-name sfdev02-nsg \
  --name Allow-AADDS-Outbound \
  --priority 90 \
  --direction Outbound \
  --access Allow \
  --protocol '*' \
  --source-address-prefixes '*' \
  --source-port-ranges '*' \
  --destination-address-prefixes 192.168.40.4 192.168.40.5 \
  --destination-port-ranges 88 389 636 53 445 \
  --subscription 0190fa7d-4ccf-4e3d-beb1-323b5780bfc8
# OUTPUT (2026-07-10):
# Regla creada en P101 (P90 solicitado; P100 ya estaba en uso).
# Puertos iniciales: 88, 389, 636, 53, 445. Timeout confirmado — ver CX-04.

# CX-04 — Actualizar Allow-AADDS-Outbound a puertos wildcard (puertos específicos generaron timeout NLA)
az network nsg rule update \
  --resource-group SFCG-REGR-DEV \
  --nsg-name sfdev02-nsg \
  --name Allow-AADDS-Outbound \
  --destination-port-ranges '*' \
  --subscription 0190fa7d-4ccf-4e3d-beb1-323b5780bfc8
# OUTPUT (2026-07-10):
# destinationPortRanges: ["*"]
# provisioningState: Succeeded

# CX-05 — Estado completo NSG sfdev02-nsg — Outbound
az network nsg rule list \
  --resource-group SFCG-REGR-DEV \
  --nsg-name sfdev02-nsg \
  --subscription 0190fa7d-4ccf-4e3d-beb1-323b5780bfc8 \
  --output json | jq -r '
  [.[] | select(.direction == "Outbound")] | sort_by(.priority) |
  (["P","Name","Access","Proto","Source","Dest","DestPort"]),
  (.[] | [
    (.priority | tostring),
    .name, .access, .protocol,
    ([.sourceAddressPrefix] + .sourceAddressPrefixes | map(select(. != "" and . != null)) | join(",")),
    ([.destinationAddressPrefix] + .destinationAddressPrefixes | map(select(. != "" and . != null)) | join(",")),
    ([.destinationPortRange] + .destinationPortRanges | map(select(. != "" and . != null)) | join(","))
  ]) | @tsv'
# OUTPUT (2026-07-10):
# P     Name                       Access  Proto  Source  Dest                       DestPort
# 100   Allow-Outbound-strgsqlbkp  Allow   *      *       192.168.50.17/32           443,445
# 101   Allow-AADDS-Outbound       Allow   *      *       192.168.40.4,192.168.40.5  *
# 500   Deny-Outbound-Prod-192     Deny    *      *       192.168.0.0/16             *
# 501   Deny-Outbound-Prod-10      Deny    *      *       10.0.0.0/16                *
# 1000  Subredes_out               Allow   *      *       *                          *

# CX-06 — Estado completo NSG sfdev02-nsg — Inbound
az network nsg rule list \
  --resource-group SFCG-REGR-DEV \
  --nsg-name sfdev02-nsg \
  --subscription 0190fa7d-4ccf-4e3d-beb1-323b5780bfc8 \
  --output json | jq -r '
  [.[] | select(.direction == "Inbound")] | sort_by(.priority) |
  (["P","Name","Access","Proto","Source","SourcePort","Dest","DestPort"]),
  (.[] | [
    (.priority | tostring),
    .name, .access, .protocol,
    ([.sourceAddressPrefix] + .sourceAddressPrefixes | map(select(. != "" and . != null)) | join(",")),
    ([.sourcePortRange] + .sourcePortRanges | map(select(. != "" and . != null)) | join(",")),
    ([.destinationAddressPrefix] + .destinationAddressPrefixes | map(select(. != "" and . != null)) | join(",")),
    ([.destinationPortRange] + .destinationPortRanges | map(select(. != "" and . != null)) | join(","))
  ]) | @tsv'
# OUTPUT (2026-07-10):
# P    Name                     Access  Proto  Source       SourcePort  Dest        DestPort
# 300  RDP                      Allow   TCP    *            *           *           3389
# 310  ClubSite_Test02_9443     Allow   *      *            *           *           9443
# 320  MobileApp_803            Allow   *      *            *           *           803
# 321  MobileApp_843_HTPS       Allow   TCP    *            *           *           843
# 330  WebService_804           Allow   *      *            *           *           804,802,805
# 340  ClubSite_Test02_9080     Allow   *      *            *           *           9080
# 350  Port_80                  Allow   *      *            *           10.2.0.5    80,22,443
# 360  Port_443                 Allow   *      *            *           *           443
# 370  Port_8080                Allow   *      *            *           *           8080
# 380  Port_4430                Allow   *      *            *           *           4430
# 390  Port_8081                Allow   *      *            *           *           8081,8082,8184
# 400  Subredes                 Allow   *      10.2.1.0/24  *           10.2.0.0/24 *
# 410  Port_SQL                 Allow   TCP    *            *           *           1433
# 420  Entorno_DEV              Allow   *      *            *           *           7443,700,701,702,703,704
# 430  AllowWebserviceV2Prepro  Allow   *      *            *           *           8181,8182,8183,8184,8185
# 440  AllowAnyRDPInbound       Allow   TCP    *            *           10.3.0.4    3389
# 600  dev-keycloak-http        Allow   *      *            *           10.0.2.5    8080
# 610  dev-keycloak-https       Allow   TCP    *            *           *           8443
