"""
GITIN-2171: local test of lambda_function_graylog.py. No AWS access: boto3 is stubbed; Graylog is a UDP socket on 127.0.0.1.
Usage: python3 test_lambda_local.py
Checks: GELF fields/ServiceName, update_service called only when expected, dry_run skips it, errors are logged AND re-raised,
and that a dead Graylog address never breaks the handler.
"""
import importlib.util
import json
import os
import socket
import sys
import types

HERE = os.path.dirname(os.path.abspath(__file__))

# --- Graylog stand-in -------------------------------------------------------
rx = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
rx.bind(('127.0.0.1', 0))
rx.settimeout(1.0)
os.environ['GRAYLOG_HOST'] = '127.0.0.1'
os.environ['GRAYLOG_PORT'] = str(rx.getsockname()[1])

# --- boto3 stub -------------------------------------------------------------
class FakeECS:
    def __init__(self, running, desired, pending=0, fail=False):
        self.s = {'runningCount': running, 'desiredCount': desired, 'pendingCount': pending}
        self.fail = fail
        self.updates = []

    def describe_services(self, cluster, services):
        if self.fail:
            raise RuntimeError('simulated describe_services failure')
        return {'services': [self.s]}

    def update_service(self, cluster, service, desiredCount):
        self.updates.append((cluster, service, desiredCount))


current = {}
boto3_stub = types.ModuleType('boto3')
boto3_stub.client = lambda name: current['ecs']
sys.modules['boto3'] = boto3_stub

spec = importlib.util.spec_from_file_location('lf', os.path.join(HERE, 'lambda_function_graylog.py'))
lf = importlib.util.module_from_spec(spec)
spec.loader.exec_module(lf)


class Ctx:
    aws_request_id = 'test-req-1'
    function_name = 'IntegrationLambdaEcsTaskProd'
    def get_remaining_time_in_millis(self): return 2500


def sns_event(state, old):
    msg = {'AlarmName': 'sendMailOldestMessage', 'NewStateValue': state, 'OldStateValue': old,
           'NewStateReason': 'Threshold Crossed: 1 datapoint [58.0] was greater than the threshold (25.0).'}
    return {'Records': [{'Sns': {'MessageId': 'm-1', 'Message': json.dumps(msg)}}]}


def drain():
    out = []
    while True:
        try:
            out.append(json.loads(rx.recv(65535)))
        except socket.timeout:
            return out


def run(title, ecs, event, expect_updates, expect_events, raises=False):
    current['ecs'] = ecs
    err = None
    try:
        res = lf.lambda_handler(event, Ctx())
    except Exception as e:
        err, res = e, None
    msgs = drain()
    events = [m['_event'] for m in msgs]
    ok = (ecs.updates == expect_updates) and (events == expect_events) and (bool(err) == raises) \
        and all(m['_ServiceName'] == lf.SERVICE_NAME and m['_ServiceType'] == 'Lambda' and m['version'] == '1.1' and 'short_message' in m for m in msgs)
    print(f"[{'PASS' if ok else 'FAIL'}] {title}: updates={ecs.updates} events={events} raised={type(err).__name__ if err else None}")
    for m in msgs:
        print('   GELF', json.dumps({k: v for k, v in m.items() if k not in ('timestamp',)}, sort_keys=True))
    return ok


results = [
    run('ALARM, running 5 -> update to 15', FakeECS(5, 5), sns_event('ALARM', 'OK'),
        [('smartfran-pedidos-production', 'platform-service-production-service', 15)],
        ['invoked', 'scale_check', 'scale_update_requested']),
    run('OK transition, running 14 -> still updates to 15 (current production behaviour, kept)', FakeECS(14, 14), sns_event('OK', 'ALARM'),
        [('smartfran-pedidos-production', 'platform-service-production-service', 15)],
        ['invoked', 'scale_check', 'scale_update_requested']),
    run('running 15 -> no update', FakeECS(15, 15), sns_event('ALARM', 'OK'),
        [], ['invoked', 'scale_check', 'scale_not_needed']),
    run('dry_run test event, running 5 -> no update', FakeECS(5, 5), {'dry_run': True},
        [], ['invoked', 'scale_check', 'scale_skipped_dry_run']),
    run('describe fails -> error logged and re-raised', FakeECS(5, 5, fail=True), sns_event('ALARM', 'OK'),
        [], ['invoked', 'error'], raises=True),
]

# Dead Graylog address must not break the handler
lf._addr = ('127.0.0.1', 9)  # discard port; nothing listens
current['ecs'] = FakeECS(5, 5)
try:
    lf.lambda_handler(sns_event('ALARM', 'OK'), Ctx())
    ok = current['ecs'].updates == [('smartfran-pedidos-production', 'platform-service-production-service', 15)]
except Exception as e:
    ok = False
print(f"[{'PASS' if ok else 'FAIL'}] unreachable Graylog: handler still scales")
results.append(ok)
lf._addr = False  # unresolvable host
current['ecs'] = FakeECS(5, 5)
try:
    lf.lambda_handler(sns_event('ALARM', 'OK'), Ctx())
    ok = len(current['ecs'].updates) == 1
except Exception:
    ok = False
print(f"[{'PASS' if ok else 'FAIL'}] unresolvable Graylog host: handler still scales")
results.append(ok)

print('ALL PASS' if all(results) else 'SOME FAILED')
sys.exit(0 if all(results) else 1)
