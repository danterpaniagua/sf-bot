#!/usr/bin/env bash
# GITIN-2171: how do AWS-side logs reach the SmartPedidos Graylog today, and is the Graylog host reachable from AWS Lambda?
# Usage: bash scripts_aws_graylog_pipeline_recon.sh <aws-cli-profile>
# Read-only AWS calls only (kinesis/firehose list+describe, logs describe-log-groups/subscription-filters, ec2 describe-*).
# Writes JSON under data/. Nothing is created or changed.
set -eu
E=/home/dpaniagua/Documentos/git/bots/smartpedidos/events/20261005_gitin2171-lambda-monitoring/data
P="${1:?usage: $0 <aws-cli-profile>}"
mkdir -p "$E"
GL_IP=3.214.234.76   # sf-monitoreo.smartfran.com (ec2-3-214-234-76.compute-1.amazonaws.com), from DNS on 2026-10-05

for R in us-east-1 us-east-2; do
  A="aws --profile $P --region $R --output json"
  $A kinesis list-streams > "$E/kinesis_streams_$R.json" 2> "$E/kinesis_streams_${R}_stderr.txt" || true
  $A firehose list-delivery-streams > "$E/firehose_streams_$R.json" 2> "$E/firehose_streams_${R}_stderr.txt" || true
  for D in $(jq -r '.DeliveryStreamNames[]?' "$E/firehose_streams_$R.json" 2>/dev/null); do
    $A firehose describe-delivery-stream --delivery-stream-name "$D" --query 'DeliveryStreamDescription.{Name:DeliveryStreamName,Type:DeliveryStreamType,Status:DeliveryStreamStatus,Source:Source,Destinations:Destinations[].{Id:DestinationId,HttpEndpoint:HttpEndpointDestinationDescription.EndpointConfiguration.Url,S3:ExtendedS3DestinationDescription.BucketARN,Processing:ExtendedS3DestinationDescription.ProcessingConfiguration}}' > "$E/firehose_${R}_${D}.json" 2>&1 || true
  done
  # Log groups (names only), then subscription filters for every log group
  $A logs describe-log-groups --query 'logGroups[].logGroupName' > "$E/log_groups_$R.json" 2> "$E/log_groups_${R}_stderr.txt" || true
  : > "$E/log_subscription_filters_$R.jsonl"
  for LG in $(jq -r '.[]?' "$E/log_groups_$R.json" 2>/dev/null); do
    $A logs describe-subscription-filters --log-group-name "$LG" 2>/dev/null | jq -c --arg lg "$LG" 'select((.subscriptionFilters|length)>0)|{logGroup:$lg,filters:[.subscriptionFilters[]|{filterName,destinationArn,filterPattern}]}' >> "$E/log_subscription_filters_$R.jsonl" || true
  done
done

# Graylog host (us-east-1): instance, security groups, and the inbound rules (which ports/CIDRs allow UDP 12201 / 11514 etc.)
A1="aws --profile $P --region us-east-1 --output json"
$A1 ec2 describe-instances --filters "Name=ip-address,Values=$GL_IP" --query 'Reservations[].Instances[].{Id:InstanceId,Type:InstanceType,State:State.Name,Name:Tags[?Key==`Name`]|[0].Value,PublicIp:PublicIpAddress,SGs:SecurityGroups[].GroupId,VpcId:VpcId}' > "$E/graylog_host_instance.json" 2>&1 || true
SGS=$(jq -r '.[]?.SGs[]?' "$E/graylog_host_instance.json" 2>/dev/null | sort -u | tr '\n' ' ')
if [ -n "$SGS" ]; then
  # shellcheck disable=SC2086
  $A1 ec2 describe-security-groups --group-ids $SGS --query 'SecurityGroups[].{Id:GroupId,Name:GroupName,Inbound:IpPermissions[].{Proto:IpProtocol,From:FromPort,To:ToPort,Cidrs:IpRanges[].CidrIp,SGs:UserIdGroupPairs[].GroupId}}' > "$E/graylog_host_security_groups.json" 2>&1 || true
fi
echo "done: files in $E (kinesis_*, firehose_*, log_subscription_filters_*, graylog_host_*)"
