#!/usr/bin/env bash
# Auth0 read-only check: APIs (permissions, RBAC settings), roles, role permissions, role members,
# client grants, applications, organizations. GET requests only (plus the token request).
#
# Usage (variables must be exported in the calling shell):
#   ENVN=PROD ./scripts.sh [permission]     # permission defaults to read:tenant
#   ENVN=DEV  ./scripts.sh write:tenant
# Reads AUTH0_CLIENTID_<ENVN>, AUTH0_SECRET_<ENVN>, AUTH0_AUDIENCE_<ENVN>, AUTH0_URL_<ENVN>.
# Writes to $OUT (default: this event's data/), files tagged with the environment and date.
# Never prints or stores the secret or the access token.
set -euo pipefail

ENVN="${ENVN:?set ENVN=PROD or ENVN=DEV}"
PERM="${1:-read:tenant}"
OUT="${OUT:-/home/dpaniagua/Documentos/git/bots/cloud/events/20260930_pos-wasm-tenant-403-after-deploy/data}"
TAG="$(echo "$ENVN" | tr 'A-Z' 'a-z')_$(date +%Y%m%d)"
test -d "$OUT"

CID=$(printenv "AUTH0_CLIENTID_$ENVN") || { echo "AUTH0_CLIENTID_$ENVN not exported"; exit 1; }
SEC=$(printenv "AUTH0_SECRET_$ENVN")   || { echo "AUTH0_SECRET_$ENVN not exported"; exit 1; }
AUD=$(printenv "AUTH0_AUDIENCE_$ENVN") || { echo "AUTH0_AUDIENCE_$ENVN not exported"; exit 1; }
URL=$(printenv "AUTH0_URL_$ENVN")      || { echo "AUTH0_URL_$ENVN not exported"; exit 1; }
BASE="${URL%/oauth/token}"; BASE="${BASE%/}"; A="$BASE/api/v2"

RESP=$(printf '{"client_id":"%s","client_secret":"%s","audience":"%s","grant_type":"client_credentials"}' "$CID" "$SEC" "$AUD" \
  | curl -s -X POST "$BASE/oauth/token" -H 'content-type: application/json' --data-binary @-)
{ echo "domain=$BASE"; echo "$RESP" | jq 'del(.access_token)'; } > "$OUT/auth0_${TAG}_token_meta.txt"
TOKEN=$(echo "$RESP" | jq -r '.access_token // empty')
test -n "$TOKEN" || { echo "no token; see $OUT/auth0_${TAG}_token_meta.txt"; exit 1; }
H="Authorization: Bearer $TOKEN"

# getall <path[?query]>  -> one JSON array with every page (stops on non-array, e.g. an error object)
getall() {
  local sep="?" page=0 acc='[]' r n
  [[ "$1" == *\?* ]] && sep="&"
  while :; do
    r=$(curl -s -H "$H" "$A/$1${sep}per_page=100&page=$page")
    if ! echo "$r" | jq -e 'type=="array"' >/dev/null 2>&1; then echo "$r"; return; fi
    acc=$(jq -s 'add' <(echo "$acc") <(echo "$r"))
    n=$(echo "$r" | jq 'length'); [ "$n" -lt 100 ] && break; page=$((page+1))
  done
  echo "$acc"
}

getall "resource-servers"                                   > "$OUT/auth0_${TAG}_resource_servers.json"
getall "clients?fields=name,client_id,app_type&include_fields=true" > "$OUT/auth0_${TAG}_clients.json"
getall "client-grants"                                      > "$OUT/auth0_${TAG}_client_grants.json"
getall "organizations"                                      > "$OUT/auth0_${TAG}_organizations.json"
getall "roles"                                              > "$OUT/auth0_${TAG}_roles.json"

: > "$OUT/auth0_${TAG}_role_permissions.jsonl"
for id in $(jq -r '.[]?.id' "$OUT/auth0_${TAG}_roles.json"); do
  name=$(jq -r --arg id "$id" '.[]|select(.id==$id)|.name' "$OUT/auth0_${TAG}_roles.json")
  perms=$(getall "roles/$id/permissions" | jq -c '[.[]?|{p:.permission_name,a:.resource_server_identifier}]')
  users=$(curl -s -H "$H" "$A/roles/$id/users?per_page=1&include_totals=true" | jq '.total // null')
  jq -cn --arg id "$id" --arg name "$name" --argjson u "${users:-null}" --argjson p "$perms" \
    '{role_id:$id,name:$name,users:$u,permissions:$p}' >> "$OUT/auth0_${TAG}_role_permissions.jsonl"
done

S="$OUT/auth0_${TAG}_summary.txt"
{
  echo "tenant: $BASE    checked permission: $PERM"
  echo; echo "== APIs: name | identifier | RBAC | token dialect | offline access | #permissions | has $PERM"
  jq -r --arg p "$PERM" '.[]?|[.name,.identifier,((.enforce_policies//false)|tostring),(.token_dialect//"-"),((.allow_offline_access//false)|tostring),((.scopes//[])|length|tostring),(((.scopes//[])|map(.value)|index($p))!=null|tostring)]|join(" | ")' "$OUT/auth0_${TAG}_resource_servers.json"
  echo; echo "== Roles: name | members | #permissions | has $PERM | APIs"
  jq -r --arg p "$PERM" '[.name,(.users|tostring),(.permissions|length|tostring),((.permissions|map(.p)|index($p))!=null|tostring),(.permissions|map(.a)|unique|join(","))]|join(" | ")' "$OUT/auth0_${TAG}_role_permissions.jsonl"
  echo; echo "== Client grants (machine-to-machine): application | audience | #scopes | has $PERM"
  jq -r --slurpfile c "$OUT/auth0_${TAG}_clients.json" --arg p "$PERM" '.[]?|. as $g|(($c[0]|map(select(.client_id==$g.client_id))|.[0].name) // $g.client_id) as $n|[$n,$g.audience,(($g.scope//[])|length|tostring),((($g.scope//[])|index($p))!=null|tostring)]|join(" | ")' "$OUT/auth0_${TAG}_client_grants.json"
  echo; echo "== Applications: name | type"
  jq -r '.[]?|[.name,(.app_type//"-")]|join(" | ")' "$OUT/auth0_${TAG}_clients.json"
  echo; echo "== Organizations: name | id"
  jq -r '.[]?|[.name,.id]|join(" | ")' "$OUT/auth0_${TAG}_organizations.json" 2>/dev/null || true
} > "$S"
echo "done: $S"
