#!/usr/bin/env bash
# C8: generalizes C6. Creates a custom role = streams:read:<id> for every stream whose title matches a regex.
# STATE-CHANGING with --apply (POST /api/roles); read-only otherwise (dry run prints the matched streams).
# It does not assign the role to anyone.
# Usage: scripts-create-stream-role.sh <graylog-base-url> <token-env-var-name> <role-name> <title-regex> <description> [--apply]
set -euo pipefail
BASE="${1:?graylog base url}"; TOKVAR="${2:?token env var name}"; ROLE="${3:?role name}"; RX="${4:?title regex}"; DESC="${5:?description}"; MODE="${6:-dry-run}"
TOKEN="${!TOKVAR:?env var $TOKVAR is not set}"
call() { # method path [body-file]
  local out code; out="$(mktemp)"
  if [ -n "${3:-}" ]; then
    code="$(curl -sS -m 30 -X "$1" -o "$out" -w '%{http_code}' -u "${TOKEN}:token" -H 'Accept: application/json' -H 'Content-Type: application/json' -H 'X-Requested-By: cli' --data @"$3" "${BASE}/api/$2" || echo 000)"
  else
    code="$(curl -sS -m 30 -X "$1" -o "$out" -w '%{http_code}' -u "${TOKEN}:token" -H 'Accept: application/json' -H 'X-Requested-By: cli' "${BASE}/api/$2" || echo 000)"
  fi
  case "$code" in 200|201|204) cat "$out"; rm -f "$out";; 404) rm -f "$out"; echo "NOTFOUND";; *) echo "ERROR: $1 /api/$2 -> HTTP $code: $(head -c 200 "$out" | tr -d '\r\n')" >&2; rm -f "$out"; exit 1;; esac
}
ENC="${ROLE// /%20}"
if [ "$(call GET "roles/${ENC}")" != "NOTFOUND" ]; then echo "role '$ROLE' already exists; nothing to do"; exit 0; fi
STREAMS="$(call GET streams)"
BODY="$(mktemp)"
echo "$STREAMS" | jq --arg n "$ROLE" --arg d "$DESC" --arg rx "$RX" '[.streams[] | select(.title | test($rx))] as $s
  | {name: $n, description: $d, read_only: false, permissions: ($s | map("streams:read:" + .id) | sort)}' > "$BODY"
echo "role: $ROLE"; echo "streams matched by /$RX/:"
echo "$STREAMS" | jq -r --arg rx "$RX" '.streams[] | select(.title | test($rx)) | "  \(.id) | \(.title)"' | sort -t'|' -k2
N="$(jq '.permissions|length' "$BODY")"; echo "permissions in the new role: $N"
[ "$N" -gt 0 ] || { echo "no stream matched; aborting"; rm -f "$BODY"; exit 1; }
[ "$MODE" = "--apply" ] || { echo "dry run: nothing changed. Rerun with --apply to create the role."; rm -f "$BODY"; exit 0; }
call POST roles "$BODY" >/dev/null; rm -f "$BODY"
call GET "roles/${ENC}" | jq '{name, read_only, permission_count: (.permissions|length)}'
