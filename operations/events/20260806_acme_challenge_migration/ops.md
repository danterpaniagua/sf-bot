# 20260806_acme_challenge_migration

**Tags:** Operaciones, SmartLoyalty, Azure, DNS, SSL

## Resumen

El 06/08/2026 se implementó la renovación automática y completamente desatendida del certificado SSL de MobileAppService (`mobileservice.clubgrido.com.ar:8043`), delegando el subdominio `_acme-challenge.mobileservice.clubgrido.com.ar` a una zona de Azure DNS y reconfigurando win-acme en `SFCG-MOBI-01` y `SFCG-MOBI-02` para validar renovaciones contra esa zona. Esto elimina el paso manual de validación DNS-01 (registro TXT agregado a mano) usado como solución temporal desde el 04/08/2026 (`GITIN-1786`), y resuelve de forma definitiva el bloqueador original de `GITIN-1758` (certificado sin renovación automática vigente).

## Tabla resumen

| Campo | Valor |
|---|---|
| Ticket Jira | [GITIN-1774](https://smartit-ar.atlassian.net/browse/GITIN-1774) |
| Historia | [GITIN-1768](https://smartit-ar.atlassian.net/browse/GITIN-1768) — Automatización de renovación de certificados SSL |
| Bloquea | [GITIN-1758](https://smartit-ar.atlassian.net/browse/GITIN-1758) |
| Sistema | MobileAppService (`SFCG-MOBI-01`/`SFCG-MOBI-02`), Azure DNS, GoDaddy |
| Severidad | N/A (tarea de automatización, no incidente) |
| Iniciado | 06/08/2026 |
| Resuelto | 06/08/2026 |
| Responsable | SRE |

## Causa raíz

La renovación automática no podía implementarse vía el plugin GoDaddy de win-acme porque la cuenta de GoDaddy no tiene habilitado el acceso a su API de Domains (`403 ACCESS_DENIED`, confirmado el 04/08/2026, sin ETA de resolución). La validación HTTP-01 tampoco es viable porque el Load Balancer de MobileAppService no tiene ninguna regla de puerto 80/443. La solución fue delegar únicamente el subdominio `_acme-challenge.mobileservice.clubgrido.com.ar` (vía un único registro NS en GoDaddy) a una zona de Azure DNS, y usar el plugin de validación DNS-01 de Azure DNS de win-acme contra esa zona — evita por completo la dependencia de la API de GoDaddy, sin tocar ningún otro registro DNS del dominio.

## Hallazgos

| # | Hallazgo | Riesgo |
|---|---|---|
| H1 | El plugin de validación DNS-01 de Azure DNS no estaba instalado en ninguna VM — solo se había descargado el build base de win-acme y el plugin de GoDaddy (inútil por el bloqueo de API). Es un paquete separado que debe descargarse aparte | Bajo |
| H2 | El primer intento de descarga del plugin usó un nombre de archivo adivinado y devolvió 404 — el nombre real (`plugin.validation.dns.azure.v2.2.9.1701.zip`) se confirmó contra la API de GitHub, no por prueba y error adicional | Bajo |
| H3 | `az ad sp create-for-rbac` no acepta `--subscription` — a diferencia de la mayoría de comandos `az`, las operaciones `az ad` son de nivel tenant/Azure AD, no de suscripción | Informativo |
| H4 | El texto `[Manual]` en la salida de `wacs.exe` corresponde al plugin de **Source** (entrada manual del hostname), no al de **Validation** — no es señal de que la validación manual siga activa; puede confundirse fácilmente al leer la salida | Bajo |

## Recursos afectados

| Componente | Impacto |
|---|---|
| `SFCG-MOBI-01` / `SFCG-MOBI-02` | Renovación de certificado reconfigurada — ahora completamente desatendida, sin cambios de disponibilidad del servicio durante la implementación |
| Zona Azure DNS `_acme-challenge.mobileservice.clubgrido.com.ar` | Recurso nuevo, resource group `DefaultGroup01` |
| Service Principal `winacme-mobileservice-dns` | Credencial nueva, compartida entre ambas VMs, rol `DNS Zone Contributor` acotado a la zona anterior únicamente |
| DNS de `clubgrido.com.ar` (GoDaddy) | Un único registro NS agregado para el host `_acme-challenge.mobileservice` — ningún otro registro del dominio fue tocado |

## Comandos ejecutados

| # | Comando / Script | Propósito |
|---|---|---|
| C1 | `az network dns zone create` | ⚠️ Crear la zona Azure DNS para la delegación |
| C2 | `az network dns zone show` | Obtener los nameservers asignados |
| C3 | `az ad sp create-for-rbac` | ⚠️ Crear el Service Principal para win-acme |
| C4 | `az role assignment create` | ⚠️ Otorgar `DNS Zone Contributor` sobre la zona |
| C5 | `dig` | Confirmar que la delegación NS está activa |
| C6 | Descarga/instalación del plugin Azure DNS (PowerShell) | ⚠️ Instalar el plugin en cada VM |
| C7 | `wacs.exe` interactivo (Manage renewals → Edit → Validation) | ⚠️ Reconfigurar la renovación existente en cada VM |
| C8 | Visor de Eventos (Task Scheduler) | Confirmar ejecución desatendida exitosa de la tarea programada |
| C9 | `Get-ChildItem Cert:\LocalMachine\WebHosting` | Confirmar thumbprint/fechas del certificado nuevo en cada VM |
| C10 | `openssl s_client` | Verificar el certificado servido en el endpoint público |

Detalle completo en `scripts.sh`.

## Acciones propuestas

1. **(SRE, ya aplicada)** Documentado el procedimiento completo en `operations/docs/mobileappservice_ssl_renewal_runbook.md` (sección 5), reemplazando el plan pendiente por los pasos reales ejecutados.
2. **(SRE)** Confirmar que la renovación automática real (no forzada) funcione correctamente cuando el certificado entre en su ventana de renovación (~30 días antes del 2026-11-04) — sin acción manual esperada, pero sin verificación de un ciclo completo todavía.
3. **(SRE, pendiente de decisión)** Evaluar si el mismo mecanismo (zona Azure DNS delegada + Service Principal + plugin) se replica para `GITIN-1769`/`1770`/`1771` (ClubSite PY/AR, WebSite) — estos tres tienen un bloqueador propio sin resolver (certificados en `WAF_APPs` no integrados con Key Vault) antes de que la validación DNS por sí sola alcance para automatizarlos.
4. **(SRE, pendiente)** Guardar el client secret del Service Principal en un gestor de secretos formal — actualmente solo se sabe que está guardado "fuera de este repo", sin un lugar específico documentado.
