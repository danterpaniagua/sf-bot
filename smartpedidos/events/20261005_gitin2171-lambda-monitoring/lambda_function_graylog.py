"""
GITIN-2171 candidate (NOT deployed): IntegrationLambdaEcsTaskProd with structured logging to Graylog.

Scaling behaviour is intentionally identical to the function currently in production (GITIN-2170 owns any change to it):
if runningCount < TASK_LIMIT -> update_service(desiredCount=TASK_LIMIT), regardless of which SNS transition (ALARM/OK) invoked it.
What is new: (1) every step is logged as one JSON line to CloudWatch and as a GELF/UDP datagram to Graylog,
(2) the alarm name/state in the SNS message is logged, (3) `{"dry_run": true}` test events skip update_service,
(4) exceptions are logged and re-raised (same failure semantics as before).
Logging can never break the scaling path: every Graylog send is wrapped in try/except and UDP sendto does not wait for an answer.
"""
import json
import os
import socket
import time

import boto3

CLUSTER = 'smartfran-pedidos-production'
SERVICE = 'platform-service-production-service'
TASK_LIMIT = 15

GRAYLOG_ENABLED = os.environ.get('GRAYLOG_ENABLED', 'true').lower() == 'true'
GRAYLOG_HOST = os.environ.get('GRAYLOG_HOST', 'sf-monitoreo.smartfran.com')
GRAYLOG_PORT = int(os.environ.get('GRAYLOG_PORT', '12201'))  # existing GELF UDP input
SERVICE_NAME = os.environ.get('GRAYLOG_SERVICE_NAME', 'PlatformEscalado')  # routes the message to its Graylog stream

# GELF/syslog levels
_LEVELS = {'DEBUG': 7, 'INFO': 6, 'WARNING': 4, 'ERROR': 3}

_sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
_addr = None


def _graylog_addr():
    """Resolve once per container; never raises."""
    global _addr
    if _addr is None:
        try:
            _addr = (socket.gethostbyname(GRAYLOG_HOST), GRAYLOG_PORT)
        except Exception:
            _addr = False
    return _addr


def log(event_name, level='INFO', ctx=None, **fields):
    """One structured record -> CloudWatch (JSON line) and Graylog (GELF 1.1 over UDP)."""
    ctx = ctx or {}
    flat = {k: v for k, v in {**ctx, **fields}.items() if v is not None}
    now = time.time()
    print(json.dumps({'timestamp': now, 'service': SERVICE_NAME, 'level': level, 'category': 'INFRA',
                      'message': f'[INFRA/{level}] {event_name}', 'event': event_name, **flat}, default=str))
    if not GRAYLOG_ENABLED:
        return
    try:
        addr = _graylog_addr()
        if not addr:
            return
        gelf = {
            'version': '1.1',
            'host': ctx.get('function_name') or 'IntegrationLambdaEcsTaskProd',
            'short_message': f'[INFRA/{level}] {event_name}',
            'timestamp': now,
            'level': _LEVELS.get(level, 6),
            '_ServiceName': SERVICE_NAME,   # which Lambda (e.g. PlatformEscalado)
            '_ServiceType': 'Lambda',       # routes every Lambda to the shared SP_Lambdas stream
            '_category': 'INFRA',
            '_level_name': level,
            '_event': event_name,
        }
        for k, v in flat.items():
            if k == 'id':  # '_id' is reserved in GELF
                k = 'record_id'
            gelf['_' + k] = v if isinstance(v, (int, float, str)) and not isinstance(v, bool) else str(v)
        _sock.sendto(json.dumps(gelf, default=str).encode('utf-8'), addr)
    except Exception:
        pass  # logging must never affect scaling


def _alarm_info(event):
    """Alarm details from the SNS envelope; {} if the event is not an SNS alarm notification."""
    try:
        sns = event['Records'][0]['Sns']
        msg = json.loads(sns['Message'])
        return {
            'alarm_name': msg.get('AlarmName'),
            'alarm_state': msg.get('NewStateValue'),
            'alarm_old_state': msg.get('OldStateValue'),
            'alarm_reason': (msg.get('NewStateReason') or '')[:300],
            'sns_message_id': sns.get('MessageId'),
        }
    except Exception:
        return {}


def lambda_handler(event, context):
    dry_run = isinstance(event, dict) and bool(event.get('dry_run'))
    ctx = {'aws_request_id': getattr(context, 'aws_request_id', None),
           'function_name': getattr(context, 'function_name', None),
           'cluster': CLUSTER, 'ecs_service': SERVICE, 'dry_run': dry_run}
    alarm = _alarm_info(event)
    log('invoked', ctx=ctx, **alarm)

    try:
        ecs_client = boto3.client('ecs')
        response = ecs_client.describe_services(cluster=CLUSTER, services=[SERVICE])
        svc = response['services'][0]
        running, desired, pending = svc['runningCount'], svc['desiredCount'], svc['pendingCount']
        log('scale_check', ctx=ctx, running=running, desired=desired, pending=pending, limit=TASK_LIMIT,
            remaining_ms=context.get_remaining_time_in_millis(), **alarm)

        if running < TASK_LIMIT:
            if dry_run:
                log('scale_skipped_dry_run', ctx=ctx, running=running, would_set_desired=TASK_LIMIT, **alarm)
            else:
                ecs_client.update_service(cluster=CLUSTER, service=SERVICE, desiredCount=TASK_LIMIT)
                log('scale_update_requested', ctx=ctx, running=running, previous_desired=desired,
                    new_desired=TASK_LIMIT, remaining_ms=context.get_remaining_time_in_millis(), **alarm)
            return {
                'statusCode': 200,
                'body': f'Tareas Previas: {running}.\nTareas aumentadas a {TASK_LIMIT}.\nTareas Deseadas: {desired}'
            }
        log('scale_not_needed', ctx=ctx, running=running, desired=desired, limit=TASK_LIMIT, **alarm)
        return {'statusCode': 200, 'body': f'No se aumentaron tareas. Tareas: {running}'}
    except Exception as exc:
        log('error', level='ERROR', ctx=ctx, error_type=type(exc).__name__, error=str(exc)[:300], **alarm)
        raise
