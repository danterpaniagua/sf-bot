#!/usr/bin/env bash
# C2: read-only. Revision history of the `*.Authorization.*` keys of a dev App Configuration store:
# when each value changed and whether the revision was valid JSON. Prints no values beyond the first 14 characters.
# Usage: scripts-revisions.sh <app-configuration-name> <subscription-id> [login|key]
# Output goes to stdout; the caller redirects it to .../data/
set -euo pipefail
APPCFG="${1:?app configuration name}"
SUB="${2:?subscription id}"
MODE="${3:-login}"

for K in Business Catalog Person Sales Site; do
  echo "== SmartFran.Cloud.${K}.Authorization.Auth0"
  az appconfig revision list --name "$APPCFG" --subscription "$SUB" --auth-mode "$MODE" \
    --key "SmartFran.Cloud.${K}.Authorization.Auth0" --all -o json |
  jq -r '
    sort_by(.lastModified // .last_modified) | .[] |
    (.value // "") as $v |
    "\(.lastModified // .last_modified) | content_type=\(.contentType // .content_type // "none") | length \($v|length) | " +
    ( $v | try (fromjson | "VALID JSON") catch "INVALID JSON") + " | starts with: " + $v[0:14]
  '
done
