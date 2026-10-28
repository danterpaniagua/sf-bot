#!/usr/bin/env bash
# C1: read-only. Why can a Graylog user not create API tokens?
# Prints, for one user: roles, flags and token-related permissions (no name, email or other profile data),
# the token-related permissions of each of the user's roles, and the cluster-config classes that look user/token related.
# Usage: scripts.sh <username> <graylog-base-url> <token-env-var-name>
#   SmartCloud:  scripts.sh <user> https://sfcloud-monitoreo.smartfran.com/graylog GRAYLOG_API_KEY
#   SmartPedidos/SmartLoyalty: scripts.sh <user> http://sf-monitoreo.smartfran.com:9000 SML_GRAYLOG_API_KEY
# Output goes to stdout; the caller redirects it to .../data/
set -euo pipefail
USER_NAME="${1:?username}"
BASE="${2:?graylog base url}"
TOKVAR="${3:?name of the env var holding the API token}"
TOKEN="${!TOKVAR:?env var $TOKVAR is not set}"
# Fails loudly: prints the HTTP status and the first 200 characters of a non-200 body, and exits.
api() {
  local out code
  out="$(mktemp)"
  code="$(curl -sS -m 30 -o "$out" -w '%{http_code}' -u "${TOKEN}:token" -H 'Accept: application/json' -H 'X-Requested-By: cli' "${BASE}/api/$1" || echo 000)"
  if [ "$code" != "200" ]; then
    echo "ERROR: GET ${BASE}/api/$1 -> HTTP ${code}; body starts with: $(head -c 200 "$out" | tr -d '\r\n')" >&2
    echo "ERROR: GET /api/$1 -> HTTP ${code}"
    rm -f "$out"; exit 1
  fi
  cat "$out"; rm -f "$out"
}

echo "== host: $(echo "$BASE" | sed 's#https\?://##; s#/.*##')"
echo "== version: $(api system | jq -r '.version')"

echo "== user ${USER_NAME}"
U="$(api "users/${USER_NAME}")"
echo "$U" | jq '{username, roles, read_only, external, service_account, session_active,
  token_permissions: [.permissions[]? | select(test("token"))],
  edit_self: [.permissions[]? | select(test("^users:edit:|^users:passwordchange:"))]}'

echo "== token-related permissions per role of the user"
echo "$U" | jq -r '.roles[]?' | while IFS= read -r R; do
  echo "-- role ${R}"
  api "roles/$(printf %s "$R" | jq -sRr @uri)" | jq '{name, read_only, token_permissions: [.permissions[]? | select(test("token"))], permission_count: (.permissions|length)}'
done

echo "== cluster config classes related to users/tokens"
api "system/cluster_config" | jq -r '.[]? // .classes[]? ' 2>/dev/null | grep -i -E 'user|token|auth' || echo "(none listed)"
