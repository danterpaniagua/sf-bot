#!/usr/bin/env bash
# C4: read-only. Lists the cluster-config classes of the instance and prints those that look user/token/permission related.
# Usage: scripts-cluster-config.sh <graylog-base-url> <token-env-var-name>
# Output goes to stdout; the caller redirects it to .../data/
set -euo pipefail
BASE="${1:?graylog base url}"
TOKVAR="${2:?name of the env var holding the API token}"
TOKEN="${!TOKVAR:?env var $TOKVAR is not set}"
OUT="$(mktemp)"
CODE="$(curl -sS -m 30 -o "$OUT" -w '%{http_code}' -u "${TOKEN}:token" -H 'Accept: application/json' -H 'X-Requested-By: cli' "${BASE}/api/system/cluster_config" || echo 000)"
[ "$CODE" = "200" ] || { echo "ERROR: GET /api/system/cluster_config -> HTTP ${CODE}"; head -c 200 "$OUT"; rm -f "$OUT"; exit 1; }
echo "== all classes"
jq -r '(.classes // .)[]' "$OUT" | sort
echo "== user/token/permission related"
jq -r '(.classes // .)[]' "$OUT" | grep -iE 'user|token|permission|role|account|auth' | sort || echo "(none)"
rm -f "$OUT"
