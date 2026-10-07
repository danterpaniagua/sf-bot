Asunto: Picos de CPU en Concentrador — en seguimiento

Hola,

Les cuento sobre un evento que estamos monitoreando desde hoy, 29/08.

Desde aproximadamente las 10:00 (hora local), nuestro monitoreo detectó varios picos puntuales de uso de CPU en Concentrador, el sistema interno que conecta los pedidos con las terminales POS de las sucursales. No se registraron caídas ni reinicios del servicio durante estos picos.

De forma proactiva, para prevenir una posible interrupción del servicio, escalamos la capacidad de los servidores de Concentrador mientras confirmamos que los picos no se repitan.

La causa todavía está en investigación. Hay un antecedente de un incidente similar (GITIN-1783, 05/08) asociado a una lentitud puntual de una integración externa con una plataforma de delivery, pero todavía no confirmamos si este evento tiene el mismo origen.

Seguimos monitoreando Concentrador tras el cambio de capacidad para confirmar que el problema no se repita.

Para más información, el ticket es GITIN-1964.

Saludos,
Dante
