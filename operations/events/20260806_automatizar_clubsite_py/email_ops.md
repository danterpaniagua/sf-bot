Asunto: Solicitud de registro NS de delegación en clubgrido.com.py — GITIN-1769

Hola Jordan,

Te escribo por la automatización de la renovación del certificado SSL de ClubSite PY (`www.clubgrido.com.py`), ticket GITIN-1769 dentro de la historia GITIN-1768.

Para poder automatizar la renovación necesitamos delegar únicamente el subdominio `_acme-challenge.www.clubgrido.com.py` a una zona de Azure DNS — es el mismo mecanismo que ya implementamos para `clubgrido.com.ar` (MobileAppService y ClubSite AR), sin ningún problema desde entonces.

Esto no afecta ningún otro registro del dominio ni requiere mover la administración de `clubgrido.com.py` a otro lado. Solo necesitamos que agregues un registro NS con estos datos, donde esté administrado hoy el DNS de `clubgrido.com.py`:

- Host: `_acme-challenge.www`
- Tipo: NS
- Valores (los 4, en el orden que permita tu panel):
  - ns1-07.azure-dns.com.
  - ns2-07.azure-dns.net.
  - ns3-07.azure-dns.org.
  - ns4-07.azure-dns.info.

Cualquier duda sobre el panel o el proveedor de DNS, decime y lo vemos juntos. Cuando esté agregado, avisame para verificar que resuelve correctamente y seguir con el resto de la automatización de este lado.

Saludos,
Dante
