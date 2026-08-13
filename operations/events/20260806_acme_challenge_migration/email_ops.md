Asunto: Renovación de MobileAppService completamente automatizada — GITIN-1774

Hola equipo,

Les cuento que terminamos la automatización definitiva de la renovación del certificado SSL de MobileAppService (GITIN-1774, dentro de la historia GITIN-1768).

Hasta ahora, la renovación dependía de un paso manual (agregar un registro TXT en GoDaddy cada vez), porque la cuenta de GoDaddy no tiene habilitado el acceso a su API de Domains. Lo que hicimos fue delegar únicamente el subdominio `_acme-challenge.mobileservice.clubgrido.com.ar` a una zona de Azure DNS (un solo registro NS agregado en GoDaddy, sin tocar ningún otro registro del dominio), y reconfiguramos win-acme en `SFCG-MOBI-01` y `SFCG-MOBI-02` para validar contra esa zona en vez de depender de GoDaddy.

Verificamos en ambas VMs que la tarea programada corrió sola y terminó exitosamente, sin ningún paso manual, y que el certificado nuevo quedó instalado correctamente (confirmado también contra el endpoint público). Con esto, la renovación queda resuelta de forma definitiva — sin depender de que GoDaddy habilite su API, y sin necesidad de que alguien intervenga cada ciclo.

Quedan dos puntos pendientes, no urgentes: confirmar un ciclo de renovación real (no forzado) más cerca de noviembre, y guardar el client secret del Service Principal en un gestor de secretos formal (por ahora está guardado fuera del repo, pero sin un lugar específico documentado).

También evaluamos si este mismo mecanismo se puede reutilizar para los otros servicios de la misma historia (ClubSite AR/PY, WebSite) — esos tres tienen su propio bloqueador (sus certificados no están integrados con Azure Key Vault) antes de que esto solo alcance para automatizarlos.

El detalle completo está en el ticket GITIN-1774.

Saludos,
Dante
