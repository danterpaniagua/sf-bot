# GITIN-1238 — SFCG-WSV2-LB no enrutaba tráfico real de clientes a SFCG-WSV2-02

**Tags:** `SmartLoyalty`, `Azure`, `SEGURIDAD`, `SRE`, `INFRADEVOPS`, `PROD`

## Resumen

El balanceador de carga `SFCG-WSV2-LB` (Azure Standard Load Balancer, servicio WebServiceV2) no
entregaba tráfico real de clientes a la VM `SFCG-WSV2-02`, pese a que su health probe se reportaba
saludable en todo momento. Las conexiones reales de clientes hacia `SFCG-WSV2-02` fallaban con timeout
de conexión TCP (sin SYN-ACK), mientras que `SFCG-WSV2-01` recibía la totalidad del tráfico real desde
su aprovisionamiento. La causa fue una regla de Network Security Group a nivel de subnet que nunca
incluyó la IP privada de `SFCG-WSV2-02` en su lista de destinos permitidos. Corregido y verificado el
2026-08-27.

## Tabla resumen

| Campo | Valor |
|---|---|
| Ticket Jira | [GITIN-1238](https://smartit-ar.atlassian.net/browse/GITIN-1238) |
| Caso | `SFCG-WSV2-LB` no enrutaba tráfico real de clientes a `SFCG-WSV2-02` |
| Plataforma | Azure — Load Balancer / Network Security Group (`sfcgnetsec01`) |
| Severidad | Media — sin redundancia real en `SFCG-WSV2-02` desde su aprovisionamiento; sin incidente de caída de servicio reportado, ya que `SFCG-WSV2-01` absorbió el tráfico completo |
| Detectado | Reportado originalmente en el ticket (fecha exacta no registrada en este evento); investigación retomada el 2026-08-26 |
| Resuelto | 2026-08-27 |
| Responsable | Dante Paniagua |

## Causa raíz

La regla `WebService_V2_PRO` del NSG `sfcgnetsec01` (aplicado a nivel de subnet DMZ, compartido con
`SFCG-MOBI-LB`) permite tráfico entrante TCP al puerto 8080 únicamente hacia una lista fija de
direcciones IP de destino (`192.168.50.171` y `192.168.50.173`), sin incluir nunca la IP privada de
`SFCG-WSV2-02` (`192.168.50.172`). El tráfico de sondeo de salud de Azure (origen `168.63.129.16`)
omite la evaluación de NSG, por lo que el probe de `SFCG-WSV2-02` se reportaba saludable en todo
momento, mientras que las conexiones TCP reales de clientes eran descartadas silenciosamente por la
regla `DenyAllInBound` por defecto — reproduciendo exactamente el síntoma original reportado (timeout
de conexión, sin SYN-ACK, pese a un probe saludable). La configuración del propio Load Balancer
(reglas, probes, membresía del backend pool, propiedades de NIC) fue siempre simétrica entre ambas
VMs; la asimetría real nunca estuvo en el LB.

## Hallazgos

| # | Hallazgo | Riesgo |
|---|---|---|
| H1 | La regla `WebService_V2_PRO` en el NSG `sfcgnetsec01` nunca incluyó `192.168.50.172` (`SFCG-WSV2-02`) en su lista de IPs de destino permitidas para el puerto 8080 | Alto |

## Recursos afectados

| Recurso | Detalle |
|---|---|
| `SFCG-WSV2-LB` | Load Balancer (Standard SKU) |
| `SFCG-WSV2-01` | `Standard_D8as_v5` — no afectada, recibía la totalidad del tráfico real |
| `SFCG-WSV2-02` | `Standard_D2ds_v4` — afectada, sin redundancia real desde su aprovisionamiento |
| `sfcgnetsec01` | NSG a nivel de subnet DMZ — contiene la regla corregida |

## Métricas del evento

| Métrica | Valor |
|---|---|
| VMs en el backend pool | 2 (`SFCG-WSV2-01`, `SFCG-WSV2-02`) |
| IP agregada a la regla NSG | `192.168.50.172` |
| Regla NSG corregida | `WebService_V2_PRO` (`sfcgnetsec01`) |
| Verificaciones post-corrección | `test-ip-flow` → `Allow`; prueba aislada de LB (pool de un solo backend) → `200 OK`; tráfico real de producción (`grido.pos.smartfran.com`) confirmado en logs IIS de `SFCG-WSV2-02` |
| Ventana de investigación (UTC) | 2026-08-26 a 2026-08-27 |

## Comandos ejecutados

Historial completo de diagnóstico en `investigation.md`. Comandos centrales:

| # | Comando | Propósito |
|---|---|---|
| C1 | `az network watcher test-ip-flow` | Confirmar directamente, vía el plano de control de Azure, si el NSG permite o deniega el flujo real hacia `SFCG-WSV2-02` |
| C2 | `az network nsg rule list --nsg-name sfcgnetsec01` | Listar las reglas del NSG de subnet para identificar la regla relevante al puerto 8080 |
| C3 | `az network nsg rule show --name WebService_V2_PRO` | Obtener el detalle completo de la regla, revelando la lista fija de IPs de destino |
| C4 | `az network nsg rule update` (`destinationAddressPrefixes`) | Aplicar la corrección — agregar `192.168.50.172` |
| C5 | `az monitor metrics list --metric DipAvailability` | Verificar el estado de salud del probe por VM a lo largo de la investigación |

## Acciones propuestas

1. (Realizado) Se agregó `192.168.50.172` a la lista de destinos de la regla `WebService_V2_PRO` en `sfcgnetsec01`.
2. (Realizado) Se verificó el restablecimiento del tráfico real hacia `SFCG-WSV2-02` mediante `test-ip-flow`, una prueba aislada de LB y confirmación de tráfico real de producción en los logs de IIS.
3. (Realizado) Se clonó el monitoreo de Zabbix de `SFCG-WSV2-01` hacia `SFCG-WSV2-02` (mismas plantillas y macros), y se creó una ventana de mantenimiento diaria (00:00–09:00 UTC-3) para evitar falsas alarmas durante el apagado nocturno programado de `SFCG-WSV2-02`.
4. (Pendiente) Confirmar el propósito de la IP `192.168.50.174`, agregada a la misma regla en la misma edición.
5. (Pendiente) Migrar el despliegue de `SmartLoyalty.WebServiceV2` en `SFCG-WSV2-02` desde `D:\` (disco temporal efímero de Azure) a almacenamiento persistente, para evitar pérdida de configuración/despliegue ante un futuro `deallocate`.
6. (Pendiente, opcional) Reintentar el cambio del probe de salud a `/healthcheck.ashx` (protocolo HTTPS) luego de revisar los bindings de sitio IIS en `SFCG-WSV2-02` para solicitudes dirigidas por IP — un intento realizado durante esta investigación fue revertido tras causar una degradación de disponibilidad de ~6 minutos en `SFCG-WSV2-02`, sin impacto en producción.

## Monitoreo (Zabbix)

Como cierre de la incorporación de `SFCG-WSV2-02`, se clonó su configuración de monitoreo desde
`SFCG-WSV2-01` (mismas plantillas `IIS by Zabbix agent active` y `Windows by Zabbix agent active`,
mismas macros de host) y se confirmó la llegada de datos reales y actuales. Dado que `SFCG-WSV2-02`
no permanece encendida las 24 horas como `-01` (apagado programado 00:00–09:00 UTC-3), se creó una
ventana de mantenimiento dedicada para esa franja horaria — evita falsas alarmas por el apagado
intencional sin necesidad de modificar ningún disparador (trigger) existente.

## Archivos de evidencia

| Archivo | Contenido |
|---|---|
| `investigation.md` | Registro completo de la investigación, hipótesis descartadas y evidencia técnica |
| `vm1_effective_nsg.json` | NSG efectivo de `SFCG-WSV2-01` |
| `vm1_effective_routes.json` | Tabla de rutas efectiva de `SFCG-WSV2-01` |
| `vm2_boot_log.txt` | Log de consola serial de `SFCG-WSV2-02` durante un reinicio |
| `vm2_effective_nsg.json` | Intento de captura fallido (VM detenida en ese momento) — vacío |
| `vm2_effective_routes.json` | Intento de captura fallido (VM detenida en ese momento) — vacío |

## Hallazgos secundarios

- El disco `D:\` de `SFCG-WSV2-02` es un disco temporal de Azure (no persistente), propio del SKU
  `Standard_D2ds_v4`. El despliegue de `SmartLoyalty.WebServiceV2` reside en ese disco, por lo que
  cualquier `deallocate` futuro lo perderá — riesgo operativo real, no corregido en este ticket.
- Se detectó y corrigió un bug de configuración separado en `SFCG-WSV2-02`: el atributo
  `maxTraceFileSizeKb` en `web.config` (case incorrecto; el listener lo requiere como
  `MaxTraceFileSizeKb`) causaba errores 500 en `SaleProvider/QueryActivePromotionV3`. Corregido
  durante la investigación, sin relación con la causa raíz de este ticket.
- La hipótesis original del ticket (TrustedLaunch/Gen2 interfiriendo con el manejo de tráfico de red)
  no fue confirmada como causa — el problema fue exclusivamente de NSG.
- Se agregó `192.168.50.174` a la misma regla NSG durante la corrección; su propósito no fue
  confirmado en esta investigación.
