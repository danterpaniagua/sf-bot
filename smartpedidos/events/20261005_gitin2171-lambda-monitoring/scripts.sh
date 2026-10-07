#!/usr/bin/env bash
# GITIN-2171 — commands run during the scoping (2026-10-05). Real outputs are in data/ (file names noted per command).
# ⚠️ marks commands that change state. Credentials are referenced only by variable name ($SML_GRAYLOG_API_KEY), never by value.
D=/home/dpaniagua/Documentos/git/bots/smartpedidos/events/20261005_gitin2171-lambda-monitoring/data
GL=http://sf-monitoreo.smartfran.com:9000

# === INVESTIGATION (read-only) ===
# C1 — Graylog + waf-to-graylog recon (inputs, streams, index sets, DNS, precedent Lambda). Script and outputs live in the GITIN-2170 folder:
#      scripts_graylog_integration_recon.sh <aws-profile>      (needs $SML_GRAYLOG_API_KEY)
# C2 — AWS-side recon: Kinesis/Firehose streams, log-group subscription filters, Graylog host security groups:
#      bash scripts_aws_graylog_pipeline_recon.sh <aws-profile>        -> data/kinesis_*, firehose_*, log_subscription_filters_*, graylog_host_*
# C3 — Backup of the production Lambda (read-only; code zip + configuration):
#      bash scripts_deploy_lambda_logging.sh <aws-profile> backup       -> data/lambda_IntegrationLambdaEcsTaskProd_code_backup_20261005_141508.zip (+ config json)
# C4 — List stream and index-set titles visible to the token (check before creating anything):
curl -sS -m 30 -u "$SML_GRAYLOG_API_KEY:token" -H 'Accept: application/json' $GL/api/streams | jq -r '.streams[]|[.title,.id,.index_set_id,(.disabled|tostring)]|@tsv'
curl -sS -m 30 -u "$SML_GRAYLOG_API_KEY:token" -H 'Accept: application/json' $GL/api/system/indices/index_sets | jq -r '.index_sets[]|[.title,.id,.index_prefix]|@tsv'
#      -> data/graylog_titles_check_*.txt
# C5 — Build the index-set body by copying SP_Platform's settings (GET only), then adjusting shards/rotation/retention:
curl -sS -m 30 -u "$SML_GRAYLOG_API_KEY:token" -H 'Accept: application/json' $GL/api/system/indices/index_sets/690ca0884481462b84da1c23 \
  | jq 'del(.id,.index_match_pattern,.index_wildcard,.can_be_default,.default,.data_tiering) | .title="SP_Lambda" | .description="Logs de Lambdas de SmartPedidos" | .index_prefix="sp_lambda_" | .creation_date=(now|todate) | .writable=true' >| "$D/graylog_indexset_SP_Lambda_body.json"
jq '.shards=1 | .rotation_strategy.rotation_period="P1W" | .retention_strategy.max_number_of_indices=52 | .creation_date=(now|todate)' "$D/graylog_indexset_SP_Lambda_body.json" >| "$D/graylog_indexset_SP_Lambda_body_final.json"
# C8 — Verify the created stream (GET):
curl -sS -m 30 -u "$SML_GRAYLOG_API_KEY:token" -H 'Accept: application/json' $GL/api/streams/6ac3da4aa85d5c4a53684559 | jq '{id,title,index_set_id,disabled,remove_matches_from_default_stream,matching_type,rules:[.rules[]|{field,type,value,inverted}]}'
#      -> data/graylog_stream_SP_Lambdas_verify_*.json
# C10 — Local test of the (now shelved) in-function logging candidate; boto3 stubbed, no AWS access:
#      python3 test_lambda_local.py                                    -> data/test_lambda_local_output.txt  (ALL PASS, 7 checks)

# === REMEDIATION — Graylog objects (run by the user) ===
# ⚠️ C6 — Create index set SP_Lambda (id 6ac3da20a85d5c4a5368453e)                -> data/graylog_indexset_SP_Lambda_create_*.json
curl -sS -m 30 -u "$SML_GRAYLOG_API_KEY:token" -H 'Accept: application/json' -H 'Content-Type: application/json' -H 'X-Requested-By: cli' \
  -X POST $GL/api/system/indices/index_sets -d @"$D/graylog_indexset_SP_Lambda_body_final.json"
# ⚠️ C7 — Create stream SP_Lambdas (id 6ac3da4aa85d5c4a53684559), rule ServiceType = Lambda, removes matches from the Default Stream (created paused)
#                                                                                  -> data/graylog_stream_SP_Lambdas_create_*.json
curl -sS -m 30 -u "$SML_GRAYLOG_API_KEY:token" -H 'Accept: application/json' -H 'Content-Type: application/json' -H 'X-Requested-By: cli' \
  -X POST $GL/api/streams -d '{"title":"SP_Lambdas","description":"Logs de Lambdas de SmartPedidos","index_set_id":"6ac3da20a85d5c4a5368453e","matching_type":"AND","remove_matches_from_default_stream":true,"rules":[{"field":"ServiceType","type":1,"value":"Lambda","inverted":false,"description":"ServiceType = Lambda"}]}'
# ⚠️ C9 — Start (resume) the stream                                                -> data/graylog_stream_SP_Lambdas_resume_*
curl -sS -m 30 -u "$SML_GRAYLOG_API_KEY:token" -H 'Accept: application/json' -H 'X-Requested-By: cli' -X POST $GL/api/streams/6ac3da4aa85d5c4a53684559/resume

# === REMEDIATION — AWS Kinesis path and Graylog input (run by the user, 2026-10-05) ===
# C11 — Read the existing Kinesis -> Graylog pattern (subscription filters + roles, Kinesis summaries, DynamoDB tables, Graylog AWS-input attribute names):
#       SML_GRAYLOG_API_KEY="$SML_GRAYLOG_API_KEY" bash scripts_kinesis_pattern_recon.sh <aws-profile>      -> data/subfilter_full_*, role_*, kinesis_summary_*, dynamodb_tables_*, graylog_aws_inputs_attributes.json
# C12 — Which IAM identity the existing Graylog AWS inputs use and its policies (key IDs masked, user name masked in the saved file):
#       SML_GRAYLOG_API_KEY="$SML_GRAYLOG_API_KEY" bash scripts_graylog_input_credentials_recon.sh <aws-profile>   -> data/graylog_aws_input_credentials_*.txt
# ⚠️ C13 — Per-Lambda names first run by mistake, then removed (stream/role/policy/filter named IntegrationLambdaEcsTaskProd):
#       bash scripts_kinesis_cleanup_old_names.sh <aws-profile> check | cleanup                              -> data/kinesis_old_names_check_*.txt
# ⚠️ C14 — Generic stream sp-lambda-logs + role graylog-cloudwatch-role-sp-lambda-logs (create), then the subscription filter on the Lambda's log group (subscribe), and read-back (verify):
#       bash scripts_kinesis_setup.sh <aws-profile> create
#       bash scripts_kinesis_setup.sh <aws-profile> subscribe /aws/lambda/IntegrationLambdaEcsTaskProd
#       bash scripts_kinesis_setup.sh <aws-profile> verify                                                    -> data/kinesis_setup_verify_*.txt
# ⚠️ C15 — Graylog AWS input sp-lambda-logs (copy of the platform input's settings, existing key; secret never printed/stored):
#       SML_GRAYLOG_API_KEY="$SML_GRAYLOG_API_KEY" bash scripts_graylog_input_create.sh <aws-profile>        -> data/graylog_input_create_*.json (id 6ac3e173a85d5c4a536857f7)
# ⚠️ C16 — Stream SP_Lambdas: add match-input rule and switch to OR:
#       SML_GRAYLOG_API_KEY="$SML_GRAYLOG_API_KEY" bash scripts_graylog_stream_rule.sh                        -> data/graylog_stream_SP_Lambdas_after_rule_*.json
# ⚠️ C17 — Synthetic test line in the Lambda's log group (a separate log stream; no Lambda invocation):
aws --profile <aws-profile> --region us-east-1 logs create-log-stream --log-group-name /aws/lambda/IntegrationLambdaEcsTaskProd --log-stream-name gitin2171-pipeline-test
aws --profile <aws-profile> --region us-east-1 logs put-log-events --log-group-name /aws/lambda/IntegrationLambdaEcsTaskProd --log-stream-name gitin2171-pipeline-test --log-events timestamp=$(date +%s%3N),message="GITIN-2171 pipeline test line - no Lambda invocation"
# C18 — Graylog views search on the new input (gl2_source_input:6ac3e173a85d5c4a536857f7, 24 h):                -> data/graylog_search_sp_lambda_logs_*.json

# Not run (shelved after the "do not modify the Lambda" decision): scripts_deploy_lambda_logging.sh <profile> deploy | dryrun | rollback
# Not run (decision "reuse the existing key"): scripts_graylog_input_iam.sh <profile> create | verify | rollback
