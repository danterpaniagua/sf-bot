#!/usr/bin/env bash
# GITIN-2116: stamp + Trivy scan of the three Node 22.20 images already built/pulled:
#   node:22.20-alpine (raw)  platform-n22:develop  platform-n22:opt2
# Writes to data/. Read-only on the images (docker run only). No builds.
set -eu
E=/home/dpaniagua/Documentos/git/bots/smartpedidos/events/20260928_gitin2116-platform-npm-update/data
TRIVY=aquasec/trivy

for T in raw develop opt2; do
  IMG="platform-n22:$T"; [ "$T" = raw ] && IMG="node:22.20-alpine"
  {
    docker image inspect "$IMG" --format 'id={{.Id}} created={{.Created}}'
    docker run --rm --entrypoint sh "$IMG" -c 'node -v; npm -v; cat /etc/alpine-release; apk info -v openssl musl zlib ca-certificates 2>/dev/null'
  } > "$E/image_stamp_n22_${T}_20260930.txt" 2>&1 || true
  docker run --rm -v /var/run/docker.sock:/var/run/docker.sock "$TRIVY" image \
    --scanners vuln --pkg-types os,library --severity HIGH,CRITICAL --format json "$IMG" \
    > "$E/trivy_vuln_n22_${T}_20260930.json" 2> "$E/trivy_stderr_n22_${T}_20260930.txt"
  jq -r '.Results[]?|.Target as $t|(.Class//"?") as $c|.Vulnerabilities[]?|[$c,$t,.PkgName,.InstalledVersion,.VulnerabilityID,.Severity]|@tsv' \
    "$E/trivy_vuln_n22_${T}_20260930.json" | sort > "$E/cve_list_n22_${T}_20260930.tsv"
done

{ for T in raw develop opt2; do echo "== n22 $T"; awk -F'\t' '{print $1, $6}' "$E/cve_list_n22_${T}_20260930.tsv" | sort | uniq -c; done; } > "$E/n22_summary_20260930.txt"
echo "done: $E/n22_summary_20260930.txt"
