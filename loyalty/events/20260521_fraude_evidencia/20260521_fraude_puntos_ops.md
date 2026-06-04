**Asunto:** Investigación — Actividad fraudulenta de puntos, 21 de mayo de 2026

---

Equipo,

Durante la madrugada del 21 de mayo de 2026 (23:00–02:00 hora local) se detectó actividad anómala de transferencias de puntos en SmartFran.Solution.SmartLoyalty. A continuación, los patrones identificados. El detalle completo está en el ticket de Jira y en `events/20260521_fraude_evidencia/`.

**Explotación de transferencia duplicada + incumplimiento de límite diario**
Un emisor ejecutó 4 transferencias por un total de 28.000 puntos en la misma sesión, superando 3,5 veces el límite diario de 8.000 puntos. Dos pares de transferencias a la misma cuenta receptora fueron procesadas con 22 y 35 segundos de diferencia con parámetros idénticos, lo que podría indicar que la plataforma no está validando duplicados en tiempo real.

**Consolidación de puntos en cuenta hub**
La cuenta receptora principal registró un saldo de 36.100 puntos al cierre del evento. De ese total, 24.100 puntos preexistían antes de las transferencias de esta madrugada, lo que sugiere consolidación progresiva de puntos en esa cuenta.

**Redistribución posterior al evento**
Tres cuentas receptoras registraron actividad adicional —canjes o reenvíos— dentro de la misma ventana horaria, luego de recibir los puntos.

**Transferencia circular**
Dos cuentas ejecutaron transferencias recíprocas con 16 minutos de diferencia.

**Patrón de registro sistémico**
Un único registrador (`334C1371-DB4D-C86D-9BBE-08D1B05CD52F`) inscribió 28 de las cuentas emisoras involucradas, distribuidas entre el 27 de diciembre de 2021 y el día de hoy, a través de los canales WEB y APP. Una cuenta fue creada el mismo día del evento.

Dante Paniagua
SRE
