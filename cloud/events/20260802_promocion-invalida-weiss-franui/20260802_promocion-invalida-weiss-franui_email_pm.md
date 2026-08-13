Asunto: Ventas rechazadas en WEISS con el descuento "Descuento Influencers" — hipótesis en revisión

Buen día,

Recibimos un pedido de ayuda de Antonella en el grupo de WhatsApp "SC - Soporte Urgencias" por un problema puntual en el POS de WEISS (Punta del Este): algunas ventas que combinan un descuento específico ("Descuento Influencers") con ciertos productos están siendo rechazadas al momento de cobrar, y el cajero debe sacar el producto de la venta para poder cerrarla.

Realizamos varias pruebas y les comparto el estado de la revisión con lo que pudimos detectar hasta ahora.

**Importante: lo que sigue es la hipótesis principal a partir de los datos revisados hasta ahora, no una causa confirmada al 100%.** Todavía falta una confirmación con el área que administra los precios y promociones de WEISS antes de dar esto por cerrado.

Lo que encontramos: el descuento "Descuento Influencers 100%" está pensado para dejar la venta en $0 (un descuento total), pero el valor cargado en el sistema es 99,99%, no 100%. Esa diferencia de apenas una centésima de punto porcentual deja un pequeño saldo sin cobrar en cada venta que usa este descuento — el sistema no acepta cerrar una venta con un saldo pendiente, por mínimo que sea, y la rechaza.

Con datos reales de un caso probado en WEISS:
- 2 hamburguesas + Franui, con el descuento aplicado: el sistema calculó un saldo de **$0,17** y rechazó la venta.
- Las mismas 2 hamburguesas solas (sin Franui), con el mismo descuento: el saldo fue de **$0,14** y la venta sí se aceptó.
- Franui solo, sin el descuento: se vende sin ningún problema — el descuento es la variable que causa el rechazo, no el producto en sí.

Un dato adicional relevante: en algunos productos (los que el sistema arma como "combo") ese pequeño saldo pasa desapercibido y la venta se cierra igual, mientras que en productos individuales sí bloquea el cobro. Esto sugiere que el mismo problema podría estar generando un cobro de menos silencioso en ventas de combo donde no se nota, además del bloqueo visible que motivó este reporte.

**Próximos pasos:**
- Confirmar con el área responsable de precios y promociones de WEISS si el valor configurado para este descuento fue intencional o un error de carga.
- Una vez confirmado, aplicar la corrección correspondiente y validar que las ventas con este descuento se procesen sin inconvenientes.

Quedo disponible ante cualquier consulta.

Saludos,
Dante Paniagua
SRE
