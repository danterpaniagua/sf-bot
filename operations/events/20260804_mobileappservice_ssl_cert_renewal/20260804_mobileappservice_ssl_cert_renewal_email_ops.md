Asunto: Renovación del certificado SSL de Mobile — estado de la automatización (GITIN-1786)

Hola equipo,

Les cuento una novedad rápida sobre el certificado SSL de Mobile.

Resolvimos el riesgo de vencimiento inmediato en `SFCG-MOBI-01` y `SFCG-MOBI-02` — ambas VMs tienen certificados nuevos de Let's Encrypt, vigentes hasta 2026-11-02. Esto elimina el ida y vuelta manual que teníamos con Grido para que nos renovaran los certificados — son gratuitos, emitidos por Let's Encrypt, y ahora manejamos nosotros mismos el proceso de renovación.

Cada VM corre una verificación diaria de renovación (win-acme); renueva automáticamente el certificado cuando se acerca a su vencimiento — confirmado funcionando de forma confiable en ambos nodos.

Desafíos

La parte completamente desatendida todavía no está cerrada. Nos topamos con una restricción a nivel de cuenta en GoDaddy — el acceso a su API de Domains está denegado para nuestra cuenta, lo que bloquea el plugin de validación DNS que necesita win-acme para renovar automáticamente. Los certificados actuales se emitieron con un paso manual de validación DNS, a modo de solución temporal, por lo que la próxima renovación programada (2026-09-28) va a fallar si no avanzamos antes con el trabajo pendiente.

Plan para cerrar esta brecha: delegar el subdominio `_acme-challenge` a una zona de Azure DNS (un único registro NS manual en GoDaddy) y pasar al plugin de Azure DNS de win-acme — evita por completo la restricción de GoDaddy. Necesitamos tenerlo resuelto antes del 2026-09-28.

Próximos pasos

Analizar la factibilidad de extender esto al resto de los servicios que están detrás del WAF de Azure.

Saludos,
Dante
