**Asunto:** GITIN-2201 — Datos de Desarrollo necesarios para cotizar el envío de comprobantes por correo

Hola,

Estoy evaluando el envío por correo de los comprobantes de venta de SmartCloud (hoy el comprobante de cada venta solo se imprime en el POS) y qué proveedor usar en lugar de SendGrid. **Necesito la información de abajo para cotizar a los proveedores de nube y a los proveedores de correo**: el precio del correo depende de la cantidad de envíos y del peso de lo que se envía, y el precio de la nube (almacenamiento y cómputo para generar los comprobantes) depende del tamaño y de cuánto tiempo hay que guardarlos. Hoy esos datos no están medidos.

El volumen que uso es de unos 11,8 millones de comprobantes por mes en el mes pico. Como referencia, SmartFran onprem envía PDF de 17 a 50 KB por Sendinblue (Brevo).

**Qué necesito saber**

1. Mi recomendación es que el POS no tenga la responsabilidad del envío: que el flujo de la venta publique los datos del comprobante en una cola y que otro proceso, por ejemplo una Azure Function, la consuma, genere el comprobante y lo envíe. ¿En qué momento de la venta publicarían el mensaje y qué llevaría? ¿Qué componente genera el comprobante que se envía, con qué plantilla y en qué formato?
2. ¿Cuánto pesa un comprobante en la nube? ¿Es el mismo formato que usa SmartFran onprem? Les pediría, si pueden, el tamaño de un comprobante real (con QR, sin adjuntos) de una venta chica y de una grande, con el promedio y el máximo.
3. ¿Hay que guardar una copia del comprobante que se envía al cliente? En caso afirmativo, ¿qué se guardaría y dónde? ¿Hay que guardar también un registro de cada envío?
4. ¿Durante cuánto tiempo hay que guardarlo?
5. ¿Qué porcentaje de las ventas tiene correo del cliente, y se cuenta con su consentimiento para enviarle el comprobante?

Con sus respuestas ajusto el volumen, los tamaños y la retención en las cotizaciones de los proveedores de correo y de nube. Si alguna requiere más tiempo, avísenme cuál y lo vemos; puedo avanzar con las demás.

Más información: [GITIN-2201](https://smartit-ar.atlassian.net/browse/GITIN-2201)

Saludos,
Dante
