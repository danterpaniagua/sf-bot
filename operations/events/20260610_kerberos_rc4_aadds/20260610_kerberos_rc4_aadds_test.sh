#!/usr/bin/env bash
# Evento: 20260610_kerberos_rc4_aadds
# Plan de pruebas — compatibilidad AES Kerberos en Windows Server 2019 / IIS
# Objetivo: probar que un app pool de IIS usando una cuenta con AES-only (msDS-SupportedEncryptionTypes: 24)
#           autentica correctamente antes de aplicar el cambio sobre itservices.
# ⚠️ Los comandos de acción están marcados con ACTION

# === PREPARACIÓN — cuenta de prueba en Entra ID ===

# T1 — Crear usuario de prueba en Entra ID (se sincroniza a AADDS en ~5 min)
# ⚠️ ACTION — crea un usuario en el tenant de Entra ID
az ad user create \
  --display-name "SVC AES Test" \
  --user-principal-name "svc-aestest@smartit.azure" \
  --password "Aes@Test2026!" \
  --force-change-password-next-sign-in false

# T2 — Verificar que el usuario sincronizó a AADDS
ldapsearch -H ldap://192.168.40.4 \
  -D "SMARTIT\dantep" -W \
  -b "DC=smartit,DC=azure" -x \
  "(sAMAccountName=svc-aestest)" \
  sAMAccountName msDS-SupportedEncryptionTypes distinguishedName

# T3 — Establecer AES-only (valor 24 = AES-128 + AES-256) en la cuenta de prueba
# ⚠️ ACTION — modifica atributo msDS-SupportedEncryptionTypes en svc-aestest
ldapmodify -H ldap://192.168.40.4 \
  -D "SMARTIT\dantep" -W -x << EOF
dn: CN=SVC AES Test,OU=AADDC Users,DC=smartit,DC=azure
changetype: modify
replace: msDS-SupportedEncryptionTypes
msDS-SupportedEncryptionTypes: 24
EOF

# T4 — Confirmar que el atributo se aplicó correctamente
# Resultado esperado: msDS-SupportedEncryptionTypes: 24
ldapsearch -H ldap://192.168.40.4 \
  -D "SMARTIT\dantep" -W \
  -b "DC=smartit,DC=azure" -x \
  "(sAMAccountName=svc-aestest)" \
  sAMAccountName msDS-SupportedEncryptionTypes

# === LIMPIEZA — ejecutar solo después de confirmar resultados de T5–T7 ===

# T8 — Eliminar usuario de prueba de Entra ID
# ⚠️ ACTION — elimina svc-aestest del tenant
az ad user delete --id "svc-aestest@smartit.azure"
