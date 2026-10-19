# GITIN-2228 — [OPE] Graylog: nvme0n3. Alta latencia

**Tags:** `SmartCloud`, `Graylog`, `Obserbavilidad`, `SRE`, `PROD`

## Qué pasó

- Zabbix generó una alerta en el host "Cloud Graylog": "nvme0n3: Disk read/write request responses are too high (read > 20 ms for 15m or write > 20 ms for 15m)".
- La alerta estuvo activa de las 08:33:01 a las 08:38:04 (5 minutos 3 segundos) del 2026-10-15 y se resolvió sola. No se indicó la zona horaria de las horas de la alerta.
- La alerta muestra los valores "2 ms, 63,0535 ms"; se asume que son lectura y escritura, en ese orden, y que lo alto es la escritura. Pendiente de confirmar con el historial del item en Zabbix.
- `nvme0n3` es el disco de datos de OpenSearch de la VM de Graylog (partición montada en `/var/lib/opensearch`); la relación con la VM es una inferencia por el layout y los tamaños.
