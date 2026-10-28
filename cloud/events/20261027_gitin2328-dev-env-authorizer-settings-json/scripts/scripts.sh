#!/usr/bin/env bash
# C1: read-only. Check that every App Configuration key `SmartFran.Cloud.*.Authorization.*`
# of a dev environment holds valid JSON, without printing values (they contain ClientSecret).
# Usage: scripts.sh <app-configuration-name> <subscription-id> [login|key]   (auth mode, default login; use key when the account has no data-plane role but can list the store's keys)
# Output goes to stdout; the caller redirects it to /home/dpaniagua/Documentos/git/bots/cloud/events/20261027_gitin2328-dev-env-authorizer-settings-json/data/
set -euo pipefail
APPCFG="${1:?app configuration name}"
SUB="${2:?subscription id}"
MODE="${3:-login}"

az appconfig kv list --name "$APPCFG" --subscription "$SUB" --auth-mode "$MODE" \
  --key 'SmartFran.Cloud.*' --all -o json |
jq -r '
  .[] | select(.key | test("\\.Authorization\\.")) | . as $kv |
  ($kv.value // "") as $v |
  ( $v | try (fromjson | "VALID JSON | top-level properties: " + (keys | join(","))) catch ("INVALID JSON | length " + ($v|length|tostring) + " | starts with: " + $v[0:30]) )
  | "\($kv.key) [label=\($kv.label // "none")] -> " + .
'
