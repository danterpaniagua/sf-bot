# GITIN-2315 Node 20 -> 22 upgrade

**Tags:** Operaciones, SRE

## Qué pasó
- Los servicios `platformsService` y `concentradorService` de SmartPedidos construyen su imagen sobre `node:20.20-alpine` en la rama `develop` (lectura del código, no de producción).
- El release de seguridad de Node.js del 21/10 corrigió las líneas 26, 24 y 22 (26.12.1, 24.22.1 y 22.23.4). Node 20 no figura entre ellas: el aviso indica que las versiones sin soporte siempre quedan afectadas y no publica corrección para ellas.