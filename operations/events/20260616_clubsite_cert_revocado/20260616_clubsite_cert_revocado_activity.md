# Actividad — Certificado SSL Revocado — ClubSiteG2 (clubgrido.com.py)

## 2026-06-17 10:05 — Verificación de archivos PEM (C0)

**Comando:** C0 — save-pems
**Resultado:**
```
-rw-rw-r-- 1 dpaniagua dpaniagua 2,2K jun 17 10:05 /tmp/clubgrido_leaf.pem
-rw-rw-r-- 1 dpaniagua dpaniagua 1,7K jun 17 10:05 /tmp/clubgrido_int.pem
-rw-rw-r-- 1 dpaniagua dpaniagua 1,2K jun 17 10:05 /tmp/rapidssl_issuer.crt

serial=03BE1BE3DA6F7728D86370C479213CB9
subject=CN = clubgrido.com.py
notBefore=Jan  9 00:00:00 2026 GMT
notAfter=Jan  8 23:59:59 2027 GMT
```
**Observación:** Archivos PEM guardados correctamente. Certificado válido hasta enero 2027, emitido por RapidSSL TLS RSA CA G1.

---

## 2026-06-17 10:05 — Verificación OCSP (C1)

**Comando:** C1 — ocsp-check
**Resultado:**
```
Cert Status: revoked
This Update: Jun 17 04:03:00 2026 GMT
Next Update: Jun 24 03:03:00 2026 GMT
```
**Observación:** Revocación confirmada a nivel de CA. El error `ERR_CERT_REVOKED` en navegadores es legítimo. El motivo de revocación (`reasonCode`) no está presente en la respuesta OCSP — los BR §7.3.2 lo prohíben. Pendiente ejecutar C6 (CRL) para obtener el motivo.
