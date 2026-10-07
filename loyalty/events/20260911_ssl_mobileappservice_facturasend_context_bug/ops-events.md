# Eventos — 20260911_ssl_mobileappservice_facturasend_context_bug

## 2026-09-11 — Apertura de investigación a partir de una revisión de alertas

He revisado dos alertas de Zabbix que me pasaron para evaluar si eran anómalas: `SSL www.smartfran a menos de 45 dias de vencer` y `SSL MobileAppService a menos de 25 dias de vencer`. He confirmado que la primera es legítima (44 días restantes, correctamente por debajo de su umbral de 45). He identificado la segunda como sospechosa: permanecía activa desde el 2026-09-02 pese a que el valor actual del ítem (54 días) está muy por encima del umbral que supuestamente la disparó.

## 2026-09-11 — Confirmación del mecanismo de la falsa alarma

He confirmado, vía `trigger.get` y `usermacro.get` (global), que los tres triggers SSL de MobileAppService usan el contexto de macro `:FACTURASEND` en lugar de uno propio, y que su expresión de recuperación (`recovery_mode: 1`) exige un valor mayor a 80 días — umbral heredado de un servicio no relacionado. He confirmado que el ítem subyacente no está obsoleto (`lastclock` vigente, `lastvalue: 54`), por lo que el trigger nunca podía cumplir esa condición de recuperación pese a que el certificado está en buen estado.

## 2026-09-11 — Creación de macros dedicados para MobileAppService

He creado cuatro macros globales bajo un contexto propio `:MOBI` (`usermacro.createglobal`), con valores acordes a la renovación automática de MobileAppService: `WARN=15`, `AVERAGE=10`, `HIGH=2`, `OK=30`.

## 2026-09-11 — Corrección de los tres triggers de MobileAppService

He repuntado la `expression` y `recovery_expression` de los tres triggers de `:FACTURASEND` a `:MOBI`. He encontrado que el formato `{funcid}` devuelto por `trigger.get` no es válido para `trigger.update` — lo he resuelto reconstruyendo la expresión con la sintaxis `function(/host/key,params)` obtenida vía `expandExpression`. He confirmado, vía `item.get`, que el ítem subyacente es de tipo entero sin signo, por lo que he corregido el operador de recuperación de `>` a `>=` para que el valor 30 exacto cuente como recuperado. He corregido además el campo `description` de los tres triggers, que había quedado mostrando el contexto anterior (`FACTURASEND`) pese a que la lógica ya usaba `MOBI`.

## 2026-09-11 — Cierre técnico, con una verificación pendiente

He dejado registrada la corrección como convergida. No he podido reconfirmar en esta sesión que `triggerid 25914` haya pasado a estado recuperado, dado que un trigger solo se reevalúa en el próximo chequeo real del ítem, no al guardar la configuración — queda como seguimiento pendiente.
