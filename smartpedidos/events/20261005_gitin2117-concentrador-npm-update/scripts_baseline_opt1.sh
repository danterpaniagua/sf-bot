#!/usr/bin/env bash
# GITIN-2117: all tests use the local `ope` branch (committed tip; tree identical to develop as of f387973b).
# Measured baseline (ope as-is) vs candidate (axios ~1.20.0 + npm@11.20.0 pin + apk upgrade),
# built from the SAME commit via `git archive ope` (repo working tree untouched, no fetch), --pull --no-cache,
# Trivy flags identical to GITIN-2116: --scanners vuln --pkg-types os,library --severity HIGH,CRITICAL.
# Builds local images concentrador-service:ope (original) and concentrador-service:ope-20.20 (changes); writes everything under data/.
# ⚠️ State-changing: docker pulls/builds, writes files. The candidate patch is applied to a temp copy, not committed to ope.
set -eu
D=20261005
E=/home/dpaniagua/Documentos/git/bots/smartpedidos/events/20261005_gitin2117-concentrador-npm-update/data
G=/home/dpaniagua/Documentos/git/bots/smartpedidos/repo/dev-src-smartPedidos-concentradorService
TRIVY=aquasec/trivy
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
mkdir -p "$E"

cd "$G"
{ echo "checked-out=$(git branch --show-current)"; echo "ope=$(git rev-parse ope) $(git log -1 --format=%ad --date=short ope)"; } > "$E/commit_$D.txt"
mkdir "$TMP/dev" "$TMP/opt1"
git archive ope api | tar -x -C "$TMP/dev"
git archive ope api | tar -x -C "$TMP/opt1"

# Candidate: axios bump + npm pin (both stages) + apk upgrade (final stage). No CA-certificate block.
sed -i 's#"axios": "~1.13.5"#"axios": "~1.20.0"#' "$TMP/opt1/api/package.json"
test "$(grep -c '"axios": "~1.20.0"' "$TMP/opt1/api/package.json")" = 1
sed -i -E \
  -e 's#^(FROM node:20\.20-alpine AS base)$#\1\nRUN npm install -g npm@11.20.0#' \
  -e 's#^(FROM node:20\.20-alpine)$#\1\nRUN npm install -g npm@11.20.0\nRUN apk upgrade --no-cache#' \
  "$TMP/opt1/api/Dockerfile"
test "$(grep -c '^RUN npm install -g npm@11.20.0$' "$TMP/opt1/api/Dockerfile")" = 2
test "$(grep -c '^RUN apk upgrade --no-cache$' "$TMP/opt1/api/Dockerfile")" = 1
cp "$TMP/dev/api/Dockerfile"  "$E/Dockerfile_develop_$D"
cp "$TMP/opt1/api/Dockerfile" "$E/Dockerfile_opt1_$D"
diff "$TMP/dev/api/package.json" "$TMP/opt1/api/package.json" > "$E/package_json_diff_$D.txt" || true

for T in develop opt1; do
  SRC=dev; [ "$T" = opt1 ] && SRC=opt1
  # Tag convention: {branch} = original; {branch}-{nodeversion} = changes test (branch = ope, node = 20.20).
  IMG="concentrador-service:ope"; [ "$T" = opt1 ] && IMG="concentrador-service:ope-20.20"
  docker build --pull --no-cache -f "$TMP/$SRC/api/Dockerfile" -t "$IMG" "$TMP/$SRC/api" > "$E/build_${T}_$D.txt" 2>&1
  {
    docker image inspect "$IMG" --format 'id={{.Id}} created={{.Created}}'
    docker run --rm --entrypoint sh "$IMG" -c 'node -v; npm -v; cat /etc/alpine-release; apk info -v openssl musl zlib 2>/dev/null; npm ls axios mongoose @sendgrid/mail --all 2>&1 | head -40'
  } > "$E/image_stamp_${T}_$D.txt" 2>&1 || true
  docker run --rm -v /var/run/docker.sock:/var/run/docker.sock "$TRIVY" image \
    --scanners vuln --pkg-types os,library --severity HIGH,CRITICAL --format json "$IMG" \
    > "$E/trivy_vuln_${T}_$D.json" 2> "$E/trivy_stderr_${T}_$D.txt"
  jq -r '.Results[]?|.Target as $t|(.Class//"?") as $c|.Vulnerabilities[]?|[$c,$t,.PkgName,.InstalledVersion,.VulnerabilityID,.Severity]|@tsv' \
    "$E/trivy_vuln_${T}_$D.json" | sort > "$E/cve_list_${T}_$D.tsv"
done

{
  for T in develop opt1; do
    echo "== $T (class severity)"; awk -F'\t' '{print $1, $6}' "$E/cve_list_${T}_$D.tsv" | sort | uniq -c
    echo "== $T (lang-pkgs packages)"; awk -F'\t' '$1=="lang-pkgs"{print $3, $4}' "$E/cve_list_${T}_$D.tsv" | sort | uniq -c
  done
} > "$E/summary_$D.txt"
echo "done: $E/summary_$D.txt"
