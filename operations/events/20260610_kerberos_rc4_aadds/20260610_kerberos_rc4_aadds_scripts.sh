#!/usr/bin/env bash
# Evento: 20260610_kerberos_rc4_aadds
# Alerta AADDS123 — Kerberos RC4 Encryption Enabled
# Dominio: smartit.azure | Resource Group: DefaultGroup01
# ⚠️ Los comandos de remediación están marcados con ACTION

# === INVESTIGACIÓN ===

# C1 — Localizar resource group del dominio administrado
az resource list \
  --resource-type "Microsoft.AAD/domainServices" \
  --query "[*].{Name:name, ResourceGroup:resourceGroup, Location:location}" \
  --output table

# C2 — Detalle completo del dominio administrado
az ad ds show \
  --name smartit.azure \
  --resource-group DefaultGroup01 \
  --output json

# C3 — Configuración de seguridad del dominio (kerberosRc4Encryption, ntlmV1, tlsV1)
az ad ds show \
  --name smartit.azure \
  --resource-group DefaultGroup01 \
  --query "domainSecuritySettings" \
  --output json

# C4 — Estado del conjunto de réplicas y alertas activas
az ad ds show \
  --name smartit.azure \
  --resource-group DefaultGroup01 \
  --query "replicaSets[*].{Location:location, Vnet:virtualNetworkId, Health:healthLastEvaluated, Alerts:healthAlerts}" \
  --output json

# C5 — Detalle de alertas con URL de resolución
az ad ds show \
  --name smartit.azure \
  --resource-group DefaultGroup01 \
  --query "healthAlerts[*].{ID:id, Name:name, Severity:severity, Raised:raisedDateTime, LastDetected:lastDetectedDateTime, Message:message, ResolutionURL:resolutionUri}" \
  --output json

# === AUDITORÍA ===

# C6 — Cuentas de usuario con bit RC4 explícito (msDS-SupportedEncryptionTypes & 4)
ldapsearch -H ldap://192.168.40.4 \
  -D "SMARTIT\dantep" -W \
  -b "DC=smartit,DC=azure" -x \
  "(&(objectClass=user)(objectCategory=person)(msDS-SupportedEncryptionTypes:1.2.840.113556.1.4.803:=4))" \
  sAMAccountName msDS-SupportedEncryptionTypes

# C7 — Cuentas de usuario sin atributo msDS-SupportedEncryptionTypes (heredan default del dominio)
ldapsearch -H ldap://192.168.40.4 \
  -D "SMARTIT\dantep" -W \
  -b "DC=smartit,DC=azure" -x \
  "(&(objectClass=user)(objectCategory=person)(!(msDS-SupportedEncryptionTypes=*)))" \
  sAMAccountName msDS-SupportedEncryptionTypes

# C8 — Cuentas de equipo con bit RC4 explícito
ldapsearch -H ldap://192.168.40.4 \
  -D "SMARTIT\dantep" -W \
  -b "DC=smartit,DC=azure" -x \
  "(&(objectClass=computer)(msDS-SupportedEncryptionTypes:1.2.840.113556.1.4.803:=4))" \
  sAMAccountName msDS-SupportedEncryptionTypes

# C9 — Cuentas de equipo sin atributo msDS-SupportedEncryptionTypes
ldapsearch -H ldap://192.168.40.4 \
  -D "SMARTIT\dantep" -W \
  -b "DC=smartit,DC=azure" -x \
  "(&(objectClass=computer)(!(msDS-SupportedEncryptionTypes=*)))" \
  sAMAccountName msDS-SupportedEncryptionTypes

# === REMEDIACIÓN ===

# ⚠️ ACTION — C10 — Establecer AES-only en cuenta itservices antes del cambio de dominio
ldapmodify -H ldap://192.168.40.4 \
  -D "SMARTIT\dantep" -W -x << EOF
dn: CN=appaccess,OU=AADDC Users,DC=smartit,DC=azure
changetype: modify
replace: msDS-SupportedEncryptionTypes
msDS-SupportedEncryptionTypes: 24
EOF

# ⚠️ ACTION — C11 — Deshabilitar RC4 en la configuración de seguridad del dominio AADDS
az ad ds update \
  --name smartit.azure \
  --resource-group DefaultGroup01 \
  --domain-security-settings kerberosRc4Encryption=Disabled

# C12 — Verificar que kerberosRc4Encryption figura como Disabled
az ad ds show \
  --name smartit.azure \
  --resource-group DefaultGroup01 \
  --query "domainSecuritySettings" \
  --output json
