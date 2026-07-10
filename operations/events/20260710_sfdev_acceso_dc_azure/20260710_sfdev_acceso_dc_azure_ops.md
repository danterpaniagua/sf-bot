# [OPE] sfdev — Sin acceso a los controladores de dominio de Azure AD DS

**Fecha:** 2026-07-10
**Estado:** En verificación
**Severidad:** Alta
**Suscripción:** Smart IT - Grido (`0190fa7d-4ccf-4e3d-beb1-323b5780bfc8`)

---

## Resumen

La VM `sfdev02` (RG `SFCG-REGR-DEV`) perdió conectividad con los controladores de dominio de Azure AD DS (`smartit.azure`) como efecto secundario de las reglas de denegación de tráfico saliente hacia `192.168.0.0/16` implementadas en el NSG `sfdev02-nsg` (evento relacionado: `20260630_sfdev02_acceso_prod`). Los DC de AADDS residen en `192.168.40.0/24`, subred incluida en el rango denegado. Como consecuencia, la autenticación NLA falla al intentar establecer sesiones RDP hacia `sfdev02`, ya que la VM no puede contactar al DC para validar credenciales de dominio vía Kerberos. Se debe agregar una regla de permiso explícita para tráfico saliente hacia los DC con prioridad superior a la regla de denegación.

---

## Tabla resumen

| Ítem | Detalle |
|---|---|
| VM afectada | `sfdev02` — RG `SFCG-REGR-DEV` |
| NSG afectado | `sfdev02-nsg` — RG `SFCG-REGR-DEV` |
| Error reportado | NLA error 0x0 — "no se puede establecer contacto con el controlador de dominio" |
| Dominio AADDS | `smartit.azure` — RG `DefaultGroup01` |
| IPs DC | `192.168.40.4`, `192.168.40.5` (subred `192.168.40.0/24`) |
| Causa | `Deny-Outbound-Prod-192` (P500) bloquea `192.168.0.0/16`, cubriendo la subred AADDS |
| Regla aplicada | `Allow-AADDS-Outbound` (P101) — Allow `*` → `192.168.40.4`, `192.168.40.5` puerto `*` |
| Evento relacionado | `20260630_sfdev02_acceso_prod` |

---

## Causa raíz

Las reglas `Deny-Outbound-Prod-192` (P500, destino `192.168.0.0/16`) y `Deny-Outbound-Prod-10` (P501, destino `10.0.0.0/16`), implementadas para aislar `sfdev02` de la red de producción, también bloquean el tráfico saliente hacia `192.168.40.0/24`, subred donde residen los controladores de dominio de Azure AD DS.

NLA requiere que la VM contacte al DC mediante Kerberos antes de establecer la sesión RDP. Sin esta conectividad, la autenticación falla con código de error 0x0.

La prueba inicial con puertos específicos (88, 389, 636, 53, 445) resultó en timeout, confirmando que el flujo Kerberos en este entorno utiliza puertos dinámicos RPC adicionales. La regla definitiva aplica destino `*` en puertos, acotado a las IPs de los DC.

---

## Hallazgos

### NSG sfdev02-nsg — Estado actual (2026-07-10)

**Outbound:**

| P | Nombre | Acceso | Proto | Source | Dest | DestPort |
|---|---|---|---|---|---|---|
| 100 | Allow-Outbound-strgsqlbkp | Allow | * | * | 192.168.50.17/32 | 443,445 |
| 101 | Allow-AADDS-Outbound | Allow | * | * | 192.168.40.4, 192.168.40.5 | * |
| 500 | Deny-Outbound-Prod-192 | Deny | * | * | 192.168.0.0/16 | * |
| 501 | Deny-Outbound-Prod-10 | Deny | * | * | 10.0.0.0/16 | * |
| 1000 | Subredes_out | Allow | * | * | * | * |

**Inbound:**

| P | Nombre | Acceso | Proto | Source | SourcePort | Dest | DestPort |
|---|---|---|---|---|---|---|---|
| 300 | RDP | Allow | TCP | * | * | * | 3389 |
| 310 | ClubSite_Test02_9443 | Allow | * | * | * | * | 9443 |
| 320 | MobileApp_803 | Allow | * | * | * | * | 803 |
| 321 | MobileApp_843_HTPS | Allow | TCP | * | * | * | 843 |
| 330 | WebService_804 | Allow | * | * | * | * | 804,802,805 |
| 340 | ClubSite_Test02_9080 | Allow | * | * | * | * | 9080 |
| 350 | Port_80 | Allow | * | * | * | 10.2.0.5 | 80,22,443 |
| 360 | Port_443 | Allow | * | * | * | * | 443 |
| 370 | Port_8080 | Allow | * | * | * | * | 8080 |
| 380 | Port_4430 | Allow | * | * | * | * | 4430 |
| 390 | Port_8081 | Allow | * | * | * | * | 8081,8082,8184 |
| 400 | Subredes | Allow | * | 10.2.1.0/24 | * | 10.2.0.0/24 | * |
| 410 | Port_SQL | Allow | TCP | * | * | * | 1433 |
| 420 | Entorno_DEV | Allow | * | * | * | * | 7443,700,701,702,703,704 |
| 430 | AllowWebserviceV2Prepro | Allow | * | * | * | * | 8181,8182,8183,8184,8185 |
| 440 | AllowAnyRDPInbound | Allow | TCP | * | * | 10.3.0.4 | 3389 |
| 600 | dev-keycloak-http | Allow | * | * | * | 10.0.2.5 | 8080 |
| 610 | dev-keycloak-https | Allow | TCP | * | * | * | 8443 |

> Las reglas con prefijo `Port_` en inbound corresponden a acceso internet a aplicaciones IIS web. No constituyen hallazgo de seguridad en este contexto.

---

## Recursos afectados

| Recurso | Tipo | RG |
|---|---|---|
| `sfdev02` | VM | `SFCG-REGR-DEV` |
| `sfdev02-nsg` | NSG | `SFCG-REGR-DEV` |
| `smartit.azure` | Azure AD DS | `DefaultGroup01` |
| DC `192.168.40.4` | Controlador de dominio AADDS | `DefaultGroup01` |
| DC `192.168.40.5` | Controlador de dominio AADDS | `DefaultGroup01` |

---

## Comandos ejecutados

| # | Comando/Script | Propósito |
|---|---|---|
| CX-01 | `20260710_sfdev_acceso_dc_azure_scripts.sh` | Localizar recurso AADDS en suscripción |
| CX-02 | `20260710_sfdev_acceso_dc_azure_scripts.sh` | Obtener IPs de los controladores de dominio |
| CX-03 | `20260710_sfdev_acceso_dc_azure_scripts.sh` | Crear regla Allow-AADDS-Outbound en sfdev02-nsg |
| CX-04 | `20260710_sfdev_acceso_dc_azure_scripts.sh` | Actualizar Allow-AADDS-Outbound a puertos wildcard |
| CX-05 | `20260710_sfdev_acceso_dc_azure_scripts.sh` | Estado completo NSG sfdev02-nsg — Outbound |
| CX-06 | `20260710_sfdev_acceso_dc_azure_scripts.sh` | Estado completo NSG sfdev02-nsg — Inbound |

---

## Acciones propuestas

1. **Verificar conectividad RDP** — confirmar que DevOps puede establecer sesión RDP hacia `sfdev02` con NLA activo tras la aplicación de `Allow-AADDS-Outbound` (P101).
2. **Evaluar reducción de puertos en Allow-AADDS-Outbound** — la regla actual permite todos los puertos (`*`) hacia los DC. Evaluar restricción a rango de puertos dinámicos RPC (49152–65535) junto con los puertos fijos de Kerberos en una ventana de mantenimiento.
3. **Replicar regla en otras VMs dev** — verificar si otras VMs de desarrollo en la misma VNet tienen configuración NSG similar y requieren la misma regla `Allow-AADDS-Outbound`.
4. **Documentar subred AADDS en playbook de hardening** — incorporar `192.168.40.0/24` como exclusión explícita al momento de definir reglas de deny hacia `192.168.0.0/16` en entornos con Azure AD DS.

---

## Hallazgos secundarios

- La subred AADDS `192.168.40.0/24` no estaba documentada como exclusión en el evento `20260630_sfdev02_acceso_prod`. Cualquier deny sobre `192.168.0.0/16` debe carve-out esta subred para preservar la autenticación de dominio.
- `Allow-Outbound-strgsqlbkp` (P100) permite tráfico hacia `192.168.50.17/32` en puertos 443 y 445. Confirmado como punto de montaje cross-RG legítimo para backup SQL/storage. No requiere acción.
