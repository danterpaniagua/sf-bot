# GITIN-2267 — [SML] Análisis de índices: IX_CustomerPointsLog_Points

**Tags:** `SmartLoyalty`, `SQLServer`, `SRE`, `PROD`

## Qué pasó

- En la revisión de la base de datos de SmartLoyalty (GITIN-2251), el índice `IX_CustomerPointsLog_Points` de `Sml.CustomerPointsLog` (unos 10 GB) tuvo 338 búsquedas y 0 recorridos frente a 1.214.569 actualizaciones desde el reinicio del servicio del 2026-10-14 (lectura del 2026-10-19), es decir, mucho costo de escritura con muy poca lectura.
