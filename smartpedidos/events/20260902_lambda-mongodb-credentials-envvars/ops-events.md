# Eventos — 20260902_lambda-mongodb-credentials-envvars

## 2026-09-02 — Apertura del ticket, dos intentos de conexión descartados antes de confirmar el alcance real

He intentado dos veces conectar GITIN-1973 con investigaciones equivocadas antes de confirmar su alcance real: primero con `20260720_credenciales-mongodb-hardcodeadas/` (credenciales en `concentrador-service`/`platforms-service`, revertido), luego asumiendo que se refería al bug de interpolación de `connString` ya corregido bajo GITIN-1970. El alcance real: la cadena de conexión a MongoDB de `mongo-to-s3-CFN-ScheduledMongoToS3-1EZXBGD94CJVO` estaba originalmente hardcodeada en texto plano, y fue migrada a variables de entorno — un hallazgo distinto de ambos intentos anteriores. He creado `investigation.md` y `ops.md` documentando esto como reportado, sin evidencia propia de la versión original en texto plano.
