# OPS — Certificado SSL Revocado — ClubSiteG2 (clubgrido.com.py)

## Resumen

El 16 de junio de 2026 se detectó que el servicio ClubSiteG2 publicado en IIS bajo el dominio `clubgrido.com.py` presenta el error `net::ERR_CERT_REVOKED` en navegadores. El certificado SSL emitido por RapidSSL TLS RSA CA G1 (DigiCert) está activo y no expirado (vence el 8 de enero de 2027), pero fue revocado por la autoridad certificante antes de su vencimiento natural. El servicio web es inaccesible para todos los usuarios finales vía HTTPS. El impacto es total sobre la disponibilidad pública de ClubSiteG2.

## Tabla resumen

| Campo | Valor |
|---|---|
| ID alerta | — |
| Sistema | ClubSiteG2 — IIS — `clubgrido.com.py` |
| Severidad | Crítica |
| Detectado | 2026-06-16 |
| Resuelto | Pendiente |
| Responsable | Dante Paniagua |

## Causa raíz

El certificado SSL del dominio `clubgrido.com.py` (serial `03BE1BE3DA6F7728D86370C479213CB9`, emitido por RapidSSL TLS RSA CA G1) fue revocado por la autoridad certificante. La revocación fue confirmada vía OCSP el 17-06-2026 a las 04:03 UTC (C1). El error `ERR_CERT_REVOKED` en navegadores es legítimo y refleja el estado real del certificado.

El motivo de la revocación no está disponible en la respuesta OCSP (los BR §7.3.2 prohíben incluir `reasonCode` en OCSP). El motivo exacto debe obtenerse de la CRL (C6) o del portal DigiCert. El motivo determina si la clave privada está comprometida y si puede reutilizarse en el certificado de reemplazo.

## Hallazgos

| # | Hallazgo | Riesgo |
|---|---|---|
| H1 | Certificado `clubgrido.com.py` revocado por DigiCert/RapidSSL — servicio ClubSiteG2 inaccesible vía HTTPS | Alto |
| H2 | El certificado fue emitido el 09-01-2026 y vence el 08-01-2027 — la revocación ocurrió durante el ciclo de vida activo | Alto |
| H3 | La causa de la revocación es desconocida — puede indicar compromiso de clave privada | Alto |
| H4 | Si la clave privada fue comprometida, reutilizarla en un nuevo certificado es un riesgo de seguridad | Alto |
| H5 | No se ha evaluado si otros servicios desplegados utilizan este mismo certificado o clave privada — el impacto puede extenderse más allá de ClubSiteG2 | Alto |

## Recursos afectados

| Recurso | Tipo | Detalle |
|---|---|---|
| `clubgrido.com.py` | Dominio / Certificado SSL | Certificado revocado — `ERR_CERT_REVOKED` |
| `www.clubgrido.com.py` | SAN incluido en el certificado | Igualmente inaccesible |
| ClubSiteG2 | Servicio IIS | Inaccesible vía HTTPS mientras el certificado revocado esté vinculado |

## Comandos ejecutados

| # | Comando / Script | Propósito |
|---|---|---|
| C1 | `ocsp-check` | Verificar estado de revocación del certificado vía OCSP contra RapidSSL |
| C2 | `serial-decode` | Decodificar número de serie del certificado para referencia con DigiCert |
| C3 | `san-check` | Confirmar que el certificado cubre `www.clubgrido.com.py` en sus SANs |
| C4 | `live-tls-check` | Verificar qué certificado está sirviendo IIS en `www.clubgrido.com.py` |
| C5 | `ocsp-stapling-check` | Verificar si IIS sirve un OCSP staple válido en la conexión TLS |
| C6 | `crl-check` | Descargar la CRL de RapidSSL y buscar el serial — confirmar si figura como revocado a nivel de CA |

Ver: `20260616_clubsite_cert_revocado_scripts.sh`

## Acciones propuestas

1. **Verificar el estado de revocación via OCSP** (C1 en scripts) — confirmar que la revocación está activa y obtener el `revocationReason` reportado por el servidor OCSP de RapidSSL.
2. **Consultar el portal DigiCert** con el número de serie `03be1be3da6f7728d863700c479213cb9` — determinar quién solicitó la revocación y el motivo declarado.
3. **Evaluar impacto en servicios desplegados** — auditar todos los sitios y servicios IIS en el entorno para identificar cualquier binding HTTPS que utilice el mismo certificado (`clubgrido.com.py`) o la misma clave privada. Los SAN del certificado cubren `clubgrido.com.py` y `www.clubgrido.com.py`; verificar que no haya otros servicios vinculados. Si el motivo de revocación es `keyCompromise`, todos los servicios que operan con esa clave privada están comprometidos y deben cesar el uso inmediatamente.
4. **Evaluar compromiso de clave privada** — si el motivo es `keyCompromise`, la clave privada actual no debe reutilizarse bajo ningún concepto. Generar un nuevo par de claves antes de emitir el certificado de reemplazo.
5. **Emitir certificado de reemplazo** vía DigiCert/RapidSSL con el mismo dominio `clubgrido.com.py` y `www.clubgrido.com.py` — usar CSR generado con clave nueva si corresponde.
6. **Vincular el nuevo certificado en IIS** sobre el binding HTTPS del sitio ClubSiteG2 y verificar accesibilidad del servicio.

## Hallazgos secundarios

**Obligaciones del suscriptor bajo CA/Browser Forum Baseline Requirements v2.2.8 (§9.6.3)**

Al detectar la revocación de este certificado, aplican las siguientes obligaciones contractuales del suscriptor derivadas del Subscriber Agreement con DigiCert/RapidSSL, las cuales están alineadas con los Baseline Requirements del CA/B Forum:

| Obligación | Sección BR | Descripción |
|---|---|---|
| Cese inmediato de uso | §9.6.3 — Reporting and Revocation | El suscriptor DEBE cesar el uso del certificado y de la clave privada asociada ante cualquier sospecha de compromiso de clave. La revocación por `keyCompromise` activa esta obligación de forma inmediata. |
| Cese de uso de clave privada | §9.6.3 — Termination of Use | Ante una revocación por `keyCompromise`, el suscriptor DEBE cesar todo uso de la clave privada correspondiente, incluyendo cualquier otro servicio que la utilice. |
| Responsividad | §9.6.3 — Responsiveness | El suscriptor tiene la obligación de responder a instrucciones de la CA relativas a compromiso de clave dentro del plazo especificado en el Subscriber Agreement. |
| Protección de clave privada | §9.6.3 — Protection of Private Key | El suscriptor debe mantener el control exclusivo de la clave privada. Si la clave fue comprometida, esto constituye una violación de las obligaciones del suscriptor. |

La CA (DigiCert/RapidSSL) ya cumplió su obligación bajo §4.9.1.1: revocar dentro de las 24 horas para `keyCompromise` o dentro de los 5 días para otros motivos. La obligación de acción ahora recae sobre el suscriptor.

**Reducción progresiva de vigencia de certificados SSL — CA/B Forum BR §6.3.2**

El certificado revocado fue emitido el 09-01-2026 con vigencia de 364 días, válido bajo las reglas previas al 15-03-2026 (máximo 398 días). El certificado de reemplazo que se emita hoy queda sujeto al nuevo límite en vigor:

| Emitido desde | Emitido antes de | Vigencia máxima |
|---|---|---|
| — | 2026-03-15 | 398 días |
| **2026-03-15** | 2027-03-15 | **200 días** |
| 2027-03-15 | 2029-03-15 | 100 días |
| 2029-03-15 | — | 47 días |

Un certificado emitido el 16-06-2026 vencerá como máximo el ~02-01-2027 (200 días). A partir de marzo de 2027 el límite baja a 100 días, y a partir de marzo de 2029 a 47 días. La renovación manual no es sostenible en ciclos de 47 días. Se recomienda evaluar automatización vía ACME (DigiCert CertCentral o equivalente) antes del próximo ciclo de renovación.
