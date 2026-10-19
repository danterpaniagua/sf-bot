#!/usr/bin/env python3
# Event: 20261014_gitin2222-ecs-reinicios-avisos-sns
# C6 - SOLO LECTURA, local. Cuenta los avisos SNS de un buzon mbox de Thunderbird (el usuario lo exporto como ~/Downloads/AWS; el .msf es solo el indice y no hace falta).
#      Lee cabeceras y cuerpo solo para extraer: hora del aviso ("A las <ts>"), tipo de cambio, Status, revision de la task definition y topic (nombre sacado de x-amz-sns-subscription-arn).
#      No imprime ni guarda direcciones de correo ni ARN de suscripcion. Salida: data/c6-mailbox-*.tsv (conteos) + resumen por pantalla.
# Uso:  python3 -I scripts-c6.py <ruta mbox> <carpeta data>   (ejecutar fuera de la carpeta que contiene el mbox)
import mailbox, sys, re, collections, email.utils, datetime as dt, os

mbox_path, out_dir = sys.argv[1], sys.argv[2]
ART = dt.timezone(dt.timedelta(hours=-3))
rows = []; seen = collections.Counter(); unparsed = 0
for m in mailbox.mbox(mbox_path):
    body = ''
    for part in (m.walk() if m.is_multipart() else [m]):
        if part.get_content_type() == 'text/plain':
            p = part.get_payload(decode=True) or b''
            body += p.decode(part.get_content_charset() or 'utf-8', 'replace')
    sub = (m.get('x-amz-sns-subscription-arn') or '')
    topic = sub.split(':')[5] if sub.count(':') >= 5 else '?'
    mid = m.get('x-amz-sns-message-id') or ''
    seen[mid] += 1
    mt = re.search(r'A las (\d{4}-\d\d-\d\dT[\d:]+Z) se ha detectado un cambio \(([^)]+)\)', body)
    if not mt:
        unparsed += 1
        rows.append(dict(topic=topic, ts=None, kind='?', status='-', rev='-', mid=mid)); continue
    ts = dt.datetime.strptime(mt.group(1), '%Y-%m-%dT%H:%M:%SZ').replace(tzinfo=dt.timezone.utc)
    st = re.search(r'Status:\s*(\w+)', body); rv = re.search(r'task-definition/([\w\-]+):(\d+)', body)
    rows.append(dict(topic=topic, ts=ts, kind=mt.group(2), status=st.group(1) if st else '-', rev=(rv.group(1).split('-')[0] + ':' + rv.group(2)) if rv else '-', mid=mid))

n = len(rows)
print('mensajes', n, '| sin patron reconocido', unparsed, '| ids SNS repetidos (mismo mensaje varias veces)', sum(1 for c in seen.values() if c > 1 and True))
print('por topic y tipo:'); [print('  ', c, k) for k, c in collections.Counter((r['topic'], r['kind']) for r in rows).most_common()]
team = [r for r in rows if r['ts'] and r['status'] != '-']
print('con Status (plantilla del topic Team):', len(team)); [print('  ', c, k) for k, c in collections.Counter(r['status'] for r in team).most_common()]
print('revisiones (Team):'); [print('  ', c, k) for k, c in collections.Counter(r['rev'] for r in team).most_common(8)]
stopped = [r for r in team if r['status'] == 'STOPPED']

def day(r): return r['ts'].astimezone(ART).strftime('%Y-%m-%d')
print('STOPPED por dia (-03:00) | todos los Team por dia:')
alld = collections.Counter(day(r) for r in team); sd = collections.Counter(day(r) for r in stopped)
for d in sorted(alld): print('  ', d, 'STOPPED', sd.get(d, 0), 'Team', alld[d])
hh = collections.Counter(r['ts'].astimezone(ART).strftime('%Y-%m-%d %H:00') for r in stopped)
print('horas con mas STOPPED (-03:00):'); [print('  ', k, c) for k, c in hh.most_common(12)]
byrev = collections.Counter((day(r), r['rev']) for r in stopped)
os.makedirs(out_dir, exist_ok=True)
with open(os.path.join(out_dir, 'c6-mailbox-stopped-hourly.tsv'), 'w') as f:
    for k in sorted(hh): f.write(f'{k}\t{hh[k]}\n')
with open(os.path.join(out_dir, 'c6-mailbox-team-daily.tsv'), 'w') as f:
    for d in sorted(alld): f.write(f'{d}\t{alld[d]}\t{sd.get(d, 0)}\n')
print('archivos: c6-mailbox-stopped-hourly.tsv, c6-mailbox-team-daily.tsv en', out_dir)

# --- segunda parte: eventos unicos (el topic Team llega 2 veces por mensaje: 2 suscriptores) y revisiones
uniq = {}
for r in team:
    uniq.setdefault(r['mid'], r)
U = list(uniq.values())
print('\neventos unicos del topic Team (mensajes SNS distintos):', len(U), '| copias por mensaje:', collections.Counter(seen[r['mid']] for r in U).most_common(3))
print('primera / ultima aparicion por revision (PROVISIONING y STOPPED), hora -03:00:')
for rev in sorted({r['rev'] for r in U}):
    ts = sorted(r['ts'] for r in U if r['rev'] == rev and r['status'] == 'PROVISIONING')
    st = sorted(r['ts'] for r in U if r['rev'] == rev and r['status'] == 'STOPPED')
    f = lambda t: t.astimezone(ART).strftime('%m-%d %H:%M') if t else '-'
    print('  ', rev, 'primer PROVISIONING', f(ts[0] if ts else None), '| ultimo PROVISIONING', f(ts[-1] if ts else None), '| STOPPED unicos', len(st), '| ultimo STOPPED', f(st[-1] if st else None))
print('STOPPED unicos por dia y revision de platform (-03:00):')
ud = collections.Counter((day(r), r['rev']) for r in U if r['status'] == 'STOPPED' and r['rev'].startswith('platform'))
for d in sorted({k[0] for k in ud}):
    print('  ', d, ', '.join(f'{k[1]}={c}' for k, c in sorted(ud.items()) if k[0] == d))
with open(os.path.join(out_dir, 'c6-mailbox-unique-stopped-by-rev-day.tsv'), 'w') as f:
    for (d, rev), c in sorted(ud.items()): f.write(f'{d}\t{rev}\t{c}\n')
