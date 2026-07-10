# Azure NSG Reference

**Last updated:** 2026-07-10
**Subscription:** Smart IT - Grido (`0190fa7d-4ccf-4e3d-beb1-323b5780bfc8`)

---

## Resource Groups

| Resource Group | Environment | Purpose |
|---|---|---|
| `DefaultGroup01` | **Production** | SmartLoyalty prod VMs, NSGs, VNets, AADDS, Private Endpoints |
| `SFCG-REGR-DEV` | **Dev / Testing / Staging** | SmartLoyalty dev/testing/staging VMs, NSGs, VNets |

---

## VNet Topology

| VNet | CIDR | RG | Environment |
|---|---|---|---|
| SmartFran-vnet | 10.2.0.0/16 | SFCG-REGR-DEV | Dev |
| sfcgvnet01 | 192.168.0.0/16 | DefaultGroup01 | Prod |

### VNet Peering

| Peering | From | To | Status |
|---|---|---|---|
| smartfran-to-sfcgvnet01 | SmartFran-vnet | sfcgvnet01 | Connected |

Peering has `allowGatewayTransit: true`, `allowForwardedTraffic: true`. If `sfcgvnet01` has a VPN Gateway, dev VMs may also reach on-premises networks through it. Route `10.0.0.0/16` also appears as `VNetPeering` in sfdev02 effective routes — at least one additional private network is reachable from dev.

---

## Azure AD DS

| Field | Value |
|---|---|
| Domain | `smartit.azure` |
| RG | `DefaultGroup01` |
| DC subnet | `192.168.40.0/24` |
| DC 1 | `192.168.40.4` |
| DC 2 | `192.168.40.5` |

**Rule:** when adding deny rules covering `192.168.0.0/16`, always carve out `192.168.40.0/24` with a higher-priority allow rule targeting the DC IPs. Kerberos NLA uses dynamic RPC ports — use port `*` scoped to the DC IPs, not a port list.

---

## Known NSGs

### sfdev02-nsg — SFCG-REGR-DEV (Dev VM)

Associated with: VM `sfdev02`, NIC `sfdev0256_z1`

**Outbound (2026-07-10):**

| P | Name | Access | Proto | Dest | DestPort | Note |
|---|---|---|---|---|---|---|
| 100 | Allow-Outbound-strgsqlbkp | Allow | * | 192.168.50.17/32 | 443,445 | Cross-RG PE — SQL/storage backup mount. Confirmed legitimate. |
| 101 | Allow-AADDS-Outbound | Allow | * | 192.168.40.4, 192.168.40.5 | * | DC auth — Kerberos requires dynamic ports |
| 500 | Deny-Outbound-Prod-192 | Deny | * | 192.168.0.0/16 | * | Prod isolation |
| 501 | Deny-Outbound-Prod-10 | Deny | * | 10.0.0.0/16 | * | Prod isolation |
| 1000 | Subredes_out | Allow | * | * | * | Catch-all — effective only for dev traffic (10.2.x.x) |

**Inbound (2026-07-10):**

| P | Name | Access | Proto | Source | Dest | DestPort | Note |
|---|---|---|---|---|---|---|---|
| 300 | RDP | Allow | TCP | * | * | 3389 | Internet-exposed |
| 310–390, 420, 430, 600, 610 | Port_* / Entorno_DEV / AllowWebservice* / keycloak | Allow | * | * | * | various | Internet access to IIS web apps — intentional |
| 400 | Subredes | Allow | * | 10.2.1.0/24 | 10.2.0.0/24 | * | Dev internal |
| 410 | Port_SQL | Allow | TCP | * | * | 1433 | Internet-exposed |
| 440 | AllowAnyRDPInbound | Allow | TCP | * | 10.3.0.4 | 3389 | — |

### sfcgnetsec01 — DefaultGroup01 (Prod)

Associated with: VNet `sfcgvnet01`, prod subnet `192.168.50.0/24`

**Inbound findings (2026-06-30):**

| P | Name | Source | DestPort | Note |
|---|---|---|---|---|
| 110 | SMTP-Any-sfcgvm06 | 192.168.50.0/24 | ALL | All traffic from prod subnet, no port restriction |
| 115 | AD-Any_Any | * | ALL | All traffic from any source |
| 126 | AllowAnyCustom22_80_443Inbound | * | ALL | All ports from any source |
| 1400 | AllowAnyCustom3389Inbound | * | 3389 | RDP internet-exposed |

---

## Known Private Endpoints

| IP | Type | Status | Note |
|---|---|---|---|
| 192.168.50.17/32 | InterfaceEndpoint | Confirmed legitimate | Cross-RG SQL/storage backup mount (`strgsqlbkp`) |
| 192.168.50.191/32 | InterfaceEndpoint | **Unverified** | Pending identification |

---

## CLI Patterns

### List NSG rules — full columns (outbound)

```bash
az network nsg rule list \
  --resource-group <RG> \
  --nsg-name <NSG_NAME> \
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
```

### List NSG rules — full columns (inbound)

```bash
az network nsg rule list \
  --resource-group <RG> \
  --nsg-name <NSG_NAME> \
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
```

### Get Azure AD DS DC IPs

```bash
az resource show \
  --resource-group DefaultGroup01 \
  --resource-type "Microsoft.AAD/domainServices" \
  --name smartit.azure \
  --subscription 0190fa7d-4ccf-4e3d-beb1-323b5780bfc8 \
  --query "properties.replicaSets[].domainControllerIpAddress" -o table
```
