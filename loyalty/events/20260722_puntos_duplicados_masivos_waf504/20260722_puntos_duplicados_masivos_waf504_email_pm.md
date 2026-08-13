**Asunto:** Cierre de incidente — Duplicación de puntos en campaña de premios (22/07/2026)

Hola equipo,

Les escribo para informarles el cierre del incidente de duplicación de puntos detectado hoy, 22/07/2026, durante la campaña de premios a socios ganadores de Club Grido.

**¿Qué pasó?**

Durante la ejecución de la asignación masiva de puntos de la campaña, el sistema devolvió un error de timeout al operador, pero el proceso siguió corriendo del lado del servidor sin que el operador lo supiera. Al ver el error, el operador reintentó la operación varias veces sobre los mismos listados, lo que generó que un grupo de socios recibiera los puntos de la campaña más de una vez.

**Impacto**

La duplicación afectó a 7.940 socios, por un total de 376.450.000 puntos otorgados de más entre las cuatro listas de la campaña ("Lista socios ganadores", "Lista 1", "Lista 2" y "Campaña recupero").

**Resolución**

Se decidió revertir el 100% de los puntos otorgados en esas cuatro listas — en lugar de calcular sólo el excedente por socio — y volver a correr la campaña completa desde cero con un método que garantiza que cada socio reciba sus puntos una única vez. Ambos pasos ya se completaron y se verificaron de punta a punta:

- Se retiraron exactamente 376.450.000 puntos duplicados, en 37.645 transacciones, sin ninguna duplicación remanente.
- Se volvió a asignar la campaña correctamente: los 7.940 socios ganadores ya tienen acreditados sus 10.000 puntos correspondientes, verificado uno por uno sin ningún duplicado.

El incidente está cerrado. Los socios ya cuentan con los puntos correctos de la campaña — no se requiere ninguna acción adicional de su parte ni de Grido.

**Próximos pasos**

Estamos evaluando mejoras en la plataforma para que un timeout en asignaciones masivas de puntos no derive en reintentos manuales que dupliquen la operación, de cara a futuras campañas.

Saludos,
Dante
