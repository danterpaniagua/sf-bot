#!/usr/bin/env bash
# C9: deletes the three custom roles created by C6/C8. STATE-CHANGING with --apply; dry run otherwise.
# For each role: saves its JSON as a backup (to recreate it with POST /api/roles if needed), lists its members, and
# refuses to delete a role that still has members (remove it from those users first).
# Usage: scripts-delete-ai-roles.sh <graylog-base-url> <token-env-var-name> <backup-dir> [--apply]
set -euo pipefail
BASE="${1:?graylog base url}"; TOKVAR="${2:?token env var name}"; BDIR="${3:?backup dir}"; MODE="${4:-dry-run}"
TOKEN="${!TOKVAR:?env var $TOKVAR is not set}"
mkdir -p "$BDIR"
call() { # method path
  local out code; out="$(mktemp)"
  code="$(curl -sS -m 30 -X "$1" -o "$out" -w '%{http_code}' -u "${TOKEN}:token" -H 'Accept: application/json' -H 'X-Requested-By: cli' "${BASE}/api/$2" || echo 000)"
  case "$code" in 200|204) cat "$out"; rm -f "$out";; 404) rm -f "$out"; echo "NOTFOUND";; *) echo "ERROR: $1 /api/$2 -> HTTP $code: $(head -c 200 "$out" | tr -d '\r\n')" >&2; rm -f "$out"; exit 1;; esac
}
for ROLE in "AI Integration Streams" "AI Integration Streams DEV" "AI Integration Streams HTTP"; do
  ENC="${ROLE// /%20}"; echo "== $ROLE"
  R="$(call GET "roles/${ENC}")"
  [ "$R" != "NOTFOUND" ] || { echo "  not found; skipping"; continue; }
  echo "$R" | jq . > "$BDIR/role-${ROLE// /_}.json"
  MEMBERS="$(call GET "roles/${ENC}/members" | jq -r '(.users // [])[] | .username')"
  if [ -n "$MEMBERS" ]; then echo "  still has members: $(echo "$MEMBERS" | tr '\n' ' '); NOT deleting"; continue; fi
  echo "  no members; permissions=$(echo "$R" | jq '.permissions|length')"
  [ "$MODE" = "--apply" ] || { echo "  dry run: would delete"; continue; }
  call DELETE "roles/${ENC}" >/dev/null && echo "  deleted"
done
