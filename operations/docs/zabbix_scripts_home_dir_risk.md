# Zabbix scripts symlinked from personal home directories — risk pending verification

**Origin:** incidental finding while designing the FEPE triggers (2026-07-24, see `events/20260714_fepe_zabbix_healthcheck/`), when listing `/usr/bin/get-*` on `sf-monitoreo.smartfran.com` to confirm the `get-fepe-status` symlink.

## Finding

At least two UserParameter scripts in use on the `Zabbix server` host (`sf-monitoreo.smartfran.com`) are symlinked from a personal home directory instead of `/opt/scripts/` (the convention documented in the `ope-zabbix` skill):

| Symlink | Target | Symlink date |
|---|---|---|
| `/usr/bin/get-cw-metrics` | `/home/ubuntu/scritps/aws-cloudwatch/get-metrics/get-metrics.py` | 2024-07-01 |
| `/usr/bin/get-enddate` | `/home/ubuntu/scritps/sslenddate/get_enddate.sh` | 2025-04-24 |

(The directory name has a typo, `scritps` instead of `scripts`, in both paths, which suggests a shared origin/copy.)

This is the same risk pattern already confirmed as root cause in two documented incidents:
- ARCA: script execution blocked for the `zabbix` user by `750` permissions on `/home/ubuntu` (`2026-06-06_arca_api_check_ops-events.md`).
- FEPE: a relative `Include=./zabbix_agent2.d/plugins.d/*.conf` (line 497 of `zabbix_agent2.conf`; the main `Include`, line 281, is absolute) could not be resolved when testing as `zabbix` from `/home/ubuntu` (`20260714_fepe_zabbix_healthcheck_ops-events.md`, finding of 2026-07-14 22:32).

## Status — not confirmed, inferred from the pattern only

It was **not verified** whether `/home/ubuntu` currently has permissions that block the `zabbix` user, or whether these two scripts actually fail; unlike ARCA and FEPE, which were confirmed failing. These two items may never have had the problem (for example if the UserParameter does not depend on `zabbix` being able to list the parent directory, or if `/home/ubuntu` permissions changed since the symlink was created). Treat as pending verification, not as a confirmed incident.

## Suggested check (not run)

```bash
namei -l /home/ubuntu/scritps/aws-cloudwatch/get-metrics/get-metrics.py
namei -l /home/ubuntu/scritps/sslenddate/get_enddate.sh

# Confirm the keys resolve when run as the zabbix user
sudo -u zabbix zabbix_agent2 -t <get-cw-metrics key> -c /etc/zabbix/zabbix_agent2.conf
sudo -u zabbix zabbix_agent2 -t <get-enddate key> -c /etc/zabbix/zabbix_agent2.conf
```

If either fails, remediation: move to `/opt/scripts/` and symlink from `/usr/bin/`, following the same procedure as ARCA and FEPE (`ope-zabbix` skill, Step 1).

Related: `get_enddate.sh` is also the script behind the 8 SSL-expiry items (it runs from the `ubuntu` user's crontab, see `docs/zabbix_observability.md` → SSL certificate expiration, `GITIN-2249`).
