# Eventos — sonarqube_disco_lleno

## 2026-07-20 — Relevamiento inicial: disco casi lleno sin alerta

**Resultado:**
He recibido el `df -h` de `/opt/ssd01` en el host Sonarqube (`ext4`, 251G total, 229G usado, 9,7G disponible, 96% de uso) junto con la novedad de que Zabbix no generó ninguna alerta al respecto.

He confirmado el nombre técnico del host en Zabbix (`sfcg-sonarqube`, visible como "Sonarqube"), obtenido a partir de la expresión del propio trigger.

## 2026-07-20 — Verificación de recolección de datos (Latest data)

**Resultado:**
He revisado Latest data para `/opt/ssd01` en el host Sonarqube: Space utilization (`pused`) 96,1348% actualizando cada ~9s, Free inodes 75,27%, Total space 250,92 GB, Used space 228,9 GB actualizando cada ~3-6s.

He confirmado que la recolección del ítem está sana — no hay problema de agente, discovery ni conectividad; los datos llegan en tiempo real.

## 2026-07-20 — Expresión del trigger y macros de umbral

**Resultado:**
He revisado la expresión del trigger "Disk space is low" para `/opt/ssd01`:

```
last(/sfcg-sonarqube/vfs.fs.size[/opt/ssd01,pused])>{$VFS.FS.PUSED.MAX.CRIT:"/opt/ssd01"} and
((last(/sfcg-sonarqube/vfs.fs.size[/opt/ssd01,total])-last(/sfcg-sonarqube/vfs.fs.size[/opt/ssd01,used]))<{$VFS.FS.FREE.MIN.CRIT:"/opt/ssd01"} or timeleft(/sfcg-sonarqube/vfs.fs.size[/opt/ssd01,pused],1h,100)<1d)
```

He confirmado los valores resueltos de los macros de contexto para `/opt/ssd01`: `{$VFS.FS.PUSED.MAX.CRIT}=90`, `{$VFS.FS.FREE.MIN.CRIT}=5G`. Confirmé que agregué estos dos macros recientemente, no son valores heredados sin tocar del template.

Con `pused`=96,13% y espacio libre reportado por Zabbix (~22 GB) muy por encima del piso de 5 GB, calculé que la segunda condición del `AND` (espacio libre bajo el crítico, o `timeleft`<1 día) nunca se cumple — el trigger no puede pasar a PROBLEM con los valores actuales, pese al uso real del 96%.

## 2026-07-20 — Causa raíz identificada y acción propuesta

**Resultado:**
He concluido que la causa raíz es el macro `{$VFS.FS.FREE.MIN.CRIT:"/opt/ssd01"}=5G`, mal calibrado respecto al tamaño real del disco (251 GB) — el punto donde `pused` cruza el 90% equivale a ~25 GB libres, muy por encima del piso de 5 GB configurado. Identifiqué además que el "free" que reporta Zabbix (~22 GB) no coincide con el disponible real (9,7 GB de `df -h`) por los bloques reservados de root de ext4 (5%), lo que agrava el desajuste. Dejé documentada en el ticket la acción propuesta: ajustar el macro a ~28 GB y validar el disparo del trigger tras el cambio.

## 2026-07-20 — Corrección: no existía macro con contexto, sólo el genérico

**Resultado:**
Se confirmó que `{$VFS.FS.FREE.MIN.CRIT}` (sin contexto) existía a nivel host con valor `5G`, pero `{$VFS.FS.FREE.MIN.CRIT:"/opt/ssd01"}` (con contexto) no existía como entrada propia — el valor `5G` resuelto anteriormente venía del fallback al macro genérico, no de un override específico para `/opt/ssd01`. Indiqué crear un macro nuevo con el contexto explícito en el nombre (`{$VFS.FS.FREE.MIN.CRIT:"/opt/ssd01"}` = `28G`) en vez de editar el genérico, para no afectar el umbral de otros sistemas de archivos del mismo host.

## 2026-07-20 — Confirmación: disco llegó a 100% sin alerta (refuerza causa raíz)

**Resultado:**
Se reportó que el disco había llegado a 100% de uso (`df`, disponible no-root en 0) sin que se emitiera ninguna alerta. Confirmé que esto no era sólo un problema de calibración relativa al 90% sino estructural: los bloques reservados de root de ext4 (~12,5 GB en este volumen) imponen un piso al "free" que lee Zabbix, piso que el `5G` configurado nunca podía cruzar por uso no-root. Documenté esta confirmación en la sección "Causa raíz" del ticket.

## 2026-07-20 — Macro `{$VFS.FS.FREE.MIN.CRIT:"/opt/ssd01"}=28G` aplicado — alerta activa

**Resultado:**
Se aplicó el macro con contexto `{$VFS.FS.FREE.MIN.CRIT:"/opt/ssd01"}=28G` en Data collection → Hosts → Sonarqube → Macros. Se confirmó que el trigger "Disk space is low on /opt/ssd01" pasó a estado PROBLEM.

Con esto quedó resuelta la causa raíz identificada en este ticket — el trigger ya es capaz de alertar sobre `/opt/ssd01`. Pendiente de confirmar si además se recibió la notificación (Chat/email/canal de alertas configurado) para descartar un problema independiente de enrutamiento de Actions.
