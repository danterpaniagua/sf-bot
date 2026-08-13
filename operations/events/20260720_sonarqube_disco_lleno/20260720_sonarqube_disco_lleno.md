# Disco casi lleno en host Sonarqube sin alerta de Zabbix

## Resumen

El host `Sonarqube` (técnico `sfcg-sonarqube`), punto de montaje `/opt/ssd01` (ext4, 251 GB), se encuentra al 96,13% de uso (aprox. 9,7 GB disponibles reales según `df -h`) sin que Zabbix haya generado ninguna alerta. La recolección de datos del ítem funciona correctamente. El trigger "Disk space is low" no se dispara por una mala calibración de los macros de umbral de contexto para `/opt/ssd01`, agregados recientemente.

## Tabla resumen

| Campo | Valor |
|---|---|
| ID alerta | N/A — no llegó a generarse |
| Sistema | Zabbix (host `Sonarqube` / `sfcg-sonarqube`) |
| Severidad | Alta |
| Detectado | 2026-07-20 |
| Resuelto | 2026-07-21 — trigger corregido (macro `{$VFS.FS.FREE.MIN.CRIT:"/opt/ssd01"}=28G`), alerta confirmada activa |
| Responsable | Dante Paniagua |

## Causa raíz

El trigger nativo "Disk space is low on {#FSNAME}" (template de descubrimiento de sistemas de archivos) exige el cumplimiento simultáneo de dos condiciones:

```
last(pused) > {$VFS.FS.PUSED.MAX.CRIT:"/opt/ssd01"}
AND
( (total - used) < {$VFS.FS.FREE.MIN.CRIT:"/opt/ssd01"}
  OR timeleft(pused,1h,100) < 1d )
```

Los macros de contexto para `/opt/ssd01` fueron agregados recientemente: `{$VFS.FS.PUSED.MAX.CRIT:"/opt/ssd01"}=90`, `{$VFS.FS.FREE.MIN.CRIT:"/opt/ssd01"}=5G`. La primera condición se cumple (`pused`=96,13% > 90%), pero la segunda no: el espacio libre que reporta Zabbix (`vfs.fs.size[...,free]` ≈ 22 GB) está muy por encima del piso de 5 GB configurado, y la tasa de llenado actual no alcanza a disparar `timeleft()<1d`. El resultado es que el trigger nunca pasa a estado PROBLEM pese al 96% de uso real — el macro de espacio libre en bytes fue calibrado sin relación al tamaño real del disco (en un volumen de 251 GB, el punto donde `pused` cruza el 90% equivale a ~25 GB libres, no 5 GB).

Un factor adicional agrava el desajuste: el "free" que expone Zabbix (~22 GB) no coincide con el "disponible" real que reporta `df -h` (9,7 GB) — la diferencia (~12,5 GB) corresponde al 5% de bloques reservados para root que ext4 aplica por defecto en este volumen. Zabbix calcula sobre el espacio libre "crudo" (incluye la reserva de root), no sobre el disponible real para el proceso de SonarQube, por lo que cualquier umbral en bytes definido sobre este ítem sobreestima el margen real en ~12,5 GB.

**Confirmación adicional (2026-07-20):** se reportó que el disco llegó a 100% de uso (`df`, disponible no-root en 0) sin que se emitiera ninguna alerta. Esto confirma que el problema no era sólo de calibración relativa al 90% — era estructural: por los bloques reservados de root de ext4 (~12,5 GB en este volumen), el valor "free" que lee Zabbix vía `statvfs` **nunca puede bajar de ese piso** mientras el llenado provenga de uso no-root (la aplicación SonarQube). Con `{$VFS.FS.FREE.MIN.CRIT:"/opt/ssd01"}=5G`, la condición `free < 5G` era matemáticamente inalcanzable en este disco sin importar cuán lleno estuviera desde la perspectiva de la aplicación — el disco podía sostenerse en 100% (df) indefinidamente sin que este trigger pasara nunca a PROBLEM. Confirma que `28G` (por encima del piso de ~12,5 GB) es imprescindible, no sólo preferible, para que la cláusula sea alcanzable.

## Hallazgos

| # | Hallazgo | Riesgo |
|---|---|---|
| H1 | `/opt/ssd01` al 96,13% de uso (`pused`), recolección de datos del ítem funcionando correctamente (~9s de intervalo) | Alto |
| H2 | `{$VFS.FS.FREE.MIN.CRIT:"/opt/ssd01"}=5G` muy por debajo del punto real donde `pused` cruza el 90% (~25 GB en un disco de 251 GB) | Alto |
| H3 | Espacio libre reportado por Zabbix (~22 GB) no coincide con el disponible real (9,7 GB, `df -h`) — atribuible a bloques reservados de root en ext4 (5%) | Medio |
| H4 | No se confirmó si el trigger está actualmente en estado PROBLEM en Monitoring → Problems ni si las Actions/rutas de notificación están operativas — pendiente de validar una vez corregido el macro | Medio |

## Recursos afectados

| Componente | Impacto |
|---|---|
| Host Sonarqube (`sfcg-sonarqube`) | Disco `/opt/ssd01` sin alertar pese a estar casi lleno — riesgo de degradación o caída del servicio SonarQube por falta de espacio |
| Zabbix (triggers de `/opt/ssd01`) | Macros de umbral mal calibrados, agregados recientemente sin validar contra el tamaño real del disco |

## Comandos ejecutados

Ninguno — el relevamiento se realizó por inspección manual en la interfaz de Zabbix (Latest data y Macros del host `Sonarqube`) y por `df -h` provisto directamente. No se generó archivo de script para esta sesión.

## Acciones propuestas

1. ✅ (SRE) Ajustar `{$VFS.FS.FREE.MIN.CRIT:"/opt/ssd01"}` de `5G` a `28G`, creando el macro con contexto explícito (no editar el genérico `{$VFS.FS.FREE.MIN.CRIT}`, para no afectar otros sistemas de archivos del mismo host) — aplicado 2026-07-20.
2. ✅ (SRE) Confirmar en Monitoring → Problems que el trigger pasa a estado PROBLEM — confirmado 2026-07-20.
3. ⚠️ (SRE) Validar que las Actions/rutas de notificación asociadas a este trigger estén habilitadas y enviando correctamente — pendiente de confirmación explícita de recepción (Chat/email/canal configurado).
4. ⚠️ (Infra/SRE) Evaluar si reducir el porcentaje de bloques reservados para root en `/opt/ssd01` (`tune2fs -m`) tiene sentido, dado que es un disco de datos de aplicación (SonarQube) y no un disco raíz — reduciría la brecha entre el "free" que ve Zabbix y el disponible real, y liberaría ~12,5 GB reales de espacio utilizable.
5. ⚠️ (SRE) Evaluar si otros hosts/discos con templates de filesystem de Zabbix tienen el mismo problema estructural (macro genérico por debajo del piso de bloques reservados de root) — este hallazgo probablemente no es exclusivo de `sfcg-sonarqube`.

## Hallazgos secundarios

Ninguno.
