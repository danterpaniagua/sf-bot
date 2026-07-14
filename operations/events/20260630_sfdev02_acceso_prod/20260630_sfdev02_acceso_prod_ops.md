# [OPS] sfdev02 — Acceso no autorizado a red de producción 192.168.50.0/24

**Fecha:** 2026-06-30
**Estado:** Abierto
**Severidad:** Alta
**Suscripción:** Smart IT - Grido (`0190fa7d-4ccf-4e3d-beb1-323b5780bfc8`)

---

## Resumen

La VM de desarrollo `sfdev02` (RG `SFCG-REGR-DEV`, IP `10.2.0.4`) tiene conectividad total hacia la red de producción `192.168.50.0/24`. El acceso fue confirmado por mi vía RDP a `192.168.50.121`. La causa es la combinación de un VNet Peering activo entre la VNet de dev y la VNet de prod, junto con una regla NSG en el entorno dev que permite todo el tráfico saliente sin restricción de destino. Adicionalmente se detectaron dos Private Endpoints desde sfdev02 hacia IPs específicas de producción.

---

## Tabla resumen

| Ítem | Detalle |
|---|---|
| VM afectada | `sfdev02` — RG `SFCG-REGR-DEV` |
| IP dev | `10.2.0.4` (VNet `SmartFran-vnet`, subred `default`, `10.2.0.0/16`) |
| Red prod alcanzada | `192.168.50.0/24` (VNet `sfcgvnet01`, RG `DefaultGroup01`) |
| Conectividad confirmada | RDP a `192.168.50.121` desde sesión en sfdev02 |
| NSG dev | `sfdev02-nsg` — RG `SFCG-REGR-DEV` |
| NSG prod | `sfcgnetsec01` — RG `DefaultGroup01` |
| Canal de enrutamiento | VNet Peering `smartfran-to-sfcgvnet01` (Connected) |
| Private Endpoints detectados | `192.168.50.17/32`, `192.168.50.191/32` → InterfaceEndpoint |
| RBAC usuario | Cost Management Reader + Billing Reader (descartado) |

---

## Causa raíz

Dos vectores independientes permiten el acceso:

**Vector 1 — NSG + VNet Peering (acceso general a 192.168.50.0/24)**

1. La regla `Subredes_out` (P100) en `sfdev02-nsg` permite **todo el tráfico saliente** sin restricción de destino ni puerto.
2. El peering `smartfran-to-sfcgvnet01` anuncia la ruta `192.168.0.0/16` a sfdev02, incluyendo `192.168.50.0/24`.
3. El NSG prod `sfcgnetsec01` acepta el tráfico entrante desde `192.168.50.0/24` en todos los puertos (regla P110 `SMTP-Any-sfcgvm06`).

**Vector 2 — Private Endpoints (acceso directo a servicios prod)**

Los endpoints `192.168.50.17/32` y `192.168.50.191/32` aparecen como `InterfaceEndpoint` en la tabla de rutas efectivas de sfdev02. Esto indica Private Endpoints configurados desde la VNet de dev hacia servicios en la red de producción. Estas conexiones son dedicadas y eluden el filtrado NSG en el lado del servicio.

---

## Hallazgos

### sfdev02-nsg (dev) — hallazgos críticos

| Prioridad | Regla | Dirección | Source | Puerto | Problema |
|---|---|---|---|---|---|
| 100 | `Subredes_out` | Outbound | `*` | `*` | **Causa raíz** — permite salida a cualquier destino |
| 300 | `RDP` | Inbound | `*` | 3389 | RDP expuesto a internet |
| 410 | `Port_SQL` | Inbound | `*` | 1433 | SQL Server 1433 expuesto a internet |
| 440 | `AllowAnyRDPInbound` | Inbound | `*` | 3389 | RDP duplicado, también expuesto a internet |

### sfcgnetsec01 (prod) — hallazgos relacionados

| Prioridad | Regla | Source | Puerto | Problema |
|---|---|---|---|---|
| 110 | `SMTP-Any-sfcgvm06` | `192.168.50.0/24` | ALL | Permite todo el tráfico desde subred prod — sin restricción de puerto |
| 115 | `AD-Any_Any` | `*` | ALL | Todo el tráfico desde cualquier origen |
| 126 | `AllowAnyCustom22_80_443Inbound` | `*` | ALL | Todos los puertos desde cualquier origen |
| 1400 | `AllowAnyCustom3389Inbound` | `*` | 3389 | RDP expuesto a internet |

---

## Recursos afectados

| Recurso | Tipo | RG |
|---|---|---|
| `sfdev02` | VM | `SFCG-REGR-DEV` |
| `sfdev0256_z1` | NIC | `SFCG-REGR-DEV` |
| `sfdev02-nsg` | NSG | `SFCG-REGR-DEV` |
| `SmartFran-vnet` | VNet | `SFCG-REGR-DEV` |
| `smartfran-to-sfcgvnet01` | VNet Peering | `SFCG-REGR-DEV` |
| `sfcgvnet01` | VNet | `DefaultGroup01` |
| `sfcgnetsec01` | NSG | `DefaultGroup01` |
| PE en `192.168.50.17` | Private Endpoint | A confirmar |
| PE en `192.168.50.191` | Private Endpoint | A confirmar |

---

## Comandos ejecutados

| # | Comando/Script | Propósito |
|---|---|---|
| CX-01 | `20260630_sfdev02_acceso_prod_scripts.sh` | Reglas NSG prod sfcgnetsec01 |
| CX-02 | `20260630_sfdev02_acceso_prod_scripts.sh` | Localizar sfdev02-nsg |
| CX-03 | `20260630_sfdev02_acceso_prod_scripts.sh` | Reglas NSG dev sfdev02-nsg |
| CX-05 | `20260630_sfdev02_acceso_prod_scripts.sh` | RBAC usuario dantep@smartfran.com |
| CX-07 | `20260630_sfdev02_acceso_prod_scripts.sh` | NIC sfdev0256_z1 — IP y subred |
| CX-08b | `20260630_sfdev02_acceso_prod_scripts.sh` | VNet peering SmartFran-vnet |
| CX-09 | `20260630_sfdev02_acceso_prod_scripts.sh` | Rutas efectivas sfdev0256_z1 |

---

## Acciones propuestas

### Inmediatas (bloqueo de acceso)

1. **Restringir `Subredes_out` (P100) en `sfdev02-nsg`** — reemplazar `Source: *, Dest: *, Port: *` por una regla que permita salida únicamente hacia rangos de dev (`10.2.0.0/16`) y agregue una regla de denegación explícita hacia `192.168.0.0/16` y `10.0.0.0/16` (rangos prod).
2. **Identificar y auditar los Private Endpoints `192.168.50.17` y `192.168.50.191`** — determinar qué servicios prod tienen PE configurados hacia la VNet de dev y evaluar si son intencionales o residuos de configuración.

### Corto plazo (hardening NSG dev)

3. **Eliminar exposición de RDP a internet** — restringir reglas P300 y P440 a IPs de administración conocidas.
4. **Restringir SQL 1433 (P410)** — limitar a IPs de dev autorizadas, no `*`.

### Mediano plazo (revisión de arquitectura)

5. **Revisar justificación del VNet Peering `smartfran-to-sfcgvnet01`** — si el peering es necesario, implementar UDR (User Defined Routes) o NSG a nivel de subred en prod que denieguen tráfico desde `10.2.0.0/16` excepto puertos explícitamente autorizados.
6. **Auditar NSG prod `sfcgnetsec01`** — las reglas P115, P126 y P1400 abren puertos a internet (`*`) sin justificación documentada. Requieren revisión y cierre o restricción de fuente.

---

## Hallazgos secundarios

- El peering `smartfran-to-sfcgvnet01` tiene `allowGatewayTransit: true` y `allowForwardedTraffic: true`. Si `sfcgvnet01` tiene un VPN Gateway, sfdev02 podría también alcanzar redes on-premises a través de él.
- La ruta `10.0.0.0/16` también aparece como `VNetPeering` en la tabla de rutas de sfdev02, indicando que hay al menos otra red privada accesible desde el entorno dev además de `192.168.0.0/16`.
