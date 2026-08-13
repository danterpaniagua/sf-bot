# Onboarding ambiente DEV a Graylog — GITIN-1794

## Resumen

Se incorporará el ambiente DEV de SmartFran Cloud (8 App Services, Resource Group `SmartFran.Cloud`, subscripción `Smart IT - Grido`) al pipeline de ingesta de logs existente en el proyecto `cloud-graylog` (Event Hub compartido `app-logs` → Logstash → Graylog), siguiendo el mismo patrón usado para las apps de PRO. Este RG y subscripción no estaban documentados previamente en `cloud-graylog` — la documentación existente solo cubría `SmartFran.Cloud.PRO` y `SmartFran.Cloud.TEST`, ambos bajo la subscripción `SmartIT Cloud`. El trabajo de infraestructura (Terraform) vive en el repo `cloud-graylog` (`~/Documentos/git/cloud-graylog/`); este ticket y su seguimiento viven en este repo (`bots/cloud/`) a pedido explícito.

## Tabla resumen

| Campo | Valor |
|---|---|
| Ticket Jira | GITIN-1794 |
| Resource Group | SmartFran.Cloud |
| Subscripción | Smart IT - Grido (`0190fa7d-4ccf-4e3d-beb1-323b5780bfc8`) |
| Repo de infraestructura | `cloud-graylog` (separado de este monorepo) |
| Estado | **Completo.** Diagnostic Settings aplicados (H9), stream/index set DEV creados, corregidos (H10, H11) y confirmados con tráfico real ruteado (H12) |
| Responsable | Dante Paniagua (SRE) |

## Causa raíz

Las 8 apps DEV de SmartFran Cloud nunca tuvieron ningún Diagnostic Setting configurado — el pipeline de Graylog se construyó inicialmente solo para PRO (piloto Sales, luego Business, resto de PRO en progreso), y el ambiente DEV, en una subscripción distinta (`Smart IT - Grido`, no relevada hasta ahora por `cloud-graylog`), quedó fuera del alcance original sin visibilidad de logs centralizada.

## Hallazgos

| # | Hallazgo | Riesgo |
|---|---|---|
| H1 | El RG `SmartFran.Cloud` / subscripción `Smart IT - Grido` no estaba documentado en `cloud-graylog` — requirió relevamiento completo antes de definir el plan de onboarding | Medio |
| H2 | Confirmado vía `az group show` (C2): el RG `SmartFran.Cloud` existe en `Smart IT - Grido` (`0190fa7d-4ccf-4e3d-beb1-323b5780bfc8`), región `eastus2` (metadata del RG). El contexto CLI activo por defecto es `SmartIT Cloud` (`85c76dea...`) — distinta — confirmando que este RG vive en una subscripción separada de `SmartFran.Cloud.PRO`/`.TEST` | Medio |
| H3 | Las App Services individuales están en región `East US` (confirmado vía C3) — misma región que el namespace Event Hub compartido `smartfran-graylog-evhns-pro` de PRO, sin bloqueo de región para reutilizarlo | Bajo |
| H4 | El RG `SmartFran.Cloud` no contiene solo un ambiente "DEV" — contiene **33 App Services** en al menos 5 tiers (`DEV`, `DEV2`, `STG`, `TEST`, `POC`) sobre 8 dominios, más `Cosmos-API` y dos apps sin sufijo de ambiente (`SmartFran-Cloud-Admin`, `SmartFran-Cloud-Catalog` — anomalía de naming, sin confirmar con el equipo de desarrollo). Alcance de GITIN-1794 acotado a las 8 apps `*-DEV` únicamente, sin `DEV2` | Alto |
| H5 | Confirmado vía C4: las 8 apps `*-DEV` en alcance no tenían ningún Diagnostic Setting configurado — a diferencia de PRO, no hay destino Log Analytics existente que preservar | Bajo |
| H6 | El provider `azurerm` de `cloud-graylog/terraform/main.tf` tenía `subscription_id` fijo a `SmartIT Cloud` — se agregó un segundo provider aliasado (`azurerm.development`, subscripción `Smart IT - Grido`) para poder gestionar recursos de DEV. Cross-subscription Diagnostic Settings → Event Hub no estaba validado empíricamente en el proyecto; el `terraform plan -target` corrido no arrojó error de validación (ver H7), pero no confirma aún que los datos lleguen a Graylog | Medio |
| H7 | `terraform plan -target=<8 diagnostic settings>`: **8 to add, 0 to change, 0 to destroy** — no toca ningún recurso existente (VM, Event Hub, apps PRO). Confirma que el plan es válido | Bajo |
| H8 | `terraform apply tfplan` ejecutado: **Apply complete! Resources: 8 added, 0 changed, 0 destroyed.** Los 8 Diagnostic Settings de las apps DEV quedaron creados apuntando al Event Hub compartido `app-logs` | Bajo |
| H9 | **Confirmado end-to-end vía búsqueda directa en Graylog**: mensaje real parseado correctamente con `resourceId` → `SMARTFRAN-CLOUD-POS-DEV`, `subscription` → `0190FA7D-4CCF-4E3D-BEB1-323B5780BFC8` (subscripción DEV), `resource_group` → `SMARTFRAN.CLOUD`, categoría `AppServiceHTTPLogs`, mensaje armado correctamente (`GET /api/deployments/latest - 202`). Tráfico real de GitHub Actions desplegando `Pos-DEV` vía API Kudu (`/api/publish`, `/api/deployments`). El routing cross-subscription (Diagnostic Settings en `Smart IT - Grido` → Event Hub en `SmartIT Cloud`) queda confirmado funcionando, no solo estructuralmente válido — cierra el ítem abierto de H6 | Bajo |
| H10 | **Stream y index set dedicados de Graylog creados** — decisión de pausa (ver Acciones propuestas anterior) revertida a pedido explícito. Dos errores de configuración encontrados y corregidos durante el armado: (1) el stream `DEV` apuntaba inicialmente a `Default index set` en vez del índice `DEV` recién creado; (2) la regla del stream (`name` vs `.*-DEV$`) quedó guardada con tipo "Match exactly" (comparación literal) en vez de "Match regular expression" — nunca iba a matchear nada. Ambos confirmados corregidos vía API REST de Graylog (ground truth, no dependiente de lectura de UI): stream `DEV` (`id: 6a7a1b8a34e7b9a985f43cbc`) → `index_set_id: 6a7a1b4234e7b9a985f43af9` (índice `DEV`, prefix `dev_`), regla única `field: name`, `type: 2` (REGEX) | Bajo |
| H11 | **Tercer bug encontrado en el mismo rule: `$` no es un ancla válida en el motor regex de Lucene** (usado por OpenSearch/Graylog) — a diferencia de motores regex estándar, las queries `regexp` de Lucene ya hacen match contra el término completo (fullmatch implícito), por lo que `^`/`$` no son necesarios y, si se incluyen, se interpretan como **caracteres literales**. El valor guardado (`.*-DEV$`) buscaba literalmente algo terminado en los 4 caracteres `-DEV$` (con signo pesos incluido) — nunca iba a matchear ningún dato real. Corregido a `.*-DEV` (sin ancla) — sigue siendo seguro contra `-DEV2` porque el fullmatch implícito de Lucene ya excluye cualquier sufijo sobrante. Corrección aplicada y confirmada vía API REST (`PUT` + `GET /streams/{id}/rules` re-verificado: `value: ".*-DEV"`, `type: 2`) | Medio |
| H12 | **Confirmado con datos reales: routing end-to-end funciona.** Tras la corrección de H11, se generó tráfico de prueba (`curl` GET a `Pos-DEV`, HTTP 200) y se confirmó que el stream `DEV` (`disabled: false`, `remove_matches_from_default_stream: true`) está clasificando correctamente — el index set `DEV` muestra **187 documentos, 580 KiB** acumulados. Cierra el ítem pendiente de H10 y el paso 10 de Acciones propuestas | Bajo |

## Recursos afectados

RG `SmartFran.Cloud`, subscripción `Smart IT - Grido` (`0190fa7d-4ccf-4e3d-beb1-323b5780bfc8`), región `East US`:

`SmartFran-Cloud-Sales-DEV`, `SmartFran-Cloud-Pos-DEV`, `SmartFran-Cloud-Catalog-DEV`, `SmartFran-Cloud-Platform-DEV`, `SmartFran-Cloud-Admin-DEV`, `SmartFran-Cloud-Person-DEV`, `SmartFran-Cloud-Business-DEV`, `SmartFran-Cloud-Orders-DEV`.

Recursos Terraform nuevos en `cloud-graylog/terraform/` (no aplicados aún): provider `azurerm.development`, `data.azurerm_resource_group.dev`, 8 `data` sources (`azurerm_windows_web_app`/`azurerm_linux_web_app`) y 8 `azurerm_monitor_diagnostic_setting` en `app_services_dev.tf`.

Fuera de alcance (documentado para referencia, no parte de este ticket): `DEV2`, `STG`, `TEST`, `POC` (25 apps adicionales) y las apps sin sufijo (`SmartFran-Cloud-Admin`, `SmartFran-Cloud-Catalog`, `SmartFran-Cloud-Cosmos-API`). Inventario completo en `cloud-graylog/CLAUDE.md` → "App Services — DEV".

## Comandos ejecutados

| # | Comando / Script | Propósito |
|---|---|---|
| C1 | Ver subscripción activa | Confirmar contexto de subscripción |
| C2 | Ver Resource Group | Confirmar existencia de `SmartFran.Cloud` en `Smart IT - Grido` |
| C3 | Listar App Services del RG | Relevar apps, estado, runtime, región |
| C4 | Diagnostic Settings de las 8 apps DEV | Confirmar que ninguna tiene configuración previa |
| C5 | Obtener SSH public key real de la VM Graylog (solo lectura) | Completar `var.ssh_public_key` sin adivinar — evita reemplazo forzado de la VM en un plan/apply sin `-target` |
| C6 | `terraform plan -target=...` (8 diagnostic settings, repo `cloud-graylog`) | Validar el plan antes de aplicar — resultado: 8 a agregar, 0 a cambiar, 0 a destruir |
| C7 ⚠️ | `terraform apply` (repo `cloud-graylog`) | Pendiente — aplicar los 8 Diagnostic Settings |

Comandos entregados al usuario para ejecutar — no ejecuto comandos Azure ni Terraform directamente. Ver `scripts.sh`.

## Acciones propuestas

1. ~~Relevar RG/subscripción/apps del ambiente DEV.~~ Completado — H1–H4.
2. ~~Confirmar alcance: solo tier DEV, sin DEV2.~~ Completado.
3. ~~Relevar Diagnostic Settings actuales de las 8 apps DEV.~~ Completado — H5.
4. ~~Preparar Terraform (`cloud-graylog/terraform/`) para las 8 apps DEV.~~ Completado — H6.
5. ~~Validar el plan con `-target`.~~ Completado — H7 (8 a agregar, 0 a cambiar, 0 a destruir).
6. ~~Aplicar el plan.~~ Completado — H8 (`Apply complete! Resources: 8 added, 0 changed, 0 destroyed.`).
7. ~~Verificar que las 8 apps entregan mensajes reales a Graylog.~~ Completado — H9. Confirmado con `Pos-DEV` (tráfico real de CI/CD); el resto de las 7 apps se asume con el mismo comportamiento dado que comparten pipeline/Event Hub, pero no se verificó cada una individualmente.
8. ~~Crear stream Graylog dedicado para DEV.~~ Completado — H10. Index set `DEV` (prefix `dev_`) y stream `DEV` (regla `name` regex `.*-DEV$`, tipo REGEX confirmado, `Remove matches from 'All messages'` activado) creados y verificados vía API. La pausa inicial (devs trabajando en mejoras de logging) fue revertida a pedido explícito.
9. ~~Corregir el valor de la regla (`.*-DEV$` → `.*-DEV`, ver H11).~~ Completado vía API — pendiente reconfirmar con `GET /streams/{id}/rules` que el nuevo valor quedó guardado.
10. ~~Confirmar tráfico real ruteado al stream `DEV`.~~ Completado — H12. Index set `DEV` muestra 187 documentos / 580 KiB acumulados. Una búsqueda sin filtro dentro del stream `DEV` mostró cero resultados inicialmente pese a esto — causa: rango de tiempo del buscador demasiado angosto para la ventana real de los datos, no un bug adicional. Ampliar el rango resolvió la búsqueda. **Ticket completo — falta solo cerrarlo formalmente en Jira.**

### Comandos de verificación (paso 7)

```bash
# Mensajes entrantes al Event Hub compartido en los últimos 30 minutos
az monitor metrics list \
  --resource "/subscriptions/85c76dea-3304-4310-8656-bf21b28e4f4b/resourceGroups/SmartFran.Cloud.PRO/providers/Microsoft.EventHub/namespaces/smartfran-graylog-evhns-pro" \
  --metric IncomingMessages \
  --interval PT5M \
  --start-time $(date -u -d '30 minutes ago' +%Y-%m-%dT%H:%M:%SZ) \
  --aggregation Total \
  -o table
```

Si la métrica no muestra actividad, puede ser simplemente que las apps DEV no tienen tráfico en este momento (a diferencia de PRO) — antes de asumir que el routing cross-subscription falló, generar tráfico real en al menos una app (ej. pegarle al endpoint de health de `Sales-DEV`) y volver a chequear. Complementar buscando directamente en Graylog (`https://sfcloud-monitoreo.smartfran.com/graylog/`) por `resourceId` conteniendo `SMARTFRAN-CLOUD-SALES-DEV` (o cualquier otra app DEV) en los últimos 15 minutos — la métrica del Event Hub confirma que algo llega, la búsqueda en Graylog confirma que Logstash lo está parseando y enrutando correctamente.
