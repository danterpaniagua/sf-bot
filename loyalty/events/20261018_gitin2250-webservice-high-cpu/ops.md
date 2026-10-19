# [SML] WebService High CPU

**Tags:** `Loyalty`, `Observabilidad`, `SRE`, `PROD`

## Qué pasó

Se reportó el 2026-10-18 que el servidor `webs02` (SFCG-WEBS-02, una de las tres instancias del WebService de SmartLoyalty) alcanzó el 100 % de CPU.

## Resumen

SFCG-WEBS-02 pasó de un promedio de CPU cercano al 40 % a las 10:00 a más del 95 % desde las 14:03 y a un 99-100 % sostenido desde las 14:27 (horas UTC-3), mientras recibía menos peticiones que SFCG-WEBS-01 y SFCG-WEBS-03. El balanceador de carga dejó de enviarle conexiones nuevas desde aproximadamente las 14:34, porque la sonda de salud HTTP del balanceador falló en todos los intentos, mientras que el ping TCP al puerto 8080 de Zabbix y el estado del grupo de aplicaciones seguían correctos. Se reinició la máquina a las 15:28; el balanceador volvió a admitirla desde las 15:38 y su CPU quedó variable (entre 22 % y 100 % por minuto; 80 % en la última medición de las 15:40), todavía por encima de las otras dos. No se identificó la causa y se cierra el evento sin ella.

## Tabla resumen

| Campo | Valor |
|---|---|
| Ticket Jira | [GITIN-2250](https://smartit-ar.atlassian.net/browse/GITIN-2250) |
| ID alerta | N/A — reporte manual (alerta no detallada) |
| Sistema | SFCG-WEBS-02 (WebService de SmartLoyalty, IIS), balanceador SFCG-WEBS-LB, Zabbix 6.0.32 (sf-monitoreo.smartfran.com) |
| Severidad | Media |
| Detectado | 2026-10-18 (CPU sobre 95 % desde las 14:03, UTC-3) |
| Resuelto | No — sin causa identificada. La máquina se reinició a las 15:28 y el balanceador volvió a admitirla desde las 15:38; no hay mediciones posteriores a las 15:40 |
| Responsable | Operaciones (SRE) |

## Causa raíz

NA

## Hallazgos

- CPU de SFCG-WEBS-02 (promedio por hora, UTC-3): 39 %, 37 %, 56 %, 79 % y 86 % entre las 10:00 y las 14:00, con picos de hasta 99,9 %. SFCG-WEBS-01 se mantuvo bajo 60 % (3-19 % de promedio horario) y SFCG-WEBS-03 en 30-34 %.
- Desde las 13:00, SFCG-WEBS-02 recibió el menor tráfico de las tres (3-7 peticiones POST por segundo contra 9-16 en las otras) y las menos conexiones; el consumo de CPU no siguió el volumen de peticiones. La cola de CPU promedió 11 (máximo 30) a las 14:00 en SFCG-WEBS-02 y 0 en SFCG-WEBS-01.
- Con la máquina saturada, el sistema operativo la reportaba con 2 procesadores lógicos y 100 % de CPU total: dos procesos de trabajo de IIS (`w3wp`, del grupo `SmartLoyalty.WebService`) usaban 79 % y 53 % de un núcleo, y el proveedor WMI (`WmiPrvSE`) 49 %. Había 5 peticiones IIS en curso.
- El balanceador (`SFCG-WEBS-LB`, una regla, distribución por IP de origen, sonda HTTP a `healthcheck.ashx` en el puerto 8080 cada 15 s, 1 fallo = no disponible) midió la disponibilidad de la sonda de SFCG-WEBS-02 en 80 %, 82 %, 68 %, 43 % y 27 % entre las 10:00 y las 14:00 y 0 % desde aproximadamente las 14:34 hasta el reinicio. Con distribución por IP de origen, el balanceador no reacciona a la CPU: solo la sonda lo saca del grupo.
- Antes del reinicio, `GET http://localhost:8080/healthcheck.ashx` en SFCG-WEBS-02 devolvió HTTP 400 en 1,7 s; después del reinicio devolvió HTTP 200 en 0,8 s. Qué comprueba ese archivo no se pudo determinar (no está en el código fuente local).
- Se reinició la máquina a las 15:28:03. Después: sonda del balanceador en 78 %, 4 %, 51 %, 76 %, 57 %, 50 %, 63 % y 49 % entre las 15:30 y las 15:37, y 100 % a las 15:38 y 15:39; cola de CPU en 0; CPU entre 22 % y 100 % por minuto (15:29 a 15:39) y 80 % en la medición de las 15:40.
- Las tres máquinas están configuradas de forma distinta: SFCG-WEBS-01 tiene 4 procesadores y hasta 5 procesos de trabajo por grupo de aplicaciones; SFCG-WEBS-02, 2 procesadores y hasta 3; SFCG-WEBS-03, 2 procesadores y 1, con reciclaje periódico cada 29 horas (las otras dos no reciclan). No se probó si esa diferencia influye en la CPU.
- El proveedor WMI (`WmiPrvSE`) consumió 60 % de un núcleo en SFCG-WEBS-02 y 94 % en SFCG-WEBS-03 en una muestra de 10 segundos tomada sin consultas WMI propias (en SFCG-WEBS-01, 1 % o menos). Zabbix ejecuta cada minuto dos consultas WMI idénticas en las tres máquinas («Windows: Number of cores» y «Windows: Network interfaces WMI get»); en SFCG-WEBS-02 el registro de WMI muestra el proveedor CIMWin32 arrancando en el segundo 18 de cada minuto, coherente con esas consultas, pero no se confirmó que sean ellas la fuente. No se llegó a medir el costo de esas consultas por máquina.
- SFCG-WEBS-03 también perdió sondas del balanceador (81-94 % de disponibilidad desde las 11:00 y caídas aisladas a 57-76 % hasta las 15:39) con CPU cercana a 30 %; no se explicó.
- Las tres máquinas arrancaron o reiniciaron IIS durante la mañana del 2026-10-18 (SFCG-WEBS-02 a las 10:00 y a las 11:09; SFCG-WEBS-03 a las 10:53; SFCG-WEBS-01 a las 11:03). Se desconoce el motivo.
- Antes del reinicio solo se obtuvo una captura de procesos (15:24); la comparación de la respuesta de `healthcheck.ashx` con una máquina sana y el listado completo de procesos no llegaron a ejecutarse.

## Recursos afectados

| Recurso | Detalle |
|---|---|
| Servidor | SFCG-WEBS-02 (2 procesadores lógicos), grupo de aplicaciones `SmartLoyalty.WebService` |
| Balanceador | SFCG-WEBS-LB, grupo `Back_WebS2` (SFCG-WEBS-01/02/03), regla `LB_Rule_WEBS2` |
| Servidores relacionados | SFCG-WEBS-01 y SFCG-WEBS-03 (comparación) |

## Comandos ejecutados

Solo lecturas sobre Zabbix, Azure y las máquinas virtuales (mediante ejecución remota de scripts de solo lectura); el único cambio sobre infraestructura fue el reinicio de SFCG-WEBS-02 hecho por el usuario.

| # | Qué se leyó |
|---|---|
| 1 | CPU de SFCG-WEBS-01/02/03 en Zabbix (12 h) y elementos de peticiones, conexiones, colas y reinicios de IIS (6 h) |
| 2 | Balanceador: reglas, sondas, grupos de destino, IP de cada interfaz de red y disponibilidad de la sonda por servidor (6 h y 1 h) |
| 3 | Triage remoto de SFCG-WEBS-02 antes y después del reinicio (procesos, cola de CPU, prueba local de `healthcheck.ashx`, peticiones IIS) |
| 4 | Comparación de procesos `w3wp` y de la configuración del grupo de aplicaciones en las tres máquinas |
| 5 | Actividad WMI (proveedores cargados y registro de WMI) en SFCG-WEBS-02 y SFCG-WEBS-03 y ítems WMI de Zabbix |

## Acciones propuestas

Todas pendientes de decisión; ninguna se aplicó.

1. **Dejar el evento cerrado sin causa (decidido por el usuario)**; reabrir si SFCG-WEBS-02 vuelve a saturarse.
2. Si se repite, **capturar antes de reiniciar** el listado de procesos y la respuesta de `healthcheck.ashx` (con la IP del servidor y con `localhost`) en SFCG-WEBS-02 y en una máquina sana.
3. Evaluar la **frecuencia de las dos consultas WMI de Zabbix** (cada minuto en las tres máquinas) y medir su costo en cada una, ya que `WmiPrvSE` consumió una parte importante de la CPU en las dos máquinas de 2 procesadores.
4. Revisar si la **diferencia de configuración** entre las tres máquinas (procesadores, procesos de trabajo por grupo de aplicaciones, reciclaje periódico) es intencional.
5. Verificar la **ruta de la sonda del balanceador** (`healthcheck.ashx`, almacenada sin barra inicial) y qué comprueba ese archivo.
6. Aclarar por qué **SFCG-WEBS-03** pierde sondas con CPU normal y el motivo de los inicios de IIS de la mañana del 2026-10-18.
