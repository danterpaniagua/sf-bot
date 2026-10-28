#!/usr/bin/env bash
# C2: read-only. Lists every Graylog role with its read-only flag, permission count and token-related permissions.
# Usage: scripts-roles.sh <graylog-base-url> <token-env-var-name>
# Output goes to stdout; the caller redirects it to .../data/
set -euo pipefail
BASE="${1:?graylog base url}"
TOKVAR="${2:?name of the env var holding the API token}"
TOKEN="${!TOKVAR:?env var $TOKVAR is not set}"
OUT="$(mktemp)"
CODE="$(curl -sS -m 30 -o "$OUT" -w '%{http_code}' -u "${TOKEN}:token" -H 'Accept: application/json' -H 'X-Requested-By: cli' "${BASE}/api/roles" || echo 000)"
[ "$CODE" = "200" ] || { echo "ERROR: GET /api/roles -> HTTP ${CODE}"; head -c 200 "$OUT"; rm -f "$OUT"; exit 1; }
jq -r '.roles[] | "\(.name) | read_only=\(.read_only) | permissions=\(.permissions|length) | token permissions: \([.permissions[] | select(test("token"))] | join(","))"' "$OUT"
rm -f "$OUT"
