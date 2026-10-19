**Asunto:** GITIN-2209 — Espacio de logs de SmartCloud: SmartPedidos reintenta en exceso cuando MercadoPago rechaza un acceso

Hola,

El almacenamiento donde SmartCloud guarda sus registros (logs) estaba cerca de agotarse. Ya lo ampliamos (pasó del 89% al 60% de uso), pero la causa del aumento sigue activa, así que con estos números ese espacio volvería a agotarse. Como el lunes 12 es feriado, queremos avanzar antes del fin de semana largo o a primera hora del martes.

**Qué encontramos**

- Desde la noche del 7 de octubre, el servicio Business de SmartCloud en producción registra unas 26 veces más mensajes que lo habitual. Casi todo viene de consultas repetidas para renovar el acceso de cuentas de billetera de MercadoPago, que MercadoPago rechaza (respuesta de autorización inválida). En una muestra de unos 40 segundos fallaban 2 cuentas, de las 5 que usan esta función.
- SmartPedidos reintenta demasiado cuando eso falla. Según lo que revisamos del código del Concentrador y de Platform, cuando SmartCloud no entrega el acceso, no lo recuerdan y vuelven a pedirlo en la consulta siguiente, sin esperar. Como varias sucursales comparten una misma cuenta, una sola cuenta rechazada genera muchísimas consultas, unas 8,8 por segundo, de día y de noche. Todavía no confirmamos cuál de los dos servicios hace la mayor parte de las consultas.
- No sabemos por qué MercadoPago rechaza esas renovaciones (por ejemplo, cuenta desvinculada o autorización revocada), ni si algo cambió en SmartPedidos alrededor de las 22:30 del 7 de octubre.

**Cuánto tiempo da el espacio ampliado**

- Es una estimación: según el ritmo de ingreso (entre 24 y unos 40 GB por día), el espacio ampliado alcanzaría para entre una y dos semanas, es decir, aproximadamente hasta entre el 15 y el 21 de octubre. El volumen siguió subiendo en los últimos días, así que podría ser menos.
- Si se llena, con la configuración por defecto (que no verificamos en el sistema), el sistema de logs dejaría de guardar mensajes nuevos hasta que se libere espacio.

**Próximos pasos**

- Necesitamos identificar a los titulares de esas 2 cuentas de MercadoPago para que vuelvan a autorizar la vinculación (y verificar las otras 3). ¿Podrían ayudarnos con el contacto antes del feriado o el martes a primera hora?
- Proponemos coordinar con Desarrollo de SmartPedidos que el Concentrador y Platform esperen y reintenten con pausas crecientes cuando no consiguen el acceso de una cuenta, y con Desarrollo de SmartCloud un ajuste equivalente en Business. Está propuesto, todavía no decidido.

Más información: [GITIN-2209](https://smartit-ar.atlassian.net/browse/GITIN-2209)

Saludos,
Dante
