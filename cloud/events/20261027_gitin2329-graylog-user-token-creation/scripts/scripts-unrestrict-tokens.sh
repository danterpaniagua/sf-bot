#!/usr/bin/env bash
# C7: sets restrict_access_token_to_admins=false in org.graylog2.users.UserConfiguration. STATE-CHANGING with --apply; dry run otherwise.
# PUT replaces the whole object, so: 1. read current + save backup; 2. change only that key; 3. dry run prints the diff, --apply PUTs and reads back.
# Rollback: PUT the backup file to the same path (see the line printed at the end).
# Usage: scripts-unrestrict-tokens.sh <graylog-base-url> <token-env-var-name> <backup-file> [--apply]
set -euo pipefail
BASE="${1:?graylog base url}"; TOKVAR="${2:?token env var name}"; BACKUP="${3:?backup file path}"; MODE="${4:-dry-run}"
TOKEN="${!TOKVAR:?env var $TOKVAR is not set}"
PATH_CFG="system/cluster_config/org.graylog2.users.UserConfiguration"
call() { # method path [body-file]
  local out code; out="$(mktemp)"
  if [ -n "${3:-}" ]; then
    code="$(curl -sS -m 30 -X "$1" -o "$out" -w '%{http_code}' -u "${TOKEN}:token" -H 'Accept: application/json' -H 'Content-Type: application/json' -H 'X-Requested-By: cli' --data @"$3" "${BASE}/api/$2" || echo 000)"
  else
    code="$(curl -sS -m 30 -X "$1" -o "$out" -w '%{http_code}' -u "${TOKEN}:token" -H 'Accept: application/json' -H 'X-Requested-By: cli' "${BASE}/api/$2" || echo 000)"
  fi
  case "$code" in 200|202|204) cat "$out"; rm -f "$out";; *) echo "ERROR: $1 /api/$2 -> HTTP $code: $(head -c 200 "$out" | tr -d '\r\n')" >&2; rm -f "$out"; exit 1;; esac
}
CUR="$(call GET "$PATH_CFG")"
echo "$CUR" | jq . > "$BACKUP"
echo "current: $(echo "$CUR" | jq -c .)"; echo "backup saved to $BACKUP"
if echo "$CUR" | jq -e '.restrict_access_token_to_admins == false' >/dev/null; then echo "already false; nothing to do"; exit 0; fi
BODY="$(mktemp)"; echo "$CUR" | jq '.restrict_access_token_to_admins = false' > "$BODY"
echo "would send: $(jq -c . "$BODY")"
[ "$MODE" = "--apply" ] || { echo "dry run: nothing changed. Rerun with --apply to send it."; rm -f "$BODY"; exit 0; }
call PUT "$PATH_CFG" "$BODY" >/dev/null; rm -f "$BODY"
call GET "$PATH_CFG" | jq -c .
echo "rollback: curl -X PUT -u \"\$$TOKVAR:token\" -H 'Content-Type: application/json' -H 'X-Requested-By: cli' --data @$BACKUP ${BASE}/api/${PATH_CFG}"
