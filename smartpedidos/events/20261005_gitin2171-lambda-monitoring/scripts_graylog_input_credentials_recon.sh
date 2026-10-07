#!/usr/bin/env bash
# GITIN-2171: which IAM identity do the existing Graylog AWS inputs use, and what may it do? (needed to give the new
# `sp-lambda-logs` input the right access to its Kinesis stream and DynamoDB lease table).
# Usage: SML_GRAYLOG_API_KEY="$SML_GRAYLOG_API_KEY" bash scripts_graylog_input_credentials_recon.sh <aws-cli-profile>
# Read-only. The access key ID stored in each input is read into shell variables and NEVER printed or written to a file; outputs use
# masked IDs (AKIA************XXXX). The secret keys are not read at all (the API returns them masked and this script does not touch them).
set -eu
E=/home/dpaniagua/Documentos/git/bots/smartpedidos/events/20261005_gitin2171-lambda-monitoring/data
P="${1:?usage: $0 <aws-cli-profile>}"
: "${SML_GRAYLOG_API_KEY:?SML_GRAYLOG_API_KEY not set (pass it as shown in the usage line)}"
A="aws --profile $P --output json"
mkdir -p "$E"
mask() { sed -E 's/(AKIA|ASIA)[A-Z0-9]{12}([A-Z0-9]{4})/\1************\2/g'; }

INPUTS=$(curl -sS -m 30 -u "$SML_GRAYLOG_API_KEY:token" -H 'Accept: application/json' http://sf-monitoreo.smartfran.com:9000/api/system/inputs)
TITLES=$(echo "$INPUTS" | jq -r '.inputs[]|select(.type|test("AWS"))|.title')

{
  echo "== access key per AWS input (masked), user it belongs to, last use"
  FIRST_USER=""
  while IFS= read -r T; do
    KID=$(echo "$INPUTS" | jq -r --arg t "$T" '.inputs[]|select(.title==$t)|.attributes.aws_access_key')
    MASKED=$(echo "$KID" | mask)
    USERINFO=$($A --region us-east-1 iam get-access-key-last-used --access-key-id "$KID" --query '{UserName:UserName,LastUsed:AccessKeyLastUsed.LastUsedDate,Service:AccessKeyLastUsed.ServiceName}' 2>&1 | tr -d '\n' | mask || true)
    echo "$T | key $MASKED | $USERINFO"
    U=$(echo "$USERINFO" | jq -r '.UserName // empty' 2>/dev/null || true)
    [ -z "$FIRST_USER" ] && [ -n "$U" ] && FIRST_USER="$U"
    unset KID
  done <<< "$TITLES"
  echo "== principal examined: ${FIRST_USER:-none found}"
  if [ -n "$FIRST_USER" ]; then
    echo "== user"; $A iam get-user --user-name "$FIRST_USER" --query 'User.{UserName:UserName,Created:CreateDate,PasswordLastUsed:PasswordLastUsed}' | mask
    echo "== access keys of that user (status, created)"; $A iam list-access-keys --user-name "$FIRST_USER" --query 'AccessKeyMetadata[].{Id:AccessKeyId,Status:Status,Created:CreateDate}' | mask
    echo "== groups"; $A iam list-groups-for-user --user-name "$FIRST_USER" --query 'Groups[].GroupName'
    echo "== attached managed policies"; $A iam list-attached-user-policies --user-name "$FIRST_USER" --query 'AttachedPolicies[].PolicyArn'
    echo "== inline policy names"; $A iam list-user-policies --user-name "$FIRST_USER" --query 'PolicyNames'
    for PA in $($A iam list-attached-user-policies --user-name "$FIRST_USER" --query 'AttachedPolicies[].PolicyArn' --output text); do
      V=$($A iam get-policy --policy-arn "$PA" --query 'Policy.DefaultVersionId' --output text)
      echo "-- policy $PA"; $A iam get-policy-version --policy-arn "$PA" --version-id "$V" --query 'PolicyVersion.Document.Statement' | mask
    done
    for PN in $($A iam list-user-policies --user-name "$FIRST_USER" --query 'PolicyNames[]' --output text); do
      echo "-- inline policy $PN"; $A iam get-user-policy --user-name "$FIRST_USER" --policy-name "$PN" --query 'PolicyDocument.Statement' | mask
    done
  fi
} > "$E/graylog_aws_input_credentials_$(date +%Y%m%d_%H%M%S).txt" 2>&1
cat "$E"/graylog_aws_input_credentials_*.txt | tail -n 200
