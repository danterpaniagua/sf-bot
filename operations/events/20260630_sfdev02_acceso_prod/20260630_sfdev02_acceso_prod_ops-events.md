# Eventos — sfdev02 Acceso no autorizado a red de producción

## 2026-06-30 — Apertura de investigación

Se ha iniciado la investigación tras detectar que la VM sfdev02 (entorno DEV, RG `SFCG-REGR-DEV`) tiene conectividad hacia la red de producción `192.168.50.0/24`. Se ha confirmado el acceso vía RDP a `192.168.50.121` desde una sesión activa en sfdev02.

## 2026-06-30 — CX-01: Reglas NSG producción (sfcgnetsec01)

**Comando:** CX-01 — az network nsg rule list sfcgnetsec01
**Resultado:** 38 reglas inbound. Críticas: P110 Allow 192.168.50.0/24/ALL, P115 Allow */ALL, P126 Allow */ALL ports, P1400 Allow */3389, P1500 Allow 192.168.50.0/24:1433.
**Observación:** Se ha identificado que el NSG prod acepta tráfico desde toda la subred `192.168.50.0/24` en todos los puertos (P110). La superficie de entrada es excesiva.

## 2026-06-30 — CX-02: Localización de sfdev02-nsg

**Comando:** CX-02 — az network nsg list (filtro sfdev02-nsg)
**Resultado:** sfdev02-nsg en RG SFCG-REGR-DEV.
**Observación:** Se ha localizado el NSG de dev en el resource group correspondiente.

## 2026-06-30 — CX-03: Reglas NSG dev (sfdev02-nsg)

**Comando:** CX-03 — az network nsg rule list sfdev02-nsg
**Resultado:** P100 Subredes_out — Allow Outbound Source:* DestPort:* (todo el tráfico saliente permitido sin restricción de destino).
**Observación:** Se ha confirmado la causa raíz de salida. La regla P100 permite enviar tráfico a cualquier IP y puerto sin restricción NSG.

## 2026-06-30 — CX-05: RBAC usuario dantep@smartfran.com

**Comando:** CX-05 — az role assignment list (suscripción prod)
**Resultado:** Cost Management Reader + Billing Reader — solo facturación.
**Observación:** Se ha descartado el acceso vía permisos de usuario al plano de control de producción.

## 2026-06-30 — CX-07: NIC sfdev0256_z1

**Comando:** CX-07 — az network nic show sfdev0256_z1
**Resultado:** IP privada 10.2.0.4, VNet SmartFran-vnet/subnet default, NSG sfdev02-nsg.
**Observación:** Se ha verificado que sfdev02 no está en la subred `192.168.50.0/24`. El acceso es por enrutamiento, no por co-ubicación en la misma subred.

## 2026-06-30 — CX-08b: VNet Peering SmartFran-vnet

**Comando:** CX-08b — az network vnet show SmartFran-vnet
**Resultado:** Peering activo smartfran-to-sfcgvnet01 → sfcgvnet01 (DefaultGroup01), estado Connected, allowForwardedTraffic=true, allowGatewayTransit=true.
**Observación:** Se ha identificado el VNet Peering como canal de enrutamiento entre la VNet de dev (10.2.0.0/16) y la VNet de prod (sfcgvnet01, que contiene 192.168.0.0/16).

## 2026-06-30 — CX-09: Rutas efectivas sfdev0256_z1

**Comando:** CX-09 — az network nic show-effective-route-table sfdev0256_z1
**Resultado:** 192.168.0.0/16 → VNetPeering (activo). 192.168.50.17/32 y 192.168.50.191/32 → InterfaceEndpoint (activo).
**Observación:** Se ha confirmado la ruta a prod vía VNet Peering. Adicionalmente, se han detectado dos Private Endpoints hacia IPs específicas dentro de la red prod (`192.168.50.17` y `192.168.50.191`), los cuales crean conexiones dedicadas que eluden el filtrado NSG en el lado del servicio.

## 2026-07-08 — CX-10/CX-11: Identificación de Private Endpoints en red prod

**Comando:** CX-10 — az network private-endpoint list / CX-11 — az network nic list (filtro por IP)
**Resultado:**
- `192.168.50.17` → PE `despliegues` → `Microsoft.Storage/storageAccounts/strgsqlbkp` (RG DefaultGroup01, subnet sfcgvnet01/DMZ)
- `192.168.50.191` → PE `sf-sml-redis-prod` → `Microsoft.Cache/Redis/SmartLoyalty-Cache-PRO-01` (RG DefaultGroup01, subnet sfcgvnet01/DMZ)
**Observación:** Se ha identificado que sfdev02 tiene acceso directo a dos recursos de producción críticos: el storage account de backups de SQL Server (`strgsqlbkp`) y el caché Redis de SmartLoyalty producción (`SmartLoyalty-Cache-PRO-01`). El PE `despliegues` ha sido confirmado como intencional — se utiliza para restaurar backups de producción en el entorno de desarrollo para pruebas de nuevas funcionalidades. El PE `sf-sml-redis-prod` requiere confirmación de necesidad antes de determinar si debe mantenerse o eliminarse.

## 2026-07-08 — Verificación de conectividad post-remediación NSG

**Comando:** Pruebas manuales de conectividad desde sesión RDP en sfdev02
**Resultado:**
- RDP a `10.0.0.4` → bloqueado ✓
- RDP a `192.168.50.111` → bloqueado ✓
- `\\192.168.50.17\` (SMB, puerto 445) → bloqueado ✗ — requerido para restore de backups
**Observación:** Se ha verificado que el bloqueo a las redes de producción es efectivo. Sin embargo, se ha detectado que la regla `Allow-Outbound-strgsqlbkp` (P100) solo permite el puerto 443, mientras que el script de conexión al storage account utiliza SMB puerto 445 (`\\192.168.50.17\`). Se debe actualizar la regla para incluir el puerto 445.

## 2026-07-08 — CX-22: Actualización de regla Allow-Outbound-strgsqlbkp (puerto 445)

**Comando:** CX-22 — az network nsg rule update Allow-Outbound-strgsqlbkp --destination-port-ranges 443 445
**Resultado:** Regla actualizada. Se ha reconectado la unidad Z: en sfdev02. Resultado: `Z: \\192.168.50.17\despliegues` — 120.08 GB usados, 4999.92 GB libres. Acceso SMB confirmado.
**Observación:** Se ha verificado que el acceso al storage account de backups (`strgsqlbkp`) vía SMB puerto 445 funciona correctamente con la regla ajustada. El bloqueo al resto de la red de producción permanece activo. Remediación NSG completada.
