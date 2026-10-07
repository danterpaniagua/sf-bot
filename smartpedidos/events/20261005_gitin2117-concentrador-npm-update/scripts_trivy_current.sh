#!/usr/bin/env bash
# GITIN-2117: save the CURRENT Trivy report (OS + npm packages) of the concentrador as-is.
# Source = committed HEAD of the local clone (branch `ope`, tree identical to `develop`), via `git archive` (working tree untouched),
# Dockerfile unchanged (FROM node:20.20-alpine, no npm pin, no apk upgrade), --pull --no-cache.
# Trivy flags as in GITIN-2116: --scanners vuln --pkg-types os,library --severity HIGH,CRITICAL.
# Outputs under data/: JSON, TSV list, summary, HTML (Trivy contrib html.tpl, same template as the Jenkins pipelines).
# ⚠️ State-changing: docker pull/build (local image concentrador-service:{branch}, i.e. :ope), writes files, downloads html.tpl.
set -eu
D=20261005
E=/home/dpaniagua/Documentos/git/bots/smartpedidos/events/20261005_gitin2117-concentrador-npm-update/data
G=/home/dpaniagua/Documentos/git/bots/smartpedidos/repo/dev-src-smartPedidos-concentradorService
TRIVY=aquasec/trivy
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
mkdir -p "$E"

cd "$G"
# Tag convention: {branch} = original (unchanged) image; {branch}-{nodeversion} = images with test changes.
IMG="concentrador-service:ope"
{ echo "checked-out=$(git branch --show-current)"; echo "ope=$(git rev-parse ope) $(git log -1 --format=%ad --date=short ope)"; } > "$E/commit_current_$D.txt"
git archive ope api | tar -x -C "$TMP"
cp "$TMP/api/Dockerfile" "$E/Dockerfile_current_$D"

docker build --pull --no-cache -f "$TMP/api/Dockerfile" -t "$IMG" "$TMP/api" > "$E/build_current_$D.txt" 2>&1
{
  docker image inspect "$IMG" --format 'id={{.Id}} created={{.Created}}'
  docker run --rm --entrypoint sh "$IMG" -c 'node -v; npm -v; cat /etc/alpine-release; apk info -v openssl musl zlib 2>/dev/null; npm ls axios mongoose @sendgrid/mail --all 2>&1 | head -40'
} > "$E/image_stamp_current_$D.txt" 2>&1 || true

docker run --rm -v /var/run/docker.sock:/var/run/docker.sock "$TRIVY" image \
  --scanners vuln --pkg-types os,library --severity HIGH,CRITICAL --format json "$IMG" \
  > "$E/trivy_vuln_current_$D.json" 2> "$E/trivy_stderr_current_$D.txt"
jq -r '.Results[]?|.Target as $t|(.Class//"?") as $c|.Vulnerabilities[]?|[$c,$t,.PkgName,.InstalledVersion,.VulnerabilityID,.Severity]|@tsv' \
  "$E/trivy_vuln_current_$D.json" | sort > "$E/cve_list_current_$D.tsv"
{ echo "== class severity"; awk -F'\t' '{print $1, $6}' "$E/cve_list_current_$D.tsv" | sort | uniq -c
  echo "== lang-pkgs packages"; awk -F'\t' '$1=="lang-pkgs"{print $3, $4}' "$E/cve_list_current_$D.tsv" | sort | uniq -c; } > "$E/summary_current_$D.txt"

curl -fsSL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/html.tpl -o "$E/html.tpl"
docker run --rm -v "$E":/work "$TRIVY" convert --format template --template "@/work/html.tpl" \
  -o "/work/trivy_report_current_$D.html" "/work/trivy_vuln_current_$D.json" > "$E/trivy_report_current_${D}_convert_log.txt" 2>&1
echo "done: $E/summary_current_$D.txt  $E/trivy_report_current_$D.html"
