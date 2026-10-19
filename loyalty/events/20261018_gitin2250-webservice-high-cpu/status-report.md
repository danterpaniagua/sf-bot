**Asunto:** Estado GITIN-2250 — CPU alta en el WebService de SmartLoyalty y pico de tráfico en Mobile (2026-10-18)

**Detectado:** Hoy una de las tres instancias del WebService de SmartLoyalty llegó a CPU casi total desde media tarde y volvió a subir tras un reinicio, desde aproximadamente las 17:00 se observan picos en el WebService y en Mobile hubo un pico de tráfico alrededor de las 19:00; ni la saturación de CPU ni el pico de Mobile generaron una alerta.

**Corregido:** Se configuraron alertas de CPU, memoria, disco y estado del WebService con aviso a Chat y Telegram, y se bajó el umbral de ráfagas de Mobile para que un pico como el de hoy sea detectado; todavía no se probó que los avisos nuevos lleguen, porque ninguno se disparó desde su configuración.

**Pendiente:** La causa de la saturación del WebService sigue sin identificarse, falta probar la entrega de las alertas nuevas y verificar que la alerta de disco se vea en todos los servidores.

| Proyecto | Componente | Antes | Después |
|---|---|---|---|
| SmartLoyalty | Alertas de CPU | Los avisos de CPU alta no llegaban a nadie | Tres niveles de aviso (advertencia, promedio, alto) en 14 servidores |
| SmartLoyalty | Alertas de memoria | Sin alerta sobre el uso comprometido de memoria | Tres niveles de aviso en 14 servidores |
| SmartLoyalty | Chequeo de salud del WebService | Sin alerta si el chequeo fallaba | Alerta cuando fallan 3 de los últimos 5 chequeos |
| SmartLoyalty | Alertas de disco | Sin aviso en 13 de 14 servidores | Nivel adicional de aviso al 95 % de uso; visible por ahora en 2 de 14 servidores |
| SmartLoyalty | Umbral de ráfagas de Mobile | 60 peticiones por segundo | 45 peticiones por segundo |

**Más información:** https://smartit-ar.atlassian.net/browse/GITIN-2250

Saludos.
