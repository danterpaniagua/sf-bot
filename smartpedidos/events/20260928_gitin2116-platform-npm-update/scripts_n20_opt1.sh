#!/usr/bin/env bash
# GITIN-2116: Option 1 (Node 20.20 + changes) measured the same way as Option 2 on Node 22.20:
# committed `ope` HEAD source (git archive), two-layer Dockerfile wording, fresh base pull, --no-cache,
# same Trivy flags. Builds local image platform-n20:opt1 and writes files under data/.
set -eu
E=/home/dpaniagua/Documentos/git/bots/smartpedidos/events/20260928_gitin2116-platform-npm-update/data
G=/home/dpaniagua/Documentos/git/bots/smartpedidos/repo/dev-scr-smartPedidos-platformsService
TRIVY=aquasec/trivy
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

cd "$G"
{ echo "ope HEAD=$(git rev-parse HEAD) branch=$(git branch --show-current)"; } > "$E/n20_opt1_commit_20260930.txt"
git archive HEAD api | tar -x -C "$TMP"

sed -E -e 's#^FROM node:[^ ]*-alpine#FROM node:20.20-alpine#' \
 -e 's#^RUN apk upgrade --no-cache && npm install -g npm@11\.20\.0$#RUN npm install -g npm@11.20.0#' \
 -e 's#^RUN apk add --no-cache ca-certificates$#RUN apk upgrade --no-cache \&\& apk add --no-cache ca-certificates#' \
 "$TMP/api/Dockerfile" > "$TMP/api/Dockerfile.n20"
cp "$TMP/api/Dockerfile.n20" "$E/Dockerfile_n20_opt1"
test "$(grep -c '^FROM node:20.20-alpine' "$TMP/api/Dockerfile.n20")" = 2
test "$(grep -c '^RUN apk upgrade --no-cache && apk add --no-cache ca-certificates$' "$TMP/api/Dockerfile.n20")" = 1

docker build --pull --no-cache -f "$TMP/api/Dockerfile.n20" -t platform-n20:opt1 "$TMP/api" > "$E/build_n20_opt1_20260930.txt" 2>&1

{
  docker image inspect platform-n20:opt1 --format 'id={{.Id}} created={{.Created}}'
  docker run --rm --entrypoint sh platform-n20:opt1 -c 'node -v; npm -v; cat /etc/alpine-release; apk info -v openssl musl zlib ca-certificates 2>/dev/null; ls /usr/local/share/ca-certificates; test -s /etc/ssl/certs/ca-certificates.crt && echo ca-bundle-present'
  docker image inspect platform-n20:opt1 --format '{{range .Config.Env}}{{println .}}{{end}}' | grep -E '^NODE_EXTRA_CA_CERTS='
} > "$E/image_stamp_n20_opt1_20260930.txt" 2>&1 || true

docker run --rm -v /var/run/docker.sock:/var/run/docker.sock "$TRIVY" image \
  --scanners vuln --pkg-types os,library --severity HIGH,CRITICAL --format json platform-n20:opt1 \
  > "$E/trivy_vuln_n20_opt1_20260930.json" 2> "$E/trivy_stderr_n20_opt1_20260930.txt"
jq -r '.Results[]?|.Target as $t|(.Class//"?") as $c|.Vulnerabilities[]?|[$c,$t,.PkgName,.InstalledVersion,.VulnerabilityID,.Severity]|@tsv' \
  "$E/trivy_vuln_n20_opt1_20260930.json" | sort > "$E/cve_list_n20_opt1_20260930.tsv"
{ echo "== n20 opt1"; awk -F'\t' '{print $1, $6}' "$E/cve_list_n20_opt1_20260930.tsv" | sort | uniq -c; echo "== packages"; awk -F'\t' '$1=="lang-pkgs"{print $3, $4}' "$E/cve_list_n20_opt1_20260930.tsv" | sort | uniq -c; } > "$E/n20_opt1_summary_20260930.txt"
echo "done: $E/n20_opt1_summary_20260930.txt"
