#!/usr/bin/env bash
# Event: 20260818_disk-flood-watermark
# OpenSearch flood-stage watermark en sfcloud-monitoreo (Graylog SmartCloud) — pérdida de mensajes en journal
# Host objetivo: sfcloud-monitoreo.smartfran.com
# Auth Graylog API: token en $GRAYLOG_API_KEY (basic auth, password literal "token")
# ⚠️ ACTION commands are clearly marked

GRAYLOG_URL="http://127.0.0.1:9000"
OS_URL="http://127.0.0.1:9200"

# === INVESTIGATION ===

# C1 — uso de disco real (filesystem) y por nodo (OpenSearch)
df -h /var/lib/opensearch
curl -s "$OS_URL/_cat/allocation?v"

# C1 — índices ordenados por tamaño / estado del cluster
curl -s "$OS_URL/_cat/indices?v&s=store.size:desc"
curl -s "$OS_URL/_cluster/health?pretty"

# C4 — retention/rotation strategy de los index sets de Sales y Business
curl -s -u "$GRAYLOG_API_KEY:token" -H "Accept: application/json" \
  "$GRAYLOG_URL/api/system/indices/index_sets?limit=0" \
  | python3 -c "
import json, sys
data = json.load(sys.stdin)
for s in data['index_sets']:
    if 'sales' in s['index_prefix'].lower() or 'business' in s['index_prefix'].lower():
        print(s['title'], '-', s['index_prefix'])
        print(' rotation:', s['rotation_strategy_class'], s['rotation_strategy'])
        print(' retention:', s['retention_strategy_class'], s['retention_strategy'])
"
# Resultado: SFC-Sales-prod y SFC-Business-prod, ambos TimeBasedSizeOptimizingStrategy
# (P30D-P40D) + DeletionRetentionStrategy (max_number_of_indices: 20) — con solo 4
# índices por set, la retención automática no purga nada en plazo útil. No es la causa raíz.

# C5 — rangos de fecha real por índice (para identificar candidatos a limpieza por antigüedad)
# ⚠️ business__9 y sales__4 (índices activos, no rotados) muestran begin/end epoch
# (1970-01-01) — NO indica antigüedad real, indica que Graylog no calculó su rango
# todavía. No tratar como "viejos".
curl -s -u "$GRAYLOG_API_KEY:token" -H "Accept: application/json" \
  "$GRAYLOG_URL/api/system/indices/ranges?limit=0" \
  | python3 -c "
import json, sys
data = json.load(sys.stdin)
cutoff = '2026-08-03T00:00:00.000Z'  # 15 días antes de 2026-08-18
for r in data['ranges']:
    name = r['index_name']
    if 'sales' in name.lower() or 'business' in name.lower():
        older = r['end'] < cutoff
        print(name, '| begin:', r['begin'], '| end:', r['end'], '| older than 15d:', older)
"

# C7 — verificar filesystem de la partición OpenSearch (antes de resize)
lsblk /dev/nvme0n3
lsblk -f /dev/nvme0n3p1


# === REMEDIATION ===

# ⚠️ C2 — levantar el bloqueo read_only_allow_delete
# Seguro de ejecutar cuando el uso de disco ya está por debajo del flood
# watermark (95%) — no requiere liberar espacio primero.
curl -s -X PUT "$OS_URL/_all/_settings" \
  -H 'Content-Type: application/json' \
  -d '{"index.blocks.read_only_allow_delete": null}'
# Resultado: {"acknowledged":true}

# ⚠️ C6 — eliminar índices rotados que exceden el corte de 15 días
# Candidatos reales (excluyendo los falsos positivos epoch de C5):
#   sales__1 (end 2026-07-23, 5gb), sales__2 (end 2026-08-02, 7.8gb),
#   business__6 (end 2026-07-31, 5.2gb) — total ~18gb
# NUNCA incluir sales__4 / business__9 (índices activos de escritura).
# Endpoint correcto: /api/system/indexer/indices/{index} (NO
# /api/system/indices/{index} — ese es para index sets, devuelve 404).
for idx in sales__1 sales__2 business__6; do
  echo "== $idx =="
  curl -s -o /dev/null -w "%{http_code}\n" -u "$GRAYLOG_API_KEY:token" -X DELETE -H "X-Requested-By: cli" \
    "$GRAYLOG_URL/api/system/indexer/indices/${idx}"
done
# Resultado: 204 en los tres. Disco pasó de 92% a 80% (118gb -> 102gb usados).

# ⚠️ C8 — resize de disco OpenSearch 128gb -> 512gb
# Resize del managed disk en Azure ejecutado manualmente por el usuario
# (fuera de Terraform, sin deallocate de VM). Los dos comandos siguientes
# expanden la partición y el filesystem XFS para usar el nuevo tamaño.
# Operación en caliente, no requiere detener OpenSearch.
sudo growpart /dev/nvme0n3 1
sudo xfs_growfs /var/lib/opensearch
# Resultado: partición 268.304.384 -> 1.073.676.255 sectores,
# XFS 33.538.048 -> 134.209.531 data blocks (4x, coincide con 128->512gb).
# Pendiente: reconciliar terraform.tfstate/main.tf (sigue en phase=pilot/128gb).


# === AUDIT ===

# C1 — confirmar espacio real tras remediation
df -h /var/lib/opensearch
curl -s "$OS_URL/_cat/allocation?v"
curl -s "$OS_URL/_cat/indices?v&s=store.size:desc" | head -10

# Pendiente (H10, sin confirmar todavía): notificaciones activas en vivo en
# Graylog (no confundir con el historial de alertas de la UI, que conserva
# el timestamp de disparo original aunque la condición ya se haya resuelto),
# y si dev__3 se creó tras levantar el bloqueo.
curl -s -u "$GRAYLOG_API_KEY:token" "$GRAYLOG_URL/api/system/notifications" | python3 -m json.tool
curl -s "$OS_URL/_cat/indices/dev*?v"
