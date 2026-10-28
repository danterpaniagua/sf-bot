#!/usr/bin/env bash
# C6: creates the custom role "AI Integration Streams" = streams:read:<id> for every stream whose title matches
# ^PROD-.*-(AppServicePlan|FunctionApp)$ (application logs; the *-AppServiceHTTPLogs, DEV and system streams are excluded).
# STATE-CHANGING with --apply (POST /api/roles); read-only otherwise (dry run prints the stream list and the body).
# It does not assign the role to anyone. The role is meant to be added next to `Reader` on the dedicated integration user.
# Usage: scripts-create-ai-role.sh <graylog-base-url> <token-env-var-name> [--apply]
set -euo pipefail
BASE="${1:?graylog base url}"; TOKVAR="${2:?token env var name}"; MODE="${3:-dry-run}"
TOKEN="${!TOKVAR:?env var $TOKVAR is not set}"
ROLE="AI Integration Streams"
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
echo "$STREAMS" | jq --arg n "$ROLE" '[.streams[] | select(.title | test("^PROD-.*-(AppServicePlan|FunctionApp)$"))] as $s
  | {name: $n, description: "Read access to the PROD application-log streams for the AI integration (no HTTP logs)", read_only: false, permissions: ($s | map("streams:read:" + .id) | sort)}' > "$BODY"
echo "streams matched:"; echo "$STREAMS" | jq -r '.streams[] | select(.title | test("^PROD-.*-(AppServicePlan|FunctionApp)$")) | "  \(.id) | \(.title)"' | sort -t'|' -k2
echo "permissions in the new role: $(jq '.permissions|length' "$BODY")"
[ "$MODE" = "--apply" ] || { echo "dry run: nothing changed. Rerun with --apply to create the role."; rm -f "$BODY"; exit 0; }
call POST roles "$BODY" >/dev/null; rm -f "$BODY"
call GET "roles/${ENC}" | jq '{name, read_only, permission_count: (.permissions|length)}'
