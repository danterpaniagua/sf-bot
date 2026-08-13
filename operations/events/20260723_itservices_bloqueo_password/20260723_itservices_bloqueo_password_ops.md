# itservices — Bloqueo recurrente por rotación de contraseña no coordinada en flota IIS

## Resumen

Durante la actualización de la identidad de App Pool IIS con la cuenta Azure AD DS `itservices` (UPN `grupo.servicesit@smartfran.com`), la cuenta quedó bloqueada de forma recurrente en el dominio administrado `smartit.azure`. El síntoma inicial en IIS ("The specified password is invalid") enmascaraba un bloqueo de cuenta por `badPwdCount` excedido, no un problema de contraseña incorrecta. La causa raíz es que `itservices` es la identidad de App Pool compartida por 12 servidores de producción de SmartLoyalty (hallazgo previo del evento `20260610_kerberos_rc4_aadds`, alerta AADDS123): al actualizarse la contraseña en un solo servidor, el resto de la flota continuó autenticando con la credencial anterior, incrementando `badPwdCount` hasta superar nuevamente el umbral de bloqueo del dominio tras cada desbloqueo manual. El bloqueo quedó resuelto de forma puntual; la rotación coordinada en el resto de la flota queda pendiente para evitar recurrencia.

## Tabla resumen

| Campo | Valor |
|---|---|
| Cuenta | `itservices` (UPN `grupo.servicesit@smartfran.com`) |
| Objeto AD | `CN=appaccess,OU=AADDC Users,DC=smartit,DC=azure` |
| Dominio | Azure AD DS — `smartit.azure` |
| DC verificados | `192.168.40.4`, `192.168.40.5` |
| Síntoma inicial | IIS: "The specified password is invalid" |
| Causa real | Cuenta bloqueada (`lockoutTime` ≠ 0) por `badPwdCount` excedido |
| Detectado | 2026-07-23 |
| Estado | Resuelto — todos los App Pools IIS operativos con la nueva credencial. Verificación LDAP de `badPwdCount`/`lockoutTime` pendiente como cierre formal |
| Responsable | Dante Paniagua |

## Causa raíz

`itservices` es la identidad de App Pool IIS compartida por la totalidad de los servidores web de producción de SmartLoyalty (ver `20260610_kerberos_rc4_aadds_ops.md`, hallazgo H6). Al actualizarse la contraseña de esta cuenta en Entra ID y sincronizarse el hash hacia AADDS (`pwdLastSet` actualizado a `2026-07-23 10:42:29`), únicamente el servidor donde se realizó la prueba quedó alineado con la nueva credencial. El resto de los servidores de la flota, con sus App Pools configurados aún con la contraseña anterior, continuaron generando intentos de autenticación fallidos contra `itservices`. Estos intentos incrementan `badPwdCount` de forma local por controlador de dominio (atributo no replicado), mientras que `lockoutTime` sí se replica de forma urgente entre réplicas — por lo que, una vez alcanzado el umbral de bloqueo en cualquier DC, la cuenta queda bloqueada en todo el dominio. Cada desbloqueo manual fue seguido de un reinicio del conteo de intentos fallidos por parte de los servidores no actualizados, reproduciendo el bloqueo en cuestión de minutos.

## Hallazgos

| # | Hallazgo | Riesgo |
|---|---|---|
| H1 | `pwdLastSet` de `itservices` actualizado a `2026-07-23 10:42:29` — confirma sincronización del nuevo hash desde Entra ID hacia AADDS | Bajo — comportamiento esperado |
| H2 | `lockoutTime` idéntico (`2026-07-23 11:04:21`) en ambas réplicas DC (`192.168.40.4` y `.5`) — replicación urgente de bloqueo funcionando correctamente | Bajo |
| H3 | `badPwdCount` no se replica entre réplicas (comportamiento nativo de AD) — cada DC lo cuenta de forma local | Informativo |
| H4 | Tras el primer desbloqueo, `badPwdCount` volvió a incrementarse (2 intentos) en minutos sobre `192.168.40.4`, sin intervención manual adicional en ese servidor | Alto — confirma reintentos automáticos activos desde otros nodos |
| H5 | **`itservices` respalda la identidad de App Pool IIS en 12 servidores de producción de SmartLoyalty simultáneamente** — una rotación de contraseña no coordinada en todos ellos provoca bloqueo recurrente de la cuenta | **Alto — bloqueante para completar la rotación** |
| H6 | Bug detectado en script de diagnóstico propio: la lectura de `lockoutTime` vía `[ADSI]` directo falla al castear `IADsLargeInteger` (COM) a `[Int64]`; requiere `DirectorySearcher` para el marshaling correcto | Bajo — corregido en `docs/itservices_rotacion_password_runbook.md` |

## Recursos afectados

### Cuenta crítica

| Recurso | Rol | Estado |
|---|---|---|
| `itservices` | Identidad de App Pool IIS en la totalidad de servidores web WS2019 de SmartLoyalty | Desbloqueada puntualmente — contraseña desincronizada respecto al resto de la flota |

### Servidores dependientes de itservices (pendientes de alinear contraseña)

| Servidor | Servicio |
|---|---|
| SFCG-WEBS-01, 02, 03 | SmartLoyalty WebService |
| SFCG-WSV2-01, 02 | SmartLoyalty WebServiceV2 |
| SFCG-WSIT-01 | SmartLoyalty Website |
| SFCG-MOBI-01, 02 | Mobile service |
| SFCG-WSCG-01 | CG web service |
| SFCG-CLUB-01, 02 | Club Grido website |
| SFCG-TO-01 | TaskOperatorService |

> No quedó registrado en esta sesión en cuál de estos servidores se realizó la prueba inicial de cambio de credencial. Confirmar y documentar antes del rollout coordinado.

## Comandos ejecutados

**Diagnóstico y resolución:** `20260723_itservices_bloqueo_password_scripts.ps1`

| # | Comando/Script | Propósito |
|---|---|---|
| CX-01 | Búsqueda ANR (`anr=servicesit`) | Localizar objeto AD — sin resultados |
| CX-02 | Búsqueda por UPN/mail/proxyAddresses | Localizar objeto AD — confirma `itservices` / `pwdLastSet` |
| CX-03 | `net user <UPN> /domain` | Intento de consulta — error de sintaxis (UPN no soportado) |
| CX-04 | `net user itservices /domain` | Intento de consulta — sAMAccountName supuesto incorrecto |
| CX-05 | `cmdkey /list` | Descartar credencial cacheada como causa del fallo silencioso de `runas` |
| CX-06 | `Start-Process -Credential` | Primer hallazgo del bloqueo real de la cuenta |
| CX-07 | Verificación `lockoutTime`/`badPwdCount` (con bug de casteo) | Detecta divergencia de `badPwdCount` entre réplicas |
| CX-08 | Verificación corregida (`DirectorySearcher`) | Confirma bloqueo simultáneo en ambas réplicas |
| CX-09 | Desbloqueo sobre `192.168.40.4` | Primer desbloqueo |
| CX-10 | Reverificación post-desbloqueo | Confirma reincremento de `badPwdCount` por reintentos externos |

## Acciones propuestas

1. **Rollout coordinado en los 12 servidores de la flota** — actualizar la contraseña de `itservices` en todos los servidores dentro de la misma ventana, minimizando el intervalo en que coexisten servidores con credenciales distintas. *(Completado)*

2. **Confirmar y documentar el servidor de la prueba inicial** — identificar en qué servidor de la flota se realizó el primer cambio de credencial que originó este evento, para incluirlo explícitamente en el rollout. *(Pendiente)*

3. **Verificar `pwdLastSet` en ambas réplicas AADDS antes de dar por propagado el cambio** — usando el script corregido de `docs/itservices_rotacion_password_runbook.md`, confirmar que ambos DC (`192.168.40.4`, `192.168.40.5`) reflejan el mismo `pwdLastSet` antes de actualizar cualquier servidor adicional. *(Pendiente)*

4. **Evaluar monitoreo de `badPwdCount` sobre `itservices`** — alerta temprana (Zabbix o Azure Monitor) ante incrementos fuera de ventana de mantenimiento planificada, dado el riesgo de caída total de autenticación IIS que implica el bloqueo de esta cuenta. *(Pendiente)*

5. **Publicar runbook de rotación** — procedimiento paso a paso documentado en `operations/docs/itservices_rotacion_password_runbook.md` para estandarizar futuras rotaciones de esta cuenta. *(Completado — ver documento)*

## Hallazgos secundarios

- El script de diagnóstico inicial (lectura directa vía `[ADSI]`) no debe reutilizarse para atributos de 64 bits (`lockoutTime`, `pwdLastSet` vía `DirectoryEntry`) por el error de casteo COM documentado en H6. El runbook publicado usa la variante corregida (`DirectorySearcher`).
- Esta cuenta ya había sido señalada como punto único de dependencia crítica en el evento `20260610_kerberos_rc4_aadds` (AADDS123) por su falta de `msDS-SupportedEncryptionTypes` explícito. Ambos hallazgos apuntan a la misma necesidad: tratar cualquier cambio sobre `itservices` como operación de flota completa, no de servidor individual.
