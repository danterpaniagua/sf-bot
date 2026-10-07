# Eventos — 20260825_wholesale-service-infra-proposal

## 2026-08-25 14:52 — Revisión de propuesta de arquitectura y creación del ticket GITIN-1938

**Resultado:**
He creado `investigation.md` y `ops.md` para GITIN-1938. He revisado la propuesta de arquitectura recibida (dos fases) para desacoplar el nuevo servicio mayorista de la infraestructura retail compartida, contrastándola contra `cloud/docs/infrastructure.md`.

He identificado que la Fase 1 propuesta no mitiga el riesgo de acoplamiento (H3) y que hay desarrollo activo de APIs mayoristas dentro del App Service Plan compartido de retail (Etapa 0, H1), previo a cualquier fase de la propuesta. He confirmado que el nuevo AppService se aprovisionará sobre un Plan dedicado (H7) y que el set de apps mayorista usará su propia aplicación Auth0, sin compartir con el tenant Auth0 de retail (H6). He agregado la separación de pipeline de CI/CD a la Fase 2 (H2) y he documentado dos opciones reales para el aislamiento de gateway (H4): APIM dedicada + WAF compartido, o DNS directo sin APIM + WAF compartido, con statu quo como línea base sin costo — sin decisión tomada, WAF permanece compartido con retail en toda opción evaluada. He agregado diagramas Mermaid para Etapa 0, Fase 1, Fase 2 y la opción de DNS directo al ticket.

## 2026-08-25 14:57 — Elevación de riesgo por persistencia compartida (H6)

**Resultado:**
He confirmado que, en una primera instancia, la persistencia del servicio mayorista se maneja tal cual está — sin DB/CosmosDB dedicada, reutilizando la capa de datos compartida con retail.

He identificado este esquema como el patrón "shared database" (monolito distribuido a nivel de datos): aunque cómputo (H7) e identidad (Auth0, H6) ya están aislados, una única base de datos compartida reintroduce el mismo acoplamiento que esa separación buscaba eliminar — contención de capacidad (DTU/vCore o RU/s), bloqueos/corrupción de datos compartidos, acoplamiento de esquema entre migraciones de mayorista y retail, y backup/PITR conjunto, sin que un rollback de código pueda deshacer un incidente a este nivel. He elevado el riesgo de H6 de Medio a Alto en `ops.md` y he actualizado los diagramas de Fase 2 y de la opción DNS directo para reflejar la DB compartida sin aislar. He agregado como acción propuesta monitorear contención de capacidad en la DB compartida y definir un criterio de migración a persistencia dedicada si el riesgo se materializa.

## 2026-08-25 15:19 — Corrección: WAF y APIM no son infraestructura preexistente

**Resultado:**
He confirmado que WAF y APIM no son infraestructura compartida preexistente de retail, como había asumido hasta ahora a partir del texto de la propuesta original — son componentes nuevos que esta misma propuesta introduce, y `cloud/docs/infrastructure.md` nunca los lista como parte de la arquitectura actual. He confirmado además que en Etapa 0 no hay WAF ni APIM delante de nada, ni retail ni mayorista — ambos se acceden hoy en forma directa.

He reescrito la Causa raíz, los diagramas de Etapa 0/Fase 1/Fase 2 y de la Opción DNS directo, y los Hallazgos H1/H3/H4/H7 en `ops.md` para reflejar esto. He identificado que la APIM, tal como está redactada la propuesta, queda exclusiva del mayorista en ambas fases — nunca frente a retail — por lo que no es un eje de decisión real. El riesgo real pasa a ser distinto: la Fase 2, tal como está escrita, conecta el WAF a "toda la infraestructura cloud", sumando a retail por primera vez a un WAF compartido con el mayorista — un acoplamiento nuevo, no uno que ya existía. He redefinido las tres opciones de H4 sobre este eje (extender el WAF a retail vs. mantenerlo exclusivo del mayorista) y he actualizado las acciones propuestas 4/4a/4b/4c en consecuencia.
