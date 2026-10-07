#!/usr/bin/env bash
# GITIN-2171: route everything that arrives through the Graylog input `sp-lambda-logs` into the stream SP_Lambdas.
# The Lambda's lines are plain text (no ServiceType field), so the existing rule (ServiceType = Lambda) does not match them.
# Adds a "match input" rule (field gl2_source_input, exact match, value = the input id) and switches the stream to match ANY rule (OR),
# keeping the ServiceType rule for Lambdas that might later send GELF directly.
# Usage: SML_GRAYLOG_API_KEY="$SML_GRAYLOG_API_KEY" bash scripts_graylog_stream_rule.sh
# ⚠️ STATE-CHANGING (production Graylog): changes the rules and matching type of the stream SP_Lambdas.
# Must run BEFORE the CloudWatch subscription filter is added, otherwise the first messages would fall into the Default Stream.
set -eu
E=/home/dpaniagua/Documentos/git/bots/smartpedidos/events/20261005_gitin2171-lambda-monitoring/data
: "${SML_GRAYLOG_API_KEY:?SML_GRAYLOG_API_KEY not set (pass it as shown in the usage line)}"
GL=http://sf-monitoreo.smartfran.com:9000
STREAM_ID=6ac3da4aa85d5c4a53684559
INPUT_ID=6ac3e173a85d5c4a536857f7
INDEXSET_ID=6ac3da20a85d5c4a5368453e
TS=$(date +%H%M%S)
H=(-sS -m 30 -u "$SML_GRAYLOG_API_KEY:token" -H 'Accept: application/json' -H 'Content-Type: application/json' -H 'X-Requested-By: cli')
mkdir -p "$E"

# ⚠️ 1) rule: match input (gl2_source_input == input id)
curl "${H[@]}" -X POST "$GL/api/streams/$STREAM_ID/rules" \
  -d "{\"field\":\"gl2_source_input\",\"type\":1,\"value\":\"$INPUT_ID\",\"inverted\":false,\"description\":\"Match input sp-lambda-logs\"}" \
  -o "$E/graylog_stream_rule_add_$TS.json" -w 'rule add: http_code=%{http_code}\n'
# ⚠️ 2) any-rule matching (OR); stream keeps its index set and the removal from the Default Stream
curl "${H[@]}" -X PUT "$GL/api/streams/$STREAM_ID" \
  -d "{\"title\":\"SP_Lambdas\",\"description\":\"Logs de Lambdas de SmartPedidos\",\"matching_type\":\"OR\",\"remove_matches_from_default_stream\":true,\"index_set_id\":\"$INDEXSET_ID\"}" \
  -o "$E/graylog_stream_matching_update_$TS.json" -w 'matching update: http_code=%{http_code}\n'
# 3) verify
curl "${H[@]}" "$GL/api/streams/$STREAM_ID" | jq '{id,title,index_set_id,disabled,remove_matches_from_default_stream,matching_type,rules:[.rules[]|{field,type,value,inverted}]}' >| "$E/graylog_stream_SP_Lambdas_after_rule_$TS.json"
cat "$E/graylog_stream_SP_Lambdas_after_rule_$TS.json"
