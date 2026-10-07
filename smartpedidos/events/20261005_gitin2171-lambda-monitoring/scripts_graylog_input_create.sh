#!/usr/bin/env bash
# GITIN-2171: create the Graylog AWS input `sp-lambda-logs` through the REST API, as a copy of the existing
# `platform-service-production-task` input (same type and settings) with only the title and the Kinesis stream name changed.
# Usage: SML_GRAYLOG_API_KEY="$SML_GRAYLOG_API_KEY" bash scripts_graylog_input_create.sh <aws-cli-profile-holding-the-key>
# ⚠️ STATE-CHANGING (production Graylog): creates (and starts) a global input.
# Credentials (user decision 2026-10-05: reuse the key the three existing AWS inputs use):
#  - the access key ID and secret are read from the local AWS CLI profile into shell variables; they are never printed, never written
#    to a file and never put on a command line (they go to jq through the environment and to curl through stdin);
#  - the script ABORTS unless the profile's access key ID ends in the same 4 characters as the key in the existing inputs (SPSH),
#    so a different key is never sent by mistake.
set -eu
E=/home/dpaniagua/Documentos/git/bots/smartpedidos/events/20261005_gitin2171-lambda-monitoring/data
P="${1:?usage: $0 <aws-cli-profile>}"
: "${SML_GRAYLOG_API_KEY:?SML_GRAYLOG_API_KEY not set (pass it as shown in the usage line)}"
GL=http://sf-monitoreo.smartfran.com:9000
EXPECT_SUFFIX=SPSH
TS=$(date +%H%M%S)
mkdir -p "$E"

# 1) refuse to create a duplicate
if curl -sS -m 30 -u "$SML_GRAYLOG_API_KEY:token" -H 'Accept: application/json' "$GL/api/system/inputs" | jq -e '.inputs[]|select(.title=="sp-lambda-logs")' >/dev/null; then
  echo "an input titled sp-lambda-logs already exists — not creating another"; exit 1
fi

# 2) the key from the local profile, with the suffix guard (nothing printed except the pass/fail line)
KID=$(aws configure get aws_access_key_id --profile "$P" 2>/dev/null || true)
SEC=$(aws configure get aws_secret_access_key --profile "$P" 2>/dev/null || true)
if [ -z "$KID" ] || [ -z "$SEC" ]; then echo "profile $P has no static access key/secret configured — aborting"; exit 1; fi
if [ "${KID: -4}" != "$EXPECT_SUFFIX" ]; then echo "the profile's access key does not end in $EXPECT_SUFFIX (the key used by the existing inputs) — aborting"; unset KID SEC; exit 1; fi
echo "profile key suffix check: OK ($EXPECT_SUFFIX)"

# 3) body = existing platform input's settings, with title/stream/credentials replaced (secret via environment, not argv)
EXISTING=$(curl -sS -m 30 -u "$SML_GRAYLOG_API_KEY:token" -H 'Accept: application/json' "$GL/api/system/inputs" | jq '.inputs[]|select(.title=="platform-service-production-task")')
export KID SEC
BODY=$(jq -n --argjson e "$EXISTING" '{title:"sp-lambda-logs", type:$e.type, global:true,
  configuration: ($e.attributes + {aws_access_key:$ENV.KID, aws_secret_key:$ENV.SEC, kinesis_stream_name:"sp-lambda-logs"})}')
unset KID SEC

# 4) create (body goes through stdin, never through argv)
printf '%s' "$BODY" | curl -sS -m 60 -u "$SML_GRAYLOG_API_KEY:token" -H 'Accept: application/json' -H 'Content-Type: application/json' -H 'X-Requested-By: cli' \
  -X POST "$GL/api/system/inputs" -d @- -o "$E/graylog_input_create_$TS.json" -w 'http_code=%{http_code}\n' >| "$E/graylog_input_create_${TS}_status.txt" 2>&1
BODY=""
cat "$E/graylog_input_create_${TS}_status.txt"; cat "$E/graylog_input_create_$TS.json"; echo
