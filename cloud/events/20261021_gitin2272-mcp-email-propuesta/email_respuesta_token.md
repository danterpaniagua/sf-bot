**Asunto:** Re: Habilitar MCP y token por usuario en Graylog

Hola,

Gracias por la respuesta. Sobre los dos puntos, en el estado actual de [GITIN-2272](https://smartit-ar.atlassian.net/browse/GITIN-2272):

- Habilitar el uso de MCP: como comenté en el correo anterior, estoy trabajando en la propuesta. Si tenés dudas sobre el avance, podés consultar ese correo o hablar con Jacqui.
- Habilitar la configuración de token por usuario: es un token de Graylog, no un token de un LLM (Claude) para usar el MCP. Es el token de la API de Graylog, que se genera por usuario dentro de Graylog, y no es un token propio del MCP, que se encuentra en estado experimental. Esta configuración todavía no está habilitada en Graylog. Dejo la documentación: [Configure MCP](https://go2docs.graylog.org/current/setting_up_graylog/configure_mcp.htm).

Saludos,
Dante
