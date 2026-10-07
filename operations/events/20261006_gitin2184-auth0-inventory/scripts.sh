#!/usr/bin/env bash
# GITIN-2184 — Inventario Auth0 (solo lectura, Management API vía Auth0 CLI)
# Uso: TAG=dev bash scripts.sh   |   TAG=prod bash scripts.sh
# Requiere (variables de entorno ya definidas): AUTH0_URL_<DEV|PROD>, AUTH0_CLIENTID_<...>, AUTH0_SECRET_<...>
#   La app M2M debe estar autorizada en la Auth0 Management API con scopes read:clients, read:client_grants,
#   read:resource_servers, read:roles, read:users, read:organizations, read:connections.
#   Secretos solo por variable de entorno, nunca en este archivo. Requiere curl y jq.
# No se piden client_secret ni email/nombre/teléfono de usuarios (fields= explícitos).

D=/home/dpaniagua/Documentos/git/bots/operations/events/20261006_gitin2184-auth0-inventory/data
mkdir -p "$D"
# dev usa las variables sin sufijo (AUTH0_URL, ...); prod usa el sufijo _PROD
if [ "$TAG" = prod ]; then SUF=_PROD; else SUF=; fi
vu=AUTH0_URL$SUF; vc=AUTH0_CLIENTID$SUF; vs=AUTH0_SECRET$SUF
for v in $vu $vc $vs; do
  [ -n "${!v}" ] || { echo "falta variable $v" >&2; exit 1; }
done
BASE="${!vu%/}"; BASE="${BASE%/oauth/token}"
case "$BASE" in http*) ;; *) BASE="https://$BASE" ;; esac
# Token M2M (client_credentials) contra la Management API del tenant; queda solo en memoria
AUTH0_TOKEN=$(curl -sS --fail-with-body -X POST "$BASE/oauth/token" -H 'content-type: application/json' \
  -d "{\"grant_type\":\"client_credentials\",\"client_id\":\"${!vc}\",\"client_secret\":\"${!vs}\",\"audience\":\"$BASE/api/v2/\"}" \
  | jq -r .access_token) && [ -n "$AUTH0_TOKEN" ] && [ "$AUTH0_TOKEN" != null ] || { echo "no se obtuvo token" >&2; exit 1; }
T() { local o; o=$(G "$1" 2>/dev/null | jq -c '.total' 2>/dev/null); echo "${o:-null}"; }  # null si la llamada falla (no 0)
G() { curl -sS --fail-with-body -H "Authorization: Bearer $AUTH0_TOKEN" "$BASE/api/v2/$1"; }


# C1 — APIs (resource servers) + permisos
G "resource-servers?per_page=100&include_totals=true" > "$D/${TAG}-apis.json"

# C2 — Applications / clients (sin secretos)
G "clients?per_page=100&include_totals=true&include_fields=true&fields=client_id,name,app_type,is_first_party,grant_types,callbacks,allowed_logout_urls,web_origins,token_endpoint_auth_method,organization_usage,created_at" > "$D/${TAG}-clients.json"

# C3 — Delegated permissions / client grants (qué client puede qué scopes en qué API)
G "client-grants?per_page=100&include_totals=true" > "$D/${TAG}-client-grants.json"

# C4 — Roles
G "roles?per_page=100&include_totals=true" > "$D/${TAG}-roles.json"

# C5 — Organizations
G "organizations?per_page=100&include_totals=true" > "$D/${TAG}-organizations.json"

# C6 — Users — solo metadata (sin PII), primeras 100 + total
G "users?per_page=100&include_totals=true&include_fields=true&fields=user_id,connection,created_at,last_login,logins_count,blocked" > "$D/${TAG}-users-meta.json"

# C7 — Conexiones (referencia para interpretar users.connection)
G "connections?per_page=100&include_fields=true&fields=id,name,strategy" > "$D/${TAG}-connections.json"

# C8 — Total real de usuarios (search_engine=v3; el listado sin q podría estar topeado en 1000)
G "users?per_page=1&include_totals=true&search_engine=v3&q=user_id:*&include_fields=true&fields=user_id" | jq -c '{total,limit}' > "$D/${TAG}-users-total.json"

# C9 — Permisos y cantidad de miembros por rol
for id in $(jq -r '.roles // . | .[].id' "$D/${TAG}-roles.json"); do
  echo "{\"role_id\":\"$id\",\"permissions_total\":$(T "roles/$id/permissions?per_page=1&include_totals=true"),\"permissions\":$(G "roles/$id/permissions?per_page=100&include_totals=true" | jq -c '[.permissions[]|{resource_server_identifier,permission_name}]'),\"members_total\":$(T "roles/$id/users?per_page=1&include_totals=true")}"
done > "$D/${TAG}-roles-detail.jsonl"

# C10 — Cantidad de miembros y conexiones habilitadas por organization
for id in $(jq -r '.organizations[].id' "$D/${TAG}-organizations.json"); do
  echo "{\"org_id\":\"$id\",\"members_total\":$(T "organizations/$id/members?per_page=1&include_totals=true"),\"connections\":$(G "organizations/$id/enabled_connections" | jq -c '[.[]|.connection.name // .connection_id]')}"
done > "$D/${TAG}-orgs-detail.jsonl"

# C12 — Usuarios con dominio @smartfran.com (local, sobre los archivos ya descargados; salida gitignored)
jq -c -n --slurpfile e "$D/${TAG}-users-emails.jsonl" --slurpfile a "$D/${TAG}-users-all.jsonl" '($a|map({(.user_id):.})|add) as $m | $e[]|select(.email|ascii_downcase|test("@smartfran\\.com$"))|. + {connections:$m[.user_id].connections,created_at:$m[.user_id].created_at,last_login:$m[.user_id].last_login,email_verified:$m[.user_id].email_verified}' > "$D/${TAG}-smartfran-users-emails.jsonl"
