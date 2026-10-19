# Eventos — 20261008_gsfc925-code-smells

## 2026-10-08 15:44 — Actualización de refs remotas y búsqueda de la rama de GSFC-925

**Comando:** C1 — `git fetch --all --prune` y listado de ramas `*925*` (`scripts.sh`)
**Resultado:**
He actualizado las refs de todos los remotos sin tocar el árbol de trabajo, que sigue en `main`. Apareció `origin/feature/gsfc-925` en `74fdf5b4b` (2026-10-06). Salidas en `data/git-fetch.txt` y `data/git-branches-925.txt`.

He confirmado que la rama existe y que su punta ya es ancestro de `origin/dev`, por lo que la comparación contra `dev` no muestra diferencias y he revisado sus 6 commits propios.

## 2026-10-08 15:54 — Revisión del código de la rama y de los commits de septiembre

He revisado en profundidad el hasher del PIN, el limitador de intentos, el servicio de PIN, el servicio de autorización, el controlador y el grant de la rama, a partir de sus commits y sin construir ni ejecutar nada. He registrado en `investigation.md` 5 riesgos (reinicio de contadores al acertar un PIN, contadores sin atomicidad, claves controladas desde el body, consumo no atómico del grant y costo de las verificaciones de PBKDF2) y varios olores de código. Después he recorrido los 31 commits de septiembre del mismo autor, todos presentes en `origin/main`, con un barrido de patrones sobre las líneas agregadas y con la lectura completa de `PlatformTenantDirectory` y `MoneyWarehouseBalanceReconciler`: un `LogError` sin placeholder que descarta el mensaje de la excepción, escrituras de anotaciones que fallan en silencio y falta de propagación del token de cancelación en las consultas pesadas. No he leído los archivos del POS, de facturación ni de migración.
