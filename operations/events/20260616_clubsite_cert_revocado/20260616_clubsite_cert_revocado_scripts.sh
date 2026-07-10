#!/usr/bin/env bash
# Event: 20260616_clubsite_cert_revocado
# Domain: clubgrido.com.py
# Cert serial: 03BE1BE3DA6F7728D86370C479213CB9
# Issuer: RapidSSL TLS RSA CA G1 (DigiCert)
#
# OUTPUT format: executed commands record their results as commented blocks
# immediately below the command, tagged with date.

# === SETUP ===

# C0 — save-pems
# Save leaf and intermediate certificates to disk before running any other command.
cat > /tmp/clubgrido_leaf.pem << 'EOF'
-----BEGIN CERTIFICATE-----
MIIGKzCCBROgAwIBAgIQA74b49pvdyjYY3DEeSE8uTANBgkqhkiG9w0BAQsFADBg
MQswCQYDVQQGEwJVUzEVMBMGA1UEChMMRGlnaUNlcnQgSW5jMRkwFwYDVQQLExB3
d3cuZGlnaWNlcnQuY29tMR8wHQYDVQQDExZSYXBpZFNTTCBUTFMgUlNBIENBIEcx
MB4XDTI2MDEwOTAwMDAwMFoXDTI3MDEwODIzNTk1OVowGzEZMBcGA1UEAxMQY2x1
YmdyaWRvLmNvbS5weTCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAOg8
QGC1+pPd1FQgZtegRxlQ9T9A6Hl0lYe0cEOoh8F1LBHnlqvCRPP/f9JpoT9dOlWp
J66CRGnsiwNPKcxiku9LEDd33kK7u2RDrMVsbaRy1lvMqSN1c9/lCOaBr4EWwp/q
8fDSCXtBMnjVGpptaSH1H8dZi8B5g84DvjXPRuYfQtSFW15ejetxfhWGYhasxPqD
dyl4pB8sGyvjcahJeaPIjYD67NsRIHkRUNeEFKvme+b4vx4DkzJNZL5cdx+yssqM
tfObu9FFGs3Pht/N0G7JqmsNBe2G/1IrNPZ5eePxUl9aV4GYVKJEKXPqEfZsTrZz
rVXtLaOpi7hb6gLGaa8CAwEAAaOCAyQwggMgMB8GA1UdIwQYMBaAFAzbbIJJD0pn
CrgU7nrESFKI61Y4MB0GA1UdDgQWBBRwOmFw8i7iaGnWz8iAlxxn2tFgTDAxBgNV
HREEKjAoghBjbHViZ3JpZG8uY29tLnB5ghR3d3cuY2x1YmdyaWRvLmNvbS5weTA+
BgNVHSAENzA1MDMGBmeBDAECATApMCcGCCsGAQUFBwIBFhtodHRwOi8vd3d3LmRp
Z2ljZXJ0LmNvbS9DUFMwDgYDVR0PAQH/BAQDAgWgMBMGA1UdJQQMMAoGCCsGAQUF
BwMBMD8GA1UdHwQ4MDYwNKAyoDCGLmh0dHA6Ly9jZHAucmFwaWRzc2wuY29tL1Jh
cGlkU1NMVExTUlNBQ0FHMS5jcmwwdgYIKwYBBQUHAQEEajBoMCYGCCsGAQUFBzAB
hhpodHRwOi8vc3RhdHVzLnJhcGlkc3NsLmNvbTA+BggrBgEFBQcwAoYyaHR0cDov
L2NhY2VydHMucmFwaWRzc2wuY29tL1JhcGlkU1NMVExTUlNBQ0FHMS5jcnQwDAYD
VR0TAQH/BAIwADCCAX0GCisGAQQB1nkCBAIEggFtBIIBaQFnAHYATGPcmOWcHauI
9h6KPd6uj6tEozd7X5uUw/uhnPzBviYAAAGbo6U0QAAABAMARzBFAiEAi1oUxUdc
txW5Lx4z374P+0Fox4cXZCLAd8gElZ1Lu7UCIDmMV3DWrFQxQQskogu7BUtbriho
nwOhgZhQ/F82aZH8AHUAHJ9oLOn68EVpUPgbloqH3dsyENhM5siy44JSSsTPWZ8A
AAGbo6U0XwAABAMARjBEAiAG82T44ZURWzKaFgRuuYCSgcR/bKDpEmiT3lE+YDEB
vwIgNNQmrWMplOLTAcqXvL8HwGBLnZc8naIoZhtU0DtIWRIAdgBgTJqven93XwHU
BvySDciZ6wscffjJUhv6+hd3O5eLyQAAAZujpTU0AAAEAwBHMEUCIGtT9D7KWLKQ
GR17hZbcAxu85/5/TBuWaCv/Wk/5ovNKAiEA7FL+PfDAXwQo1F0Yq2wB+upQMcsM
N7CEqzJ9eacvuYowDQYJKoZIhvcNAQELBQADggEBABCYpnK1mMYUNOq88P6tTDE1
cJhwkJS+ioHE7BDbMJOrO86KV5VbZCqMpteXywT75UvQ6kmy161wHOdv6HPUBDX2
AuhZnxovGys0gzNx5kwhcWEOsOjUl/70vsPyggeX85EOh1Wmr+0TKezqqtN9DSPP
p0lbOQMjVqkEvRftHn4aiT27TF44cD8g5mkOgBzBKTPULLmgABeTrdJBX/JLHxCn
IzRjsUCR3/cnjiS34bco7fXNMTmC5H6U5G9ihqNmslcwpEmdDEx0e4/LlafgqSPw
y0LzoMRPyrTOyXbvX/1WsAq7nUwCQ9mLihHv9nxxpFMRUIHvh0lljKVVNAxX/3Y=
-----END CERTIFICATE-----
EOF

cat > /tmp/clubgrido_int.pem << 'EOF'
-----BEGIN CERTIFICATE-----
MIIEszCCA5ugAwIBAgIQCyWUIs7ZgSoVoE6ZUooO+jANBgkqhkiG9w0BAQsFADBh
MQswCQYDVQQGEwJVUzEVMBMGA1UEChMMRGlnaUNlcnQgSW5jMRkwFwYDVQQLExB3
d3cuZGlnaWNlcnQuY29tMSAwHgYDVQQDExdEaWdpQ2VydCBHbG9iYWwgUm9vdCBH
MjAeFw0xNzExMDIxMjI0MzNaFw0yNzExMDIxMjI0MzNaMGAxCzAJBgNVBAYTAlVT
MRUwEwYDVQQKEwxEaWdpQ2VydCBJbmMxGTAXBgNVBAsTEHd3dy5kaWdpY2VydC5j
b20xHzAdBgNVBAMTFlJhcGlkU1NMIFRMUyBSU0EgQ0EgRzEwggEiMA0GCSqGSIb3
DQEBAQUAA4IBDwAwggEKAoIBAQC/uVklRBI1FuJdUEkFCuDL/I3aJQiaZ6aibRHj
ap/ap9zy1aYNrphe7YcaNwMoPsZvXDR+hNJOo9gbgOYVTPq8gXc84I75YKOHiVA4
NrJJQZ6p2sJQyqx60HkEIjzIN+1LQLfXTlpuznToOa1hyTD0yyitFyOYwURM+/CI
8FNFMpBhw22hpeAQkOOLmsqT5QZJYeik7qlvn8gfD+XdDnk3kkuuu0eG+vuyrSGr
5uX5LRhFWlv1zFQDch/EKmd163m6z/ycx/qLa9zyvILc7cQpb+k7TLra9WE17YPS
n9ANjG+ECo9PDW3N9lwhKQCNvw1gGoguyCQu7HE7BnW8eSSFAgMBAAGjggFmMIIB
YjAdBgNVHQ4EFgQUDNtsgkkPSmcKuBTuesRIUojrVjgwHwYDVR0jBBgwFoAUTiJU
IBiV5uNu5g/6+rkS7QYXjzkwDgYDVR0PAQH/BAQDAgGGMB0GA1UdJQQWMBQGCCsG
AQUFBwMBBggrBgEFBQcDAjASBgNVHRMBAf8ECDAGAQH/AgEAMDQGCCsGAQUFBwEB
BCgwJjAkBggrBgEFBQcwAYYYaHR0cDovL29jc3AuZGlnaWNlcnQuY29tMEIGA1Ud
HwQ7MDkwN6A1oDOGMWh0dHA6Ly9jcmwzLmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydEds
b2JhbFJvb3RHMi5jcmwwYwYDVR0gBFwwWjA3BglghkgBhv1sAQEwKjAoBggrBgEF
BQcCARYcaHR0cHM6Ly93d3cuZGlnaWNlcnQuY29tL0NQUzALBglghkgBhv1sAQIw
CAYGZ4EMAQIBMAgGBmeBDAECAjANBgkqhkiG9w0BAQsFAAOCAQEAGUSlOb4K3Wtm
SlbmE50UYBHXM0SKXPqHMzk6XQUpCheF/4qU8aOhajsyRQFDV1ih/uPIg7YHRtFi
CTq4G+zb43X1T77nJgSOI9pq/TqCwtukZ7u9VLL3JAq3Wdy2moKLvvC8tVmRzkAe
0xQCkRKIjbBG80MSyDX/R4uYgj6ZiNT/Zg6GI6RofgqgpDdssLc0XIRQEotxIZcK
zP3pGJ9FCbMHmMLLyuBd+uCWvVcF2ogYAawufChS/PT61D9rqzPRS5I2uqa3tmIT
44JhJgWhBnFMb7AGQkvNq9KNS9dd3GWc17H/dXa1enoxzWjE0hBdFjxPhUb0W3wi
8o34/m8Fxw==
-----END CERTIFICATE-----
EOF

# OUTPUT (2026-06-17):
#   serial=03BE1BE3DA6F7728D86370C479213CB9 subject=CN=clubgrido.com.py
#   notBefore=Jan 9 00:00:00 2026 GMT  notAfter=Jan 8 23:59:59 2027 GMT
#   Files verified OK: clubgrido_leaf.pem (2.2K) clubgrido_int.pem (1.7K) rapidssl_issuer.crt (1.2K)

# === INVESTIGATION ===

# C1 — ocsp-check
# Verify revocation status of the leaf certificate via OCSP.
curl -s http://cacerts.rapidssl.com/RapidSSLTLSRSACAG1.crt -o /tmp/rapidssl_issuer.crt
openssl ocsp \
  -issuer /tmp/rapidssl_issuer.crt \
  -cert /tmp/clubgrido_leaf.pem \
  -url http://status.rapidssl.com \
  -text \
  -noverify 2>&1 | grep -E "Cert Status|revocation|Reason|This Update|Next Update"

# OUTPUT (2026-06-17):
#   Cert Status: revoked
#   This Update: Jun 17 04:03:00 2026 GMT
#   Next Update: Jun 24 03:03:00 2026 GMT
#   → Revocation confirmed at CA level. ERR_CERT_REVOKED is legitimate.
#   → Revocation reason not present in OCSP (BR §7.3.2 prohibits reasonCode in OCSP). Check CRL (C6).

# C2 — serial-decode
# Decode the certificate serial number from the PEM for use with DigiCert support.
openssl x509 -in /tmp/clubgrido_leaf.pem -noout -serial -subject -dates

# === AUDIT ===

# C3 — san-check
# Confirm the certificate covers www.clubgrido.com.py (SAN validation).
openssl x509 -in /tmp/clubgrido_leaf.pem -noout -text | grep -A5 "Subject Alternative Name"

# C4 — live-tls-check
# Verify which certificate IIS is currently serving on www.clubgrido.com.py.
openssl s_client -connect www.clubgrido.com.py:443 -servername www.clubgrido.com.py 2>/dev/null \
  | openssl x509 -noout -serial -subject -dates

# C5 — ocsp-stapling-check
# Check if IIS is providing a valid OCSP stapled response.
openssl s_client -connect www.clubgrido.com.py:443 -servername www.clubgrido.com.py -status 2>&1 \
  | grep -E "OCSP Response Status|Cert Status|revok|Next Update"

# C6 — crl-check
# Download the CRL and search for the certificate serial number to obtain revocation reason.
curl -s http://cdp.rapidssl.com/RapidSSLTLSRSACAG1.crl -o /tmp/rapidssl.crl && \
openssl crl -in /tmp/rapidssl.crl -inform DER -text -noout \
  | grep -A5 -i "03be1be3"

# C7 — cert-details
# Full certificate details including CRL/OCSP extension URLs.
openssl x509 -in /tmp/clubgrido_leaf.pem -noout -text | grep -A3 -E "CRL|OCSP|Revocation"

# === REMEDIATION ===

# ⚠️ Generate new private key (run only if key compromise is confirmed or suspected)
# openssl genrsa -out /tmp/clubgrido_new.key 2048

# ⚠️ Generate new CSR with SANs for clubgrido.com.py and www.clubgrido.com.py
# openssl req -new -key /tmp/clubgrido_new.key \
#   -subj "/CN=clubgrido.com.py" \
#   -addext "subjectAltName=DNS:clubgrido.com.py,DNS:www.clubgrido.com.py" \
#   -out /tmp/clubgrido_new.csr
# cat /tmp/clubgrido_new.csr
