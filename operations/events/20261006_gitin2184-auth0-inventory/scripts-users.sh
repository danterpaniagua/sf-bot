#!/usr/bin/env bash
# GITIN-2184 — Listado completo de usuarios Auth0 (solo lectura, SIN PII: sin email/nombre/teléfono)
# C11 — este archivo completo (scripts-users.sh): exporta todos los usuarios sin tope de 1000
# Uso: TAG=dev bash scripts-users.sh   |   TAG=prod bash scripts-users.sh
# Mismas variables de entorno que scripts.sh. Pagina por ventanas mensuales de created_at (search_engine=v3)
# para evitar el tope de 1000 resultados del listado de /users.

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
G() { curl -sS --fail-with-body -H "Authorization: Bearer $AUTH0_TOKEN" "$BASE/api/v2/$1"; }

OUT="$D/${TAG}-users-all.jsonl"; : > "$OUT"
EM="$D/${TAG}-users-emails.jsonl"; : > "$EM"; chmod 600 "$EM"
F="user_id,email,identities,created_at,last_login,logins_count,blocked,email_verified"
start=2020-01-01; end=$(date -d 'next month' +%Y-%m-01)
cur=$start
while [ "$cur" != "$end" ] && [[ "$cur" < "$end" ]]; do
  nxt=$(date -d "$cur +1 month" +%Y-%m-%d)
  q="created_at:[$cur TO $nxt}"
  page=0
  while :; do
    r=$(G "users?per_page=100&page=$page&include_totals=true&search_engine=v3&include_fields=true&fields=$F&q=$(printf '%s' "$q" | jq -sRr @uri)") || { echo "ERROR ventana $cur página $page" >&2; break; }
    n=$(echo "$r" | jq '.users|length'); t=$(echo "$r" | jq '.total')
    echo "$r" | jq -c '.users[]|{user_id,email}' >> "$EM"
    echo "$r" | jq -c --arg w "$cur" '.users[]|{user_id,connections:[.identities[]?|.connection],created_at,last_login,logins_count,blocked,email_verified}' >> "$OUT"
    [ "$page" = 0 ] && [ "$t" -ge 1000 ] && echo "AVISO ventana $cur con total>=1000 (posible truncado)" >&2
    [ "$n" -lt 100 ] && break
    page=$((page+1)); sleep 0.3
  done
  cur=$nxt
done
echo "$(wc -l < "$OUT") usuarios en $OUT"
