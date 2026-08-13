# Scripts Zabbix symlinkeados desde directorios home personales — riesgo pendiente de verificar

**Origen:** hallazgo tangencial durante la sesion de diseno de triggers FEPE (2026-07-24, ver `events/20260714_fepe_zabbix_healthcheck/`), al listar `/usr/bin/get-*` en `sf-monitoreo.smartfran.com` para confirmar el symlink de `get-fepe-status`.

## Hallazgo

Al menos dos UserParameter scripts en uso en el host `Zabbix server` (`sf-monitoreo.smartfran.com`) symlinkean desde un directorio home personal en lugar de `/opt/scripts/` (la convencion documentada en el skill `ope-zabbix`):

| Symlink | Target | Fecha del symlink |
|---|---|---|
| `/usr/bin/get-cw-metrics` | `/home/ubuntu/scritps/aws-cloudwatch/get-metrics/get-metrics.py` | 2024-07-01 |
| `/usr/bin/get-enddate` | `/home/ubuntu/scritps/sslenddate/get_enddate.sh` | 2025-04-24 |

(Nota: el nombre del directorio tiene un typo — `scritps`, no `scripts` — presente en ambos paths, lo que sugiere que comparten origen/copia.)

Este es el mismo patron de riesgo ya confirmado como causa raiz en dos incidentes documentados:
- ARCA: bloqueo de ejecucion del script para el usuario `zabbix` por permisos `750` en `/home/ubuntu` (`2026-06-06_arca_api_check_ops-events.md`).
- FEPE: bloqueo de resolucion de un `Include` relativo en `zabbix_agent2.conf` al testear desde `/home/ubuntu` (`20260714_fepe_zabbix_healthcheck_ops-events.md`, hallazgo del 2026-07-14 22:32).

## Estado — no confirmado, solo inferido por patron

**No se verifico** si `/home/ubuntu` tiene actualmente permisos que bloqueen al usuario `zabbix`, ni si estos dos scripts especificos fallan en la practica — a diferencia de ARCA y FEPE, que fueron confirmados fallando. Es posible que estos dos items nunca hayan tenido el problema (por ejemplo, si el UserParameter no depende de que `zabbix` pueda listar el directorio padre, o si los permisos de `/home/ubuntu` cambiaron desde que se creo el symlink). Marcar como pendiente de verificacion, no como incidente confirmado.

## Verificacion sugerida (no ejecutada)

```bash
namei -l /home/ubuntu/scritps/aws-cloudwatch/get-metrics/get-metrics.py
namei -l /home/ubuntu/scritps/sslenddate/get_enddate.sh

# Confirmar si las keys resuelven corriendo como el usuario zabbix
sudo -u zabbix zabbix_agent2 -t <key_de_get-cw-metrics> -c /etc/zabbix/zabbix_agent2.conf
sudo -u zabbix zabbix_agent2 -t <key_de_get-enddate> -c /etc/zabbix/zabbix_agent2.conf
```

Si alguno falla, remediacion: reubicar a `/opt/scripts/` y symlinkear desde `/usr/bin/`, siguiendo el mismo procedimiento que ARCA y FEPE (`ope-zabbix` skill, Step 1).
