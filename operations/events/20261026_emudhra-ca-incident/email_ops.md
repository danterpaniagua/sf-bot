**Asunto:** Incidente de claves en CA eMudhra: no usamos esa CA en ninguna plataforma

Hola equipo,

Les resumo el incidente de la autoridad certificante eMudhra de estos días y por qué no nos afecta.

**Qué pasó**
- El 17/10 un investigador reportó que las claves privadas de ocho certificados intermedios de eMudhra eran tan débiles que se podían recuperar a partir del certificado público, en menos de un segundo. Con esas claves, un atacante podría emitir certificados falsos que los navegadores aceptarían como válidos ([Help Net Security](https://www.helpnetsecurity.com/2026/10/21/emudhra-certificates-private-keys-compromised/), [Cloudflare](https://blog.cloudflare.com/emudhra-certificate-compromise/)).
- Según eMudhra, un error en un script durante la generación de claves del 30/04/2025 creó un segundo juego de claves más débiles y lo publicó por error ([SecurityWeek](https://www.securityweek.com/browsers-block-emudhra-intermediate-cas-over-recoverable-private-keys/)). Las claves quedaron recuperables unos 17 meses.
- Chrome y Firefox bloquearon los certificados el mismo 17/10, Apple el 19/10 y Microsoft el 20/10. eMudhra los revocó. Dice que las claves raíz no se vieron afectadas y que no encontró evidencia de que los intermedios se usaran para emitir certificados a clientes ([Google](https://blog.google/security/protecting-chrome-and-android-users-from-compromised-emudhra-intermediate-ca-certificates/), [eMudhra](https://emudhra.com/en/post/certificate-security-incident)).
- Mozilla y Chrome avanzan hacia dejar de confiar en una de sus raíces, y eMudhra anunció el 22/10 que se retira del negocio global de certificados SSL/TLS. La causa raíz seguía en análisis según su última actualización.

**Por qué no nos afecta**
Según lo que tenemos relevado, ninguna plataforma usa certificados de eMudhra:
- **SmartLoyalty:** Let's Encrypt en su mayoría y GoDaddy en el resto.
- **SmartPedidos:** certificados por defecto de AWS.
- **SmartCloud:** certificados por defecto de Azure.

Cada una de esas autoridades tiene su propia cadena de confianza, distinta de la de eMudhra. Por eso los certificados que usamos no dependen de las claves comprometidas y no hay nada que revocar ni renovar de nuestro lado.

**Qué vigilar**
Aunque nuestros certificados no son de eMudhra, el incidente puede afectarnos de rebote a través de terceros. Un cliente o un proveedor externo con el que nos conectamos puede tener certificados de eMudhra o una cadena que dependa de ellos. Si alguno falla, el error aparecería de nuestro lado como un problema de conexión TLS (certificado no confiable o revocado), aunque nuestros certificados estén bien.

Recomiendo que, ante cualquier error de certificado o de conexión TLS reportado por un cliente o un proveedor, lo primero sea revisar el emisor del certificado involucrado, antes de buscar el problema en nuestra infraestructura. Si el emisor es eMudhra, el problema viene de ese certificado y no de nuestra configuración. Hoy no hay ningún caso reportado.

**Qué falta revisar**
Esto sale de lo que tenemos relevado por plataforma. No revisé la cadena real de cada endpoint público ni las integraciones con terceros. Recomiendo hacerlo antes de dar el tema por cerrado: confirmar el emisor y la raíz de cada certificado público, y revisar si algún proveedor externo con el que nos conectamos usa un certificado de eMudhra.

Saludos.
