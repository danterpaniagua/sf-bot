# dd-mm-yyyy — Plan actualización SmartPedidos (padre)

**Tags:** SmartPedidos

## Resumen

[GITIN-2107](https://smartit-ar.atlassian.net/browse/GITIN-2107) ("[SP] Plan actualización SmartPedidos") es la historia padre que agrupa la actualización de paquetes NPM de los tres componentes de SmartPedidos, dividida en una subtarea por servicio.

## Tabla resumen

| Campo | Valor |
|---|---|
| Ticket Jira | [GITIN-2107](https://smartit-ar.atlassian.net/browse/GITIN-2107) |
| Tipo | Historia padre |
| % Completado | 0% |
| Responsable | Dev |

## Subtareas

| Subtarea | Componente | Estado | Detalle |
|---|---|---|---|
| [GITIN-2116](https://smartit-ar.atlassian.net/browse/GITIN-2116) | Platform | Backlog | Diagnóstico completo (compatibilidad Node 20 + CVEs, 33 dependencias directas). Hallazgos y acciones propuestas ya redactados en el ticket. Remediación (bump de versiones) aún no aplicada. |
| [GITIN-2117](https://smartit-ar.atlassian.net/browse/GITIN-2117) | Concentrador | Backlog | No iniciado. |
| [GITIN-2118](https://smartit-ar.atlassian.net/browse/GITIN-2118) | BBOO | Backlog | No iniciado. |

## Próximos pasos

Orden de prioridad: **Platform (GITIN-2116) primero.**

1. GITIN-2116 (Platform) — aplicar la remediación (bump de `axios`, `express-jwt`, `jsonwebtoken`, `uuid`) y validar antes de cerrar esta subtarea. Único diagnóstico completo hasta el momento.
2. GITIN-2117 (Concentrador) y GITIN-2118 (BBOO) — iniciar diagnóstico una vez cerrada GITIN-2116.
