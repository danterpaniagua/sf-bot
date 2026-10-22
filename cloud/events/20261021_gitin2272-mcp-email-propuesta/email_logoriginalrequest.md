**Asunto:** Platform y Person: aviso "LogOriginalRequest is missing or is set to False" en cada request

Hola a todos,

Estoy evaluando la viabilidad de integrar IA / MCP con Graylog ([GITIN-2272](https://smartit-ar.atlassian.net/browse/GITIN-2272)). Cuantos más falsos positivos haya en los logs, más tokens consume la IA al leerlos. Al revisar los datos de los logs de SmartCloud por nivel llegué a esto: un único aviso concentra casi todos los mensajes por encima de Information. Si el valor que lo provoca es intencional, ese aviso es ruido, y recomiendo fuertemente resolverlo; no es un requisito para seguir con la evaluación.

**Qué pasa**

- En `RequestHandlingMiddleware`, si la configuración `LogOriginalRequest` no existe o está en `False`, se escribe un `Warning`: *"RequestHandlingMiddleware: The setting: \"LogOriginalRequest\" is missing or is set to \"False\". Request info about the PUT, POST and DELETE actions is not being logged."*
- Ese `else` está fuera del chequeo del método HTTP, así que según el código el aviso se escribe en cada request, no solo en PUT, POST y DELETE. Es lo que leí en `main` (`e00e8c467`); asumo que es lo desplegado porque `main` se despliega con GitHub Actions.
- Dónde está en el código (rama `main`, commit `e00e8c467`):
  - `Source/Services/Platform/SmartFran.Cloud.Platform.API/Infrastructure/Extensions/Middlewares/RequestHandlingMiddleware.cs`: lee la configuración en la línea 24, registra el cuerpo a nivel Information en la línea 29 (solo PUT, POST y DELETE) y escribe el `Warning` en la línea 34 (el `else`).
  - `Source/Services/Person/SmartFran.Cloud.Person.API/Infrastructure/Extensions/Middlewares/RequestHandlingMiddleware.cs`: mismas líneas 24, 29 y 34; el cuerpo pasa por `SanitizeRequestBody` (llamada en la línea 29, definición en la línea 72).
- Valor de `LogOriginalRequest` en producción (leído del App Service): `False` en Platform y en Person; `True` en Business, Catalog, Sales y Orders.

**Datos (24 horas del 21/10, un solo día)**

- Platform: 58.986 avisos. Person: 6.922 avisos. En una muestra de unos 1.000 mensajes por servicio repartida en el día, el 100 % de los `Warning` de ambos era este aviso.
- Entre los 8 servicios de aplicación hubo 75.004 mensajes de nivel Warning, Error o Fatal en ese período; estos dos servicios aportan unos 65,9 mil (cerca del 88 %). Que cada aviso corresponda a un request es una inferencia mía a partir del código; no comparé estos conteos con el total de requests de cada API.
- Los servicios con `True` casi no emiten este aviso (Orders 0, Sales 39, Catalog 32 `Warning` en el día).

**Cómo verificarlo en Graylog**

En la búsqueda de Graylog, con rango de 24 horas y el stream `PROD-Platform-AppServicePlan` (o `PROD-Person-AppServicePlan`):

- Solo el aviso: `AppLevel:"Warning" AND message:"LogOriginalRequest"`
- Todo lo demás por encima de Information, sin ese aviso: `AppLevel:("Warning" OR "Error" OR "Fatal") AND NOT message:"LogOriginalRequest"`

La primera debería devolver casi todo lo que devuelve `AppLevel:"Warning"` en esos streams. No probé estas consultas con la búsqueda de texto sobre `message` (el mensaje de esos dos servicios es un JSON serializado); los conteos de este correo salieron de la API por nivel y stream, no de esta consulta.

**Qué recomiendo**

No es un requisito para seguir con la evaluación, pero recomiendo fuertemente resolver este aviso: cada mensaje innecesario es contenido que la IA tiene que leer y consume tokens. Recomiendo confirmar primero si `False` en Platform y Person es intencional (por ejemplo, para no registrar el cuerpo de los requests). Según la respuesta, veo tres caminos, ninguno probado ni decidido, y la decisión es de los líderes técnicos:

1. Poner `LogOriginalRequest` en `True` en producción. Quita el aviso, pero empieza a registrar el cuerpo de cada PUT, POST y DELETE a nivel Information. En Platform el código solo limpia headers, no el cuerpo; en Person el cuerpo pasa por `SanitizeRequestBody` (no leí qué enmascara).
2. Cambiar el código para que el aviso se escriba una sola vez al iniciar la aplicación, o a nivel Debug.
3. Dejar todo como está y descartar ese mensaje en Graylog o Logstash.

Más información: [GITIN-2272](https://smartit-ar.atlassian.net/browse/GITIN-2272)

Saludos,
