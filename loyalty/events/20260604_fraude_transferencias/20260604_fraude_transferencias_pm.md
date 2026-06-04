# Informe de Fraude — Club Grido / Smart Loyalty
**Fecha del evento:** 4 de junio de 2026  
**Ventana principal:** 01:00–09:00 hs (hora local)  
**Para:** Product Management  
**De:** Dante Paniagua, SRE

---

Se detectaron tres vectores de actividad fraudulenta simultánea sobre la plataforma Smart Loyalty el 4 de junio de 2026. El evento más reciente forma parte de una operación más amplia activa desde el 16 de mayo de 2026.

---

## Vector 1 — Esquema de transferencias circulares

Tres cuentas operaron en conjunto para mover puntos de forma artificial entre sí:

- Una cuenta con identidad ficticia ("Dimon Briz", DNI 123456) y correo electrónico desechable funcionó como intermediario.
- Dos cuentas registradas bajo el nombre "Simon Brizuela" con DNIs consecutivos (46845173 y 46845174) — que corresponden a la misma persona — actuaron como concentrador y alimentador respectivamente.
- En 47 minutos, las tres cuentas ejecutaron 9 transferencias circulares (A→B→A→B) por un total de 55.340 puntos movilizados.
- Este esquema está diseñado para dificultar el rastreo del origen de los puntos y acumularlos en una sola cuenta para su posterior canje.

Los saldos de las cuentas involucradas permanecen intactos al momento de este informe: **9.565 puntos** en la cuenta concentradora y **3.300 puntos** en la cuenta alimentadora.

Una operación previa del mismo esquema fue identificada el 25 de mayo de 2026, en la que se transfirieron 10.000 puntos entre las mismas cuentas. Las tres cuentas utilizan correos electrónicos de proveedores anónimos (yopmail.com, hilostar.com) y no forman parte del listado de clientes de mailing activos.

**Tabla 1 — Emisores con actividad anómala (04/06/2026, 01:00–09:00)**

| Nombre | DNI | Puntos enviados | Canal |
|---|---|---|---|
| Dimon Briz | 123456 | 27.915 | APP |
| Simon Brizuela | 46845173 | 27.425 | APP |
| María Celeste Mamanis | 35384064 | 20.155 | APP |

**Tabla 2 — Receptores con actividad anómala (04/06/2026, 01:00–09:00)**

| Nombre | DNI | Puntos recibidos | Canal |
|---|---|---|---|
| Simon Brizuela | 46845173 | 35.915 | APP |
| Dimon Briz | 123456 | 27.415 | APP |
| Santiago Cabral | 48786856 | 20.155 | APP |

El detalle completo de todas las transferencias del período se encuentra en el archivo adjunto `20260604_fraude_transferencias_pm.csv`.

---

## Vector 2 — Desvío de beneficio de empleados

Una empleada de Grido (Colaboradora Temporal) transfirió 20.155 puntos de beneficio laboral a un cliente externo (Santiago Cabral, DNI 48786856) en tres operaciones ejecutadas en 77 segundos, con dos transferencias idénticas separadas por 17 segundos — patrón de ejecución automatizada. Este comportamiento se repitió en días consecutivos (3 y 4 de junio) hacia el mismo receptor.

El saldo del receptor al cierre de la investigación es de **20.155 puntos intactos**.

---

## Vector 3 — Manipulación de terminales POS en red de franquicias

Este vector representa la operación de mayor alcance del evento.

Entre el 16 de mayo y el 3 de junio de 2026, la cuenta ficticia "Dimon Briz" fue registrada como cliente en los sistemas de puntos de al menos **21 sucursales de 7 franquiciados distintos** en múltiples provincias del país. Como resultado, cada transacción de un cliente real procesada en esos terminales acreditó puntos a la cuenta falsa en lugar del cliente legítimo.

La imposibilidad geográfica de que una misma persona haya realizado compras en Buenos Aires (CABA), Mendoza, provincia de Buenos Aires y Santiago del Estero en el lapso de una hora confirma que la credencial fue distribuida de forma deliberada en los terminales de múltiples franquicias.

**Franquiciados con mayor volumen de transacciones afectadas:**

| Franquiciado | Sucursales | Transacciones | Puntos desviados |
|---|---|---|---|
| Cura, Juan Cruz | ORAN, ORAN II, ORAN III, ORAN IV | 253 | 1.620 |
| Zurro, Horacio | MARCOS PAZ | 187 | 1.535 |
| Jawahar, Angel | SANTIAGO DEL ESTERO II | 77 | 395 |
| Liberali, Ezequiel | FLORESTA IV | 48 | 3.200 |
| Mercado, Adrian | TERMINAL I | 4 | 1.000 |

**Total desviado en toda la operación: 10.000 puntos** en 730 transacciones. Los puntos fueron transferidos al esquema del Vector 1 y canjeados en las sucursales LICEO (franquiciado Aznarez, Juan) y LICEO 2DA (franquiciado Lazaro, Clide Mariel).

En la franquicia Cura se identificó a un operador que controla cinco identidades de personal bajo un mismo correo electrónico — patrón que indica una sola persona con acceso múltiple al sistema de gestión de la franquicia.

---

## Próximos pasos propuestos

1. **Proceso contractual contra franquiciados:** iniciar revisión contractual con los franquiciados involucrados, con prioridad en la red Cura (cuatro sucursales coordinadas) y Liberali (mayor desvío de puntos por transacción). Se recomienda escalar a Comercial y Legal.

2. **Notificación a clientes afectados:** los clientes que realizaron compras en las sucursales comprometidas entre el 16 de mayo y el 3 de junio no recibieron los puntos correspondientes a sus transacciones. Se recomienda identificarlos y restituirles los puntos. Se priorizará FLORESTA IV (3.200 puntos, 48 ventas) y MARCOS PAZ (1.535 puntos, 187 ventas) por concentración de impacto.

3. **Controles en la plataforma:** se recomienda evaluar la implementación de validación de límites de transferencia en tiempo real.

4. **Lista negra de dominios de correo temporales:** las tres cuentas del esquema circular utilizaron proveedores de correo anónimo y desechable (sin registro, sin identidad vinculada). Se recomienda incorporar en el proceso de registro de Club Grido una lista negra de dominios conocidos de correo temporal. Existe una lista de referencia de uso libre, mantenida por la comunidad y actualizada de forma continua, que puede adoptarse directamente:

   `https://raw.githubusercontent.com/disposable-email-domains/disposable-email-domains/refs/heads/main/disposable_email_blocklist.conf`

   Esta lista cubre miles de dominios desechables y se puede integrar como validación al momento del registro o actualización de correo electrónico en la plataforma.

---

*Archivos de evidencia disponibles en la carpeta del evento. Consultas adicionales: Dante Paniagua, SRE.*
