#!/usr/bin/env bash
# C3: grants `users:tokencreate:<username>` to ONE Graylog user. STATE-CHANGING with --apply; read-only otherwise (dry run).
# PUT /api/users/{username}/permissions REPLACES the whole permission list, so the script:
#   1. reads the current list and saves it as a backup file (permission strings only);
#   2. builds the new list = current list + the one permission, without duplicates;
#   3. dry run: prints the added permission and the counts; --apply: sends the PUT, then reads back and verifies.
# Usage: scripts-grant-token-create.sh <username> <graylog-base-url> <token-env-var-name> <backup-file> [--apply]
set -euo pipefail
USER_NAME="${1:?username}"; BASE="${2:?base url}"; TOKVAR="${3:?token env var name}"; BACKUP="${4:?backup file path}"; MODE="${5:-dry-run}"
TOKEN="${!TOKVAR:?env var $TOKVAR is not set}"
call() { # method path [body-file]
  local out code; out="$(mktemp)"
  if [ -n "${3:-}" ]; then
    code="$(curl -sS -m 30 -X "$1" -o "$out" -w '%{http_code}' -u "${TOKEN}:token" -H 'Accept: application/json' -H 'Content-Type: application/json' -H 'X-Requested-By: cli' --data @"$3" "${BASE}/api/$2" || echo 000)"
  else
    code="$(curl -sS -m 30 -X "$1" -o "$out" -w '%{http_code}' -u "${TOKEN}:token" -H 'Accept: application/json' -H 'X-Requested-By: cli' "${BASE}/api/$2" || echo 000)"
  fi
  case "$code" in 200|204) cat "$out"; rm -f "$out";; *) echo "ERROR: $1 /api/$2 -> HTTP $code: $(head -c 200 "$out" | tr -d '\r\n')" >&2; rm -f "$out"; exit 1;; esac
}
NEW="users:tokencreate:${USER_NAME}"
CUR="$(call GET "users/${USER_NAME}" | jq '.permissions')"
echo "$CUR" > "$BACKUP"
echo "current permissions: $(echo "$CUR" | jq 'length'); backup saved to $BACKUP"
if echo "$CUR" | jq -e --arg p "$NEW" 'index($p) != null' >/dev/null; then echo "already has $NEW; nothing to do"; exit 0; fi
BODY="$(mktemp)"; echo "$CUR" | jq --arg p "$NEW" '{permissions: (. + [$p] | unique)}' > "$BODY"
echo "would add: $NEW (new total: $(jq '.permissions|length' "$BODY"))"
[ "$MODE" = "--apply" ] || { echo "dry run: nothing changed. Rerun with --apply to send it."; rm -f "$BODY"; exit 0; }
call PUT "users/${USER_NAME}/permissions" "$BODY" >/dev/null; rm -f "$BODY"
call GET "users/${USER_NAME}" | jq --arg p "$NEW" '{has_tokencreate: (.permissions | index($p) != null), permission_count: (.permissions|length)}'
