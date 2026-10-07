**Asunto:** Incidente TaskOperatorService — ambiente de test, sin impacto a clientes

Les comparto un resumen del incidente detectado el 29/09 en el ambiente de test de SmartLoyalty.

Un problema de conexión a la base de datos en ese ambiente generó un volumen alto de correos de alerta automática hacia los equipos internos de IT y Operaciones — **más de 54.000 correos** en el día del incidente. **No hubo envío de comunicaciones hacia clientes ni exposición de datos de clientes** — el incidente quedó contenido al ambiente de test y a buzones internos.

Como consecuencia del volumen, los buzones internos de IT/Operaciones tuvieron una limitación temporal de recepción de correo, lo que pudo haber demorado otras comunicaciones operativas legítimas durante esa ventana.

El envío se detuvo deshabilitando el servicio afectado en el ambiente de test. Ya se identificó la causa técnica del volumen de correos y está definida la corrección necesaria a nivel de código.

**Próximos pasos:**
- Implementar la corrección para evitar que un futuro problema de conexión vuelva a generar un volumen alto de correos.
- Continuar la investigación sobre qué originó la falla de conexión a la base de datos.

Más información: [GITIN-2126](https://smartit-ar.atlassian.net/browse/GITIN-2126)

Saludos,
