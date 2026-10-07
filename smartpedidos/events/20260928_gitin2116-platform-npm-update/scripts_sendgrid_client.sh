#!/usr/bin/env bash
# GITIN-2116: @sendgrid/client facts. Read-only: one GET to the public npm registry, one `docker run` that only cats a file.
# Writes to data/. No secrets involved.
set -eu
E=/home/dpaniagua/Documentos/git/bots/smartpedidos/events/20260928_gitin2116-platform-npm-update/data

curl -s https://registry.npmjs.org/@sendgrid%2Fclient > "$E/registry_sendgrid__client.json"

{
  echo "latest: $(jq -r '."dist-tags".latest' "$E/registry_sendgrid__client.json")"
  for v in 7.6.2 7.7.0 8.0.0 8.1.5 8.1.6; do
    jq -r --arg v "$v" 'if .versions[$v] then "\($v)  published \(.time[$v])  deps=\(.versions[$v].dependencies|tostring)  engines=\(.versions[$v].engines|tostring)" else "\($v)  (not published)" end' "$E/registry_sendgrid__client.json"
  done
  echo "-- latest 7.x: $(jq -r '[.versions|keys[]|select(test("^7\\.[0-9]+\\.[0-9]+$"))]|sort_by(split(".")|map(tonumber))|last' "$E/registry_sendgrid__client.json")"
  echo "-- latest version's dependencies: $(jq -r '."dist-tags".latest as $l|.versions[$l].dependencies|tostring' "$E/registry_sendgrid__client.json")"
} > "$E/sendgrid_client_summary_20260930.txt"

# Source of the client as installed in the built Option 1 image (platform-n20:opt1 must exist locally)
docker run --rm --entrypoint sh platform-n20:opt1 -c 'cat /usr/src/app/node_modules/@sendgrid/client/src/classes/client.js' > "$E/sendgrid_client_source_20260930.txt" 2>&1 || true
echo "done: $E/sendgrid_client_summary_20260930.txt  and  $E/sendgrid_client_source_20260930.txt"
