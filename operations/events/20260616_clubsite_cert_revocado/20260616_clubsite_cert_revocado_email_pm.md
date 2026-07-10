# Email — PM — Certificado SSL ClubSiteG2 y cambio de vigencia industria

**Para:** [PMs]
**De:** Dante Paniagua
**Asunto:** ClubSiteG2 — Interrupción de servicio HTTPS y cambio regulatorio en certificados SSL

---

Equipo,

Les comento dos puntos relacionados con el servicio ClubSiteG2 (`clubgrido.com.py`).

**Interrupción actual**

El servicio ClubSiteG2 se encuentra inaccesible vía HTTPS desde hoy 16 de junio. El certificado SSL fue revocado por la autoridad certificante (DigiCert/RapidSSL) antes de su fecha de vencimiento. Estamos gestionando el reemplazo del certificado. Les voy a avisar cuando el servicio esté restablecido.

Recomendamos coordinar con el equipo de **CAC (Centro de Atención al Cliente)** para informar a los usuarios afectados sobre la interrupción temporal y el estado de resolución.

**Cambio regulatorio — vigencia de certificados SSL**

A partir del 15 de marzo de 2026, la industria (CA/Browser Forum) redujo la vigencia máxima de los certificados SSL de 13 meses a **200 días**. Esta reducción continuará en los próximos años: 100 días desde marzo de 2027 y 47 días desde marzo de 2029.

Esto impacta directamente en la frecuencia con la que debemos renovar los certificados de todos los servicios web de la plataforma.

**Punto de atención operacional**

Nuestro sistema de monitoreo (Zabbix) genera alertas únicamente basadas en la **fecha de vencimiento** del certificado. Una revocación como la ocurrida hoy no genera ninguna alerta en Zabbix — el sistema no tiene visibilidad sobre ese tipo de evento.

Por este motivo, es necesario realizar una revisión de todos los servicios HTTPS desplegados para validar el estado actual de sus certificados, independientemente de lo que indique el monitoreo.

**Próximos pasos**

- Restablecimiento del servicio ClubSiteG2 con certificado de reemplazo.
- Revisión del estado SSL de todos los servicios web de la plataforma.
- Evaluación de automatización de renovación para adaptarse a los nuevos plazos regulatorios.

Quedo disponible para cualquier consulta.

Dante
