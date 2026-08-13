Asunto: CPU alta y reinicios de tareas en concentrador-service / platform-service — GITIN-1783

Hola equipo,

Les paso el cierre del análisis del incidente de CPU alta en concentrador-service y platform-service del 05/08 (ticket GITIN-1783).

Quiero remarcar algo puntual porque creo que es importante para no quedarnos mirando el lugar equivocado: revisamos en detalle el mecanismo de health check y de detención de tareas de ECS/ALB para ambos servicios, y no encontramos ningún problema ahí. concentrador-service no tuvo ni un solo reinicio de tarea durante todo el incidente — su health check ni siquiera llegó a activarse. En platform-service, la configuración del health check y del Target Group está funcionando exactamente como está definida: cuando la carga del proceso supera el umbral configurado, el servicio se reporta a sí mismo como no saludable y ECS reemplaza la tarea. No es un bug en la lógica de detención ni en la configuración del balanceador — es el comportamiento esperado ante una condición real de sobrecarga.

La causa de esa sobrecarga sí la encontramos, y está en otro lado: la API de PediGrido tuvo una degradación/caída parcial durante la misma ventana (respuestas de más de 2 minutos, y varias devolviendo error de gateway). El código de concentrador-service que sincroniza el estado de apertura/cierre con PediGrido no tiene un timeout configurado en esas llamadas, y se ejecuta cada minuto sin ninguna protección contra solapamiento — así que mientras PediGrido estuvo lenta, cada ejecución fue sumando llamadas colgadas sobre las anteriores, sin límite. Eso es lo que generó la presión sostenida de CPU, no el health check en sí.

Para que quede concreto, algunos ejemplos reales de esa ventana: una llamada a `ConfirmarPedido` tardó 218 segundos en responder (con 200 OK) a las 16:49:40 hora local; un lote de llamadas casi simultáneas a `v1/locals/status` tardó alrededor de 138 segundos cada una a las 16:51:18; y más tarde, a las 17:27:06, varias llamadas a ese mismo endpoint directamente devolvieron error 524 (timeout de gateway de Cloudflare, el origen de PediGrido sin responder) recién después de 126 segundos de espera. En total, 475 llamadas a la API de PediGrido durante la ventana del incidente superaron los 40 segundos de duración — sin timeout configurado, cada una de esas llamadas quedó colgada consumiendo un slot hasta que PediGrido (eventualmente) respondió.

Como mitigación durante el incidente escalamos la capacidad (cpu/memoria) de las task definitions de ambos servicios, y después subimos el mínimo de autoescalado de platform-service. Con eso el cuadro se estabilizó ese mismo día.

Actualización de hoy (06/08): revertimos el escalado de cpu/memoria de ambas task definitions a sus revisiones previas al incidente, y también el mínimo de autoescalado de platform-service (volvió de 10 a 5). Ese escalado coincidió con la recuperación de PediGrido, pero nunca fue la corrección real del problema — la causa de fondo sigue siendo la falta de timeout que menciono abajo, y eso todavía no está resuelto. Con esta reversión completa, los dos servicios quedan exactamente como estaban antes del incidente, sin ningún colchón de capacidad. Quiero ser claro: mientras no metamos el timeout y la protección contra solapamiento, un nuevo problema de PediGrido nos puede volver a golpear igual que el 05/08, y esta vez sin ninguna mitigación de respaldo.

Quedan pendientes, del lado de desarrollo, agregar el timeout faltante y la protección contra solapamiento en esa sincronización con PediGrido —esto pasó a ser urgente tras la reversión de hoy—, y de nuestro lado evaluar si vale la pena darle más redundancia a concentrador-service (hoy corre con una sola tarea) y habilitar el logging de health checks del balanceador para tener visibilidad directa a futuro si vuelve a pasar algo similar. También creo que conviene escalar formalmente con PediGrido lo que detectamos de su lado.

Todo el detalle técnico está en el ticket.

Saludos,
Dante
