# Eventos — sfdev — Sin acceso a los controladores de dominio de Azure AD DS

## 2026-07-10 13:55 — Error NLA reportado por DevOps

**Observación:** Se ha recibido reporte de error NLA código 0x0 al intentar conexión RDP hacia sfdev02. El mensaje indica que no se puede contactar al controlador de dominio para realizar NLA. Se identifica como efecto secundario de las reglas de deny implementadas en el evento `20260630_sfdev02_acceso_prod`.

---

## 2026-07-10 14:10 — Localización del recurso AADDS

**Comando:** CX-01 — Localizar recurso AADDS en suscripción
**Resultado:**
```
Name           Rg
-------------  --------------
smartit.azure  DefaultGroup01
```
**Observación:** Se ha identificado el dominio AADDS `smartit.azure` en el RG `DefaultGroup01`.

---

## 2026-07-10 14:15 — Obtención de IPs de los controladores de dominio

**Comando:** CX-02 — Obtener IPs de los DC
**Resultado:**
```
Column1       Column2
------------  ------------
192.168.40.4  192.168.40.5
```
**Observación:** Se ha confirmado que los DC residen en `192.168.40.0/24`, subred incluida dentro del rango `192.168.0.0/16` bloqueado por `Deny-Outbound-Prod-192` (P500).

---

## 2026-07-10 14:25 — Creación de regla Allow-AADDS-Outbound

**Comando:** CX-03 — Crear Allow-AADDS-Outbound en sfdev02-nsg
**Resultado:**
```
name: Allow-AADDS-Outbound
priority: 101
access: Allow
protocol: *
destinationAddressPrefixes: [192.168.40.4, 192.168.40.5]
destinationPortRanges: [88, 389, 636, 53, 445]
provisioningState: Succeeded
```
**Observación:** Se ha creado la regla en P101. Se solicitó P90 pero P100 ya estaba en uso. Puertos iniciales: 88, 389, 636, 53, 445.

---

## 2026-07-10 14:40 — Timeout con puertos específicos — actualización a wildcard

**Comando:** CX-04 — Actualizar Allow-AADDS-Outbound a puerto wildcard
**Resultado:**
```
destinationPortRanges: [*]
provisioningState: Succeeded
```
**Observación:** Se ha actualizado la regla a puerto `*` hacia los DC. Los puertos específicos generaron timeout en la autenticación NLA, confirmando uso de puertos dinámicos RPC por parte de Kerberos en este entorno.

---

## 2026-07-10 14:50 — Documentación estado completo NSG sfdev02-nsg

**Comando:** CX-05 / CX-06 — Estado NSG outbound e inbound
**Resultado:**

Outbound:
```
P     Name                       Access  Proto  Source  Dest                       DestPort
100   Allow-Outbound-strgsqlbkp  Allow   *      *       192.168.50.17/32           443,445
101   Allow-AADDS-Outbound       Allow   *      *       192.168.40.4,192.168.40.5  *
500   Deny-Outbound-Prod-192     Deny    *      *       192.168.0.0/16             *
501   Deny-Outbound-Prod-10      Deny    *      *       10.0.0.0/16                *
1000  Subredes_out               Allow   *      *       *                          *
```

Inbound:
```
P    Name                     Access  Proto  Source       SourcePort  Dest        DestPort
300  RDP                      Allow   TCP    *            *           *           3389
310  ClubSite_Test02_9443     Allow   *      *            *           *           9443
320  MobileApp_803            Allow   *      *            *           *           803
321  MobileApp_843_HTPS       Allow   TCP    *            *           *           843
330  WebService_804           Allow   *      *            *           *           804,802,805
340  ClubSite_Test02_9080     Allow   *      *            *           *           9080
350  Port_80                  Allow   *      *            *           10.2.0.5    80,22,443
360  Port_443                 Allow   *      *            *           *           443
370  Port_8080                Allow   *      *            *           *           8080
380  Port_4430                Allow   *      *            *           *           4430
390  Port_8081                Allow   *      *            *           *           8081,8082,8184
400  Subredes                 Allow   *      10.2.1.0/24  *           10.2.0.0/24 *
410  Port_SQL                 Allow   TCP    *            *           *           1433
420  Entorno_DEV              Allow   *      *            *           *           7443,700,701,702,703,704
430  AllowWebserviceV2Prepro  Allow   *      *            *           *           8181,8182,8183,8184,8185
440  AllowAnyRDPInbound       Allow   TCP    *            *           10.3.0.4    3389
600  dev-keycloak-http        Allow   *      *            *           10.0.2.5    8080
610  dev-keycloak-https       Allow   TCP    *            *           *           8443
```
**Observación:** Se ha verificado que `Allow-AADDS-Outbound` (P101) precede a `Deny-Outbound-Prod-192` (P500). Las reglas `Port_*` de inbound corresponden a acceso internet legítimo a aplicaciones IIS. `Allow-Outbound-strgsqlbkp` (P100) confirmado como punto de montaje cross-RG para backup SQL/storage.
