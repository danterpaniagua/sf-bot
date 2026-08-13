Asunto: Factibilidad de extender la automatización de certificados SSL a los servicios detrás del WAF (GITIN-1768)

Hola equipo,

Les comparto el estado del análisis para extender la automatización de renovación de certificados SSL —la que implementamos para Mobile, ver GITIN-1786— a los servicios que están detrás del Application Gateway/WAF (`WAF_APPs`): ClubSite (AR y PY) y WebSite (`gestion.clubgrido.com.ar`).

La topología acá es distinta a la de Mobile: al estar detrás de un WAF, el certificado SSL se termina en el propio Application Gateway, no en cada servidor backend — hay un certificado por listener, no uno por VM.

Hallazgo principal: ninguno de los certificados actuales en `WAF_APPs` está integrado con Azure Key Vault — los 9 objetos de certificado presentes son todos PFX cargados directamente. Esto significa que extender la automatización acá requiere, como mínimo, migrar los certificados a una referencia de Key Vault (cambio único por listener; luego cada renovación sería solo publicar una nueva versión del secreto) o, alternativamente, automatizar la carga directa del PFX al gateway en cada renovación.

Hallazgo secundario: encontramos 9 objetos de certificado cargados en el gateway para, como máximo, 3 listeners activos — nombres como `website_2023`, `website_2024` o `clubgrido.2023.2024` sugieren certificados de ciclos de renovación manuales anteriores que nunca se limpiaron.

Seguimos con el análisis: falta confirmar qué certificado usa cada listener actualmente, y el proveedor DNS de `clubgrido.com.py`, para saber si aplica el mismo workaround que usamos con GoDaddy en Mobile.

Saludos,
Dante
