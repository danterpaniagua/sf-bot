#!/usr/bin/env bash
# GITIN-2117: the same candidate changes as scripts_baseline_opt1.sh (axios ~1.20.0 + npm@11.20.0 pin + apk upgrade) on Node 22.20,
# built from the committed local `ope` tip via `git archive ope` (working tree untouched, no fetch), --pull --no-cache,
# Trivy flags as in GITIN-2116: --scanners vuln --pkg-types os,library --severity HIGH,CRITICAL.
# Tag convention: concentrador-service:ope-22.20 (changes test). Original-on-22 baseline is NOT built here (only if wanted).
# ⚠️ State-changing: docker pull/build (local image), writes files under data/. Patch applied to a temp copy, not committed to ope.
set -eu
D=20261005
E=/home/dpaniagua/Documentos/git/bots/smartpedidos/events/20261005_gitin2117-concentrador-npm-update/data
G=/home/dpaniagua/Documentos/git/bots/smartpedidos/repo/dev-src-smartPedidos-concentradorService
TRIVY=aquasec/trivy
IMG=concentrador-service:ope-22.20
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
mkdir -p "$E"

cd "$G"
{ echo "checked-out=$(git branch --show-current)"; echo "ope=$(git rev-parse ope) $(git log -1 --format=%ad --date=short ope)"; } > "$E/commit_n22_$D.txt"
git archive ope api | tar -x -C "$TMP"

sed -i 's#"axios": "~1.13.5"#"axios": "~1.20.0"#' "$TMP/api/package.json"
test "$(grep -c '"axios": "~1.20.0"' "$TMP/api/package.json")" = 1
sed -i -E \
  -e 's#^FROM node:20\.20-alpine#FROM node:22.20-alpine#' \
  -e 's#^(FROM node:22\.20-alpine AS base)$#\1\nRUN npm install -g npm@11.20.0#' \
  -e 's#^(FROM node:22\.20-alpine)$#\1\nRUN npm install -g npm@11.20.0\nRUN apk upgrade --no-cache#' \
  "$TMP/api/Dockerfile"
test "$(grep -c '^FROM node:22.20-alpine' "$TMP/api/Dockerfile")" = 2
test "$(grep -c '^RUN npm install -g npm@11.20.0$' "$TMP/api/Dockerfile")" = 2
test "$(grep -c '^RUN apk upgrade --no-cache$' "$TMP/api/Dockerfile")" = 1
cp "$TMP/api/Dockerfile" "$E/Dockerfile_n22_$D"

docker build --pull --no-cache -f "$TMP/api/Dockerfile" -t "$IMG" "$TMP/api" > "$E/build_n22_$D.txt" 2>&1
{
  docker image inspect "$IMG" --format 'id={{.Id}} created={{.Created}}'
  docker run --rm --entrypoint sh "$IMG" -c 'node -v; npm -v; cat /etc/alpine-release; apk info -v openssl musl zlib 2>/dev/null; npm ls axios mongoose @sendgrid/mail --all 2>&1 | head -40'
} > "$E/image_stamp_n22_$D.txt" 2>&1 || true

docker run --rm -v /var/run/docker.sock:/var/run/docker.sock "$TRIVY" image \
  --scanners vuln --pkg-types os,library --severity HIGH,CRITICAL --format json "$IMG" \
  > "$E/trivy_vuln_n22_$D.json" 2> "$E/trivy_stderr_n22_$D.txt"
jq -r '.Results[]?|.Target as $t|(.Class//"?") as $c|.Vulnerabilities[]?|[$c,$t,.PkgName,.InstalledVersion,.VulnerabilityID,.Severity]|@tsv' \
  "$E/trivy_vuln_n22_$D.json" | sort > "$E/cve_list_n22_$D.tsv"
{ echo "== n22 (class severity)"; awk -F'\t' '{print $1, $6}' "$E/cve_list_n22_$D.tsv" | sort | uniq -c
  echo "== n22 (lang-pkgs packages)"; awk -F'\t' '$1=="lang-pkgs"{print $3, $4}' "$E/cve_list_n22_$D.tsv" | sort | uniq -c; } > "$E/summary_n22_$D.txt"
echo "done: $E/summary_n22_$D.txt"
