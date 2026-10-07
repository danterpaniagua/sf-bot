Asunto: Escalación de Sales — caídas recurrentes del servicio

Hola,

Les cuento sobre la escalación de ayer en el servicio Sales de SmartFran Cloud.

**Qué pasó**

El servicio Sales tuvo caídas repetidas de su proceso por agotamiento de memoria (18 caídas en la ventana de 48 horas analizada). Grido reportó estas caídas por WhatsApp, coincidiendo con picos de consumo de CPU en Sales — consistente con el patrón ya conocido, donde el consumo de CPU aumenta en los minutos previos a cada caída. Es el mismo patrón identificado a mediados de septiembre: se repite, no es un problema nuevo.

Cada caída hace que el proceso se reinicie; las solicitudes que estaban en curso en ese momento quedan colgadas hasta que expira su propio tiempo de espera, en lugar de devolver un error visible — por eso el impacto no siempre se ve reflejado como errores explícitos en los registros.

**Estado actual del servicio**

Sales corre actualmente en un plan con 3 instancias, con escalado automático entre 1 y 4 según el consumo de CPU. El costo aproximado de este plan, a la capacidad actual, es de USD 3,78 por hora (USD 1,26 por hora por instancia).

**Próximos pasos**

Seguimos monitoreando el servicio.

Saludos,
Dante
