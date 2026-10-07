#!/usr/bin/env bash
# GITIN-2116: convert stored Trivy JSON scans (OS + npm layers) into the same HTML format the Jenkins pipeline publishes
# (Trivy's contrib `html.tpl` template, as used with `--template "@html.tpl"`). No scanning, no image access: it only converts
# existing JSON files in data/. One download (the template) from GitHub.
set -eu
E=/home/dpaniagua/Documentos/git/bots/smartpedidos/events/20260928_gitin2116-platform-npm-update/data
TRIVY=aquasec/trivy

# Same template source the pipelines use
curl -fsSL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/html.tpl -o "$E/html.tpl"

# Current production state: origin/develop (ded57a5), no npm pin, no `apk upgrade`, Node 20.20 — built 2026-09-30 22:01 with a fresh base pull.
# (Add more "scan.json:report.html" pairs here if other states are wanted, e.g. trivy_vuln_n20_opt1_20260930.json for Option 1.)
for pair in \
  "trivy_vuln_develop_current_20260930.json:trivy_report_develop_current_20260930.html"; do
  IN="${pair%%:*}"; OUT="${pair##*:}"
  docker run --rm -v "$E":/work "$TRIVY" convert --format template --template "@/work/html.tpl" -o "/work/$OUT" "/work/$IN" \
    > "$E/${OUT%.html}_convert_log.txt" 2>&1
  echo "$OUT: $(wc -c < "$E/$OUT") bytes"
done
