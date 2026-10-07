#!/usr/bin/env bash
# GITIN-2170: recon for sending the escalation Lambda's logs to Graylog (sf-monitoreo.smartfran.com).
# Usage: bash scripts_graylog_integration_recon.sh <aws-cli-profile>      (needs $SML_GRAYLOG_API_KEY in the environment)
# Read-only: AWS lambda get-function(-configuration) on the existing `waf-to-graylog` Lambda (precedent for Lambda -> Graylog),
# and Graylog REST GET calls for inputs, streams and index sets. Writes under data/.
# - Lambda code is downloaded to a temp dir (signed URL never stored); only masked text is kept (AWS key IDs, secret-looking
#   assignments, e-mail local parts and phone numbers masked; hostnames/IPs/ports are NOT masked, they are what we need).
# - Graylog input attributes are filtered to a safe allowlist (no TLS key/password attributes are copied).
set -eu
E=/home/dpaniagua/Documentos/git/bots/smartpedidos/events/20261005_gitin2170-platform-mejorar-escalado/data
P="${1:?usage: $0 <aws-cli-profile>}"
: "${SML_GRAYLOG_API_KEY:?SML_GRAYLOG_API_KEY not set}"
G=http://sf-monitoreo.smartfran.com:9000
FN=waf-to-graylog
R=us-east-1
A="aws --profile $P --region $R --output json"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
mkdir -p "$E"
mask() { sed -E -e 's/(AKIA|ASIA)[A-Z0-9]{12}([A-Z0-9]{4})/\1************\2/g' \
                -e "s/((secret|password|passwd|token|api_?key)[A-Za-z_]*[[:space:]]*[=:][[:space:]]*)['\"][^'\"]{6,}['\"]/\1'<redacted>'/Ig" \
                -e 's/[A-Za-z0-9._%+-]+@([A-Za-z0-9.-]+\.[A-Za-z]{2,})/***@\1/g' \
                -e 's/\+[0-9]{8,}([0-9]{4})/+*********\1/g'; }

# 1) Precedent Lambda: configuration (VPC, env var names, timeout), trigger permissions, masked code
$A lambda get-function-configuration --function-name "$FN" --query '{Runtime:Runtime,Handler:Handler,Timeout:Timeout,MemorySize:MemorySize,LastModified:LastModified,VpcConfig:VpcConfig,EnvVarNames:keys(Environment.Variables||`{}`),Layers:Layers[].Arn,Role:Role}' > "$E/waf_to_graylog_config.json" 2>&1 || true
$A lambda get-policy --function-name "$FN" --query Policy --output text 2>&1 | mask > "$E/waf_to_graylog_policy.json" || true
URL=$($A lambda get-function --function-name "$FN" --query 'Code.Location' --output text 2>/dev/null || true)
if [ -n "$URL" ] && [ "$URL" != None ]; then
  curl -fsS "$URL" -o "$TMP/code.zip" 2> "$E/waf_to_graylog_code_download_stderr.txt" || true
  if [ -s "$TMP/code.zip" ]; then
    unzip -qo "$TMP/code.zip" -d "$TMP/code" || true
    { for f in $(cd "$TMP/code" && find . -type f \( -name '*.py' -o -name '*.json' -o -name '*.txt' \) | sort); do echo "######## $f"; mask < "$TMP/code/$f"; done; } > "$E/waf_to_graylog_code_masked.txt"
  fi
fi
$A events list-rules --query 'Rules[?contains(Name,`waf`)||contains(Name,`graylog`)].[Name,ScheduleExpression,State]' > "$E/waf_related_event_rules.json" 2>&1 || true

# 2) Graylog (read-only GETs): inputs (allowlisted attributes), streams, index sets
H=(-sS -m 30 -u "$SML_GRAYLOG_API_KEY:token" -H 'Accept: application/json')
curl "${H[@]}" "$G/api/system/inputs" | jq '[.inputs[]|{title,type,global,node,created_at,attributes:(.attributes|with_entries(select(.key|test("^(port|bind_address|override_source|recv_buffer_size|tcp_keepalive|use_null_delimiter|max_message_size|decompress_size_limit|number_worker_threads|tls_enable)$"))))}]' > "$E/graylog_inputs.json" 2>&1 || true
curl "${H[@]}" "$G/api/streams" | jq '[.streams[]|{id,title,description,index_set_id,matching_type,disabled,rules:[.rules[]?|{field,type,value,inverted}],outputs:(.outputs|length)}]' > "$E/graylog_streams.json" 2>&1 || true
curl "${H[@]}" "$G/api/system/indices/index_sets" | jq '[.index_sets[]|{id,title,description,index_prefix,shards,replicas,rotation_strategy_class,retention_strategy_class,default,writable}]' > "$E/graylog_index_sets.json" 2>&1 || true
{ echo "sf-monitoreo.smartfran.com resolves to (from this machine):"; getent hosts sf-monitoreo.smartfran.com || echo "no resolution"; } > "$E/graylog_dns.txt" 2>&1

echo "done: waf_to_graylog_*, graylog_inputs.json, graylog_streams.json, graylog_index_sets.json, graylog_dns.txt in $E"
