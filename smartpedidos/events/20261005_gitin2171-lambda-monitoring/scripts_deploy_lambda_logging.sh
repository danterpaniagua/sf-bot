#!/usr/bin/env bash
# GITIN-2171: deploy lambda_function_graylog.py to the PRODUCTION Lambda IntegrationLambdaEcsTaskProd (us-east-1), in separate phases.
# Usage: bash scripts_deploy_lambda_logging.sh <aws-cli-profile> <phase>
#   phase backup   : read-only. Saves the current code zip + configuration to data/ (needed for rollback).
#   phase deploy   : ⚠️ STATE-CHANGING. Replaces the function's code with lambda_function_graylog.py. Scaling logic is unchanged.
#   phase dryrun   : sends a {"dry_run": true} test event: describe_services (read) + Graylog logs, NO update_service.
#   phase rollback : ⚠️ STATE-CHANGING. Restores the code saved by `backup`.
# NOT included on purpose: timeout/memory changes (decision for GITIN-2170; commented example at the bottom).
# Prerequisite before `deploy`: the Graylog stream/index set for ServiceName=PlatformEscalado must exist, otherwise the messages
# land in the Default Stream (graylog_299, at the 1000-field mapping limit).
set -eu
HERE=/home/dpaniagua/Documentos/git/bots/smartpedidos/events/20261005_gitin2171-lambda-monitoring
E="$HERE/data"
P="${1:?usage: $0 <aws-cli-profile> <backup|deploy|dryrun|rollback>}"
PHASE="${2:?phase required}"
R=us-east-1
FN=IntegrationLambdaEcsTaskProd
A="aws --profile $P --region $R --output json"
TS=$(date +%Y%m%d_%H%M%S)
mkdir -p "$E"

case "$PHASE" in
  backup)
    $A lambda get-function-configuration --function-name "$FN" > "$E/lambda_${FN}_config_backup_$TS.json"
    URL=$($A lambda get-function --function-name "$FN" --query 'Code.Location' --output text)
    curl -fsS "$URL" -o "$E/lambda_${FN}_code_backup_$TS.zip"
    unzip -l "$E/lambda_${FN}_code_backup_$TS.zip" > "$E/lambda_${FN}_code_backup_${TS}_listing.txt"
    echo "backup: $E/lambda_${FN}_code_backup_$TS.zip (and config json)"
    ;;
  deploy)
    # ⚠️ production function: replaces the code (publishes $LATEST). Run `backup` first.
    TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
    cp "$HERE/lambda_function_graylog.py" "$TMP/lambda_function.py"      # handler stays lambda_function.lambda_handler
    (cd "$TMP" && zip -q code.zip lambda_function.py)
    $A lambda update-function-code --function-name "$FN" --zip-file "fileb://$TMP/code.zip" \
      --query '{FunctionName:FunctionName,LastModified:LastModified,CodeSha256:CodeSha256,LastUpdateStatus:LastUpdateStatus}' > "$E/lambda_deploy_result_$TS.json"
    aws --profile "$P" --region "$R" lambda wait function-updated --function-name "$FN"
    cat "$E/lambda_deploy_result_$TS.json"
    ;;
  dryrun)
    $A lambda invoke --function-name "$FN" --payload '{"dry_run": true}' --cli-binary-format raw-in-base64-out --log-type Tail \
      --query '{StatusCode:StatusCode,FunctionError:FunctionError,LogResult:LogResult}' "$E/lambda_dryrun_response_$TS.json" > "$E/lambda_dryrun_invoke_$TS.json"
    jq -r '.LogResult // empty' "$E/lambda_dryrun_invoke_$TS.json" | base64 -d > "$E/lambda_dryrun_log_tail_$TS.txt" || true
    jq '{StatusCode,FunctionError}' "$E/lambda_dryrun_invoke_$TS.json"; cat "$E/lambda_dryrun_log_tail_$TS.txt"
    ;;
  rollback)
    # ⚠️ production function: restores the newest code backup in data/
    ZIP=$(ls -t "$E"/lambda_${FN}_code_backup_*.zip | head -1)
    echo "restoring from: $ZIP"
    $A lambda update-function-code --function-name "$FN" --zip-file "fileb://$ZIP" --query '{LastModified:LastModified,CodeSha256:CodeSha256}' > "$E/lambda_rollback_result_$TS.json"
    aws --profile "$P" --region "$R" lambda wait function-updated --function-name "$FN"
    cat "$E/lambda_rollback_result_$TS.json"
    ;;
  *) echo "unknown phase: $PHASE"; exit 2 ;;
esac

# Optional, NOT run by this script (decision for GITIN-2170 — 7 of 23 recent invocations hit the 3 s timeout):
#   aws --profile <profile> --region us-east-1 lambda update-function-configuration --function-name IntegrationLambdaEcsTaskProd --timeout 10 --memory-size 256
