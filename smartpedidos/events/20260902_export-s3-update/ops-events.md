# Eventos — 20260902_export-s3-update

## 2026-09-02 — Apertura del ticket, alcance corregido

Se confirmó GITIN-1983 ("[SP] Actualización de Export -> S3", subtarea de GITIN-1872) como el ticket que registra formalmente la ausencia de los campos `originalId`/`displayId`/`canje` en el export de `mongo-to-s3-CFN-ScheduledMongoToS3-1EZXBGD94CJVO` y la actualización de la Lambda que los agregó. He descartado un primer intento de alcance centrado en el vacío de datos permanente del 16/08 — ese hallazgo pertenece a GITIN-1970, no a este ticket. He redactado `investigation.md` y `ops.md` referenciando la evidencia completa ya presente en `20260831_lambda-s3-export-utc3/`, sin duplicarla.
