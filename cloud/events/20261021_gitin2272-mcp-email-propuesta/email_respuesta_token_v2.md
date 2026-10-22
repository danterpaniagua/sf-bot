**Asunto:** Re: Habilitar MCP y token por usuario en Graylog

Hola,

Gracias por la respuesta. Sobre los dos puntos, en el estado actual de [GITIN-2272](https://smartit-ar.atlassian.net/browse/GITIN-2272):

- Habilitar el uso de MCP: como comenté en el correo anterior, estoy trabajando en la propuesta. Si tenés dudas sobre el avance, podés consultar ese correo o hablar con Jacqui.
- Habilitar la configuración de token por usuario: es el token de la API de Graylog, que se genera por usuario, no el token del LLM (Claude) que se conectaría al MCP, que es otra credencial y se define aparte, ni un token propio del MCP, que se encuentra en estado experimental. Esta configuración todavía no está habilitada en Graylog, y es lo que estoy analizando debido a su estado experimental. Para poder tener todo levantado, en su momento también voy a necesitar una API key de Graylog de SmartFran, ya sea para la alternativa o para el MCP. Dejo la documentación: [Configure MCP](https://go2docs.graylog.org/current/setting_up_graylog/configure_mcp.htm).

Estoy trabajando en tener esta funcionalidad o una alternativa, según lo planificado con Jacqui, con el objetivo de cumplir los tiempos acordados. Cuando tenga la propuesta la comparto por este medio.

Saludos,
Dante
