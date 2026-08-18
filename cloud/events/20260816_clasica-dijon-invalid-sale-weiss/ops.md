**Tags:** SmartCloud

## Resumen

En Weiss Punta del Este, la promoción "Promo para compartir - Dijon" muestra 3 opciones de hamburguesa en lugar de las 2 esperadas al canal de PedidosYa, generando confusión en el armado del pedido para el cliente. El caso fue reportado por CaC. La investigación determinó que la configuración de la promoción en SmartFran Cloud (`Business_WEISS`) y el armado del combo en el POS interno son correctos; la duplicación se origina en la configuración propia del catálogo de PedidosYa, externa a SmartFran.

## Tabla resumen

| Campo | Valor |
|---|---|
| Ticket Jira | GSFC-XXX (placeholder — reemplazar por el ID real antes de uso externo) |
| ID alerta | N/A (reporte de CaC, no alerta automática) |
| Sistema | SmartFran Cloud (WEISS) / PedidosYa |
| Severidad | Baja (no bloquea la venta; afecta experiencia de selección en el canal externo) |
| Detectado | No informado por CaC con fecha/hora exacta |
| Resuelto | Pendiente — causa raíz es externa a SmartFran, corrección debe aplicarse en PedidosYa |
| Responsable | Dante Paniagua, SRE (investigación) |

## Causa raíz

El ítem "Clasica con Dijon 2" aparece duplicado en la ficha de producto de la promoción dentro de la app de PedidosYa, generando 3 filas de selección de hamburguesa en lugar de 2. Se confirmó que esta duplicación no proviene de `Business_WEISS`/`Catalog_WEISS` (la configuración de `PromotionGroups`/`PromotionDetails` para la promoción es correcta y sin duplicados) ni del armador de combos del POS interno de SmartFran Cloud (que renderiza la promoción correctamente). Tampoco existe en SmartPedidos código que publique o sincronice el catálogo/menú hacia PedidosYa — su integración con esa plataforma se limita al ciclo de vida de pedidos ya realizados. La causa raíz queda entonces circunscripta a la configuración propia del catálogo de PedidosYa, gestionada fuera de los sistemas de SmartFran.

## Hallazgos

| # | Hallazgo | Riesgo |
|---|---|---|
| H1 | `Business_WEISS.PromotionGroups`/`PromotionDetails` para la Promoción 212 ("Promo para compartir - Dijon") están correctamente configurados: 4 grupos, cada uno con un único artículo elegible, sin duplicados | Bajo |
| H2 | El armador de combo del POS interno (`DialogBuildCombo.razor.cs`) renderiza la promoción correctamente, confirmado por captura de pantalla y por trazabilidad de código fuente contra la rama de producción (`main`) | Bajo |
| H3 | No existe en `repo/SmartFran.Cloud` código de exportación o sincronización de catálogo/menú hacia PedidosYa; el único código relacionado son enums de logging para pedidos entrantes | Bajo |
| H4 | La integración de SmartPedidos (`platforms-service`/`concentrador-service`) con PedidosYa cubre únicamente el ciclo de vida de pedidos (recepción, confirmación, rechazo, despacho); no existe código de publicación de menú/catálogo (`grep` de "menu" sin resultados en ambos repositorios) | Bajo |
| H5 | El ítem "Clasica con Dijon 2" aparece duplicado en la ficha de producto dentro de la app de PedidosYa — causa raíz confirmada como externa a SmartFran | Medio |

## Recursos afectados

| Recurso | Detalle |
|---|---|
| Tenant | WEISS |
| Franquicia | Weiss Punta del Este |
| Promoción | "Promo para compartir - Dijon" (Id 212, `Business_WEISS.Promotions`) |
| Canal afectado | PedidosYa (app móvil) |

## Comandos ejecutados

Ver `scripts.sh` para el detalle completo.

| # | Comando / Script | Propósito |
|---|---|---|
| C1 | Localizar promoción por nombre | Ubicar "Promo para compartir - Dijon" en `Business_WEISS.Promotions` |
| C2 | Grupos y artículos elegibles | Verificar `PromotionGroups`/`PromotionDetails` de la Promoción 212 |
| C3 | Identidad de artículos | Resolver ArticleId 85/12 en `Catalog_WEISS.Items` |
| C4 | Contenido del grupo "Signature Burgers" | Descartar como origen de las "3 opciones" |
| C5 | Introspección de esquema `Oversales` | Obtener nombres reales de tablas/columnas del sistema de upsell |
| C6 | Trigger de upsell para ArticleId 85 | Descartar el sistema de upsell (`Oversales`) como causa |
| C7 | Alcance de `PromotionApplies` | Verificar franquicia/lista de precios de las Promociones 39, 52, 212 |
| C8 | Actualización y verificación del repo local | Sincronizar `cloud/repo/SmartFran.Cloud` y confirmar que el código relevante es idéntico entre `main` y `dev` |
| C9 | Búsqueda de integración de catálogo con PedidosYa | Confirmar ausencia de código de exportación de menú en `repo/SmartFran.Cloud` y en los repositorios de SmartPedidos |

## Acciones propuestas

1. Reportar la duplicación del ítem "Clasica con Dijon 2" al responsable de la configuración del catálogo de PedidosYa para Weiss Punta del Este (equipo de canales digitales o soporte de PedidosYa), para su corrección directamente en esa plataforma.
2. No se requiere ninguna acción sobre `Business_WEISS`/`Catalog_WEISS` ni sobre el POS interno de SmartFran Cloud — la configuración es correcta.
3. Actualizar el ticket con el ID real de Jira en reemplazo del placeholder `GSFC-XXX` antes de cualquier comunicación externa.

## Hallazgos secundarios

- Se detectaron 3 promociones activas simultáneamente para "Clasica con Dijon" (Id 39, 52, 212), todas con `Include=True`, `PriceListId=912` y sin restricción de franquicia, activadas dentro de una ventana de 3 minutos el 2026-07-29. No se confirmó que esto sea la causa del defecto reportado, pero vale la pena que el equipo de Business/Catálogo revise si las tres promociones deben coexistir activas o si 39/52 son remanentes de la reactivación del 2026-07-29.
- El clon local `cloud/repo/SmartFran.Cloud` estaba 13 commits detrás de `origin/dev`; fue actualizado durante esta investigación.
