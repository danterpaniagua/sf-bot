#!/usr/bin/env bash
# Event: 20261017_gitin2248-platform-contenedores-caidos-20261016
# C3 - SOLO LECTURA contra sf-monitoreo.smartfran.com:9000 (Graylog de SmartPedidos). Token en $SML_GRAYLOG_API_KEY (nunca literal). Adaptado de scripts-c5.sh del evento 20261014_gitin2222-ecs-reinicios-avisos-sns.
#      Mensajes "[INFRA/FATAL] unhandled_rejection" de platforms-service en los dias -03:00 del 14, 15 y 16 de octubre (cada dia = 03:00Z a 03:00Z del siguiente, en ventanas de 6 horas para no pasar el limite de 500).
#      Por dia: total, y la clasificacion por firma del error: "Cannot call a class as a function" (causa H4, corregida por el PR #139), "Converting circular structure to JSON" (causa H5, sin corregir) y otras;
#      por hora -03:00; y primera y ultima hora de cada firma. Si la firma H4 deja de aparecer a cierta hora del 16-10, esa hora acota el momento en que el codigo corregido empezo a correr (inferencia, no lectura de la revision).
#      Consultas segun docs/graylog_infrastructure.md: solo GET search/universal/absolute, fechas ISO con Z, una frase entre comillas (Graylog responde 500 a OR/AND con texto libre).
#      Salidas en data/c3/: detail-<dia>-<n>.json (mensajes crudos; pueden tener datos de ordenes; **.json esta excluido de git: no pegar ni subir) y resumen-<dia>.tsv (enmascarado).
set -euo pipefail
trap 'echo "FALLO en linea $LINENO: $BASH_COMMAND" >&2' ERR
: "${SML_GRAYLOG_API_KEY:?definir SML_GRAYLOG_API_KEY en el entorno}"
export LC_ALL=C
BASE="http://sf-monitoreo.smartfran.com:9000/api"
OUT="/home/dpaniagua/Documentos/git/bots/smartpedidos/events/20261017_gitin2248-platform-contenedores-caidos-20261016/data/c3"
mkdir -p "$OUT"
fmt() { date -u -d "@$1" +"%Y-%m-%dT%H:%M:%S.000Z"; }
mask() { sed -E 's/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]+/[correo]/g; s/[0-9]{7,}/[num]/g'; }
echo "run $(date -u +%FT%TZ)"
for d in 2026-10-14 2026-10-15 2026-10-16; do
  : > "$OUT/resumen-$d.tsv"; total=0; incompleto=0
  for k in 0 1 2 3; do
    f=$(date -u -d "${d}T03:00:00Z" +%s); f=$((f + k*21600)); t=$((f + 21600))
    code=$(curl -sS -G -u "$SML_GRAYLOG_API_KEY:token" -H 'Accept: application/json' -o "$OUT/detail-$d-$k.json" -w '%{http_code}' "$BASE/search/universal/absolute" \
      --data-urlencode 'query="unhandled_rejection"' --data-urlencode "from=$(fmt $f)" --data-urlencode "to=$(fmt $t)" --data-urlencode "limit=500" \
      --data-urlencode "fields=timestamp,source,message" --data-urlencode "sort=timestamp:asc") || code=curl-fallo
    [ "$code" = 200 ] || { echo "$d ventana $k HTTP=$code"; head -c 200 "$OUT/detail-$d-$k.json"; echo; continue; }
    n=$(jq -r '.total_results' "$OUT/detail-$d-$k.json"); got=$(jq -r '.messages|length' "$OUT/detail-$d-$k.json")
    total=$((total + n)); [ "$got" -lt "$n" ] && incompleto=1
    jq -r '.messages[].message as $m | ($m.message | fromjson? // {message: $m.message}) as $j
       | [$m.timestamp[0:19], ($j.level // "-" | tostring), (($j.message // "") | tostring)[0:60], (($j.error // "") | tostring | gsub("[\t\n]"; " ") | .[0:400])] | @tsv' "$OUT/detail-$d-$k.json" | mask >> "$OUT/resumen-$d.tsv"
  done
  echo; echo "== $d (-03:00): coincidencias total=$total$( [ "$incompleto" = 1 ] && echo '  (INCOMPLETO: una ventana paso el limite 500)') | filas en el resumen: $(wc -l < "$OUT/resumen-$d.tsv")"
  python3 - "$OUT/resumen-$d.tsv" <<'PY'
import sys,collections,datetime
rows=[l.rstrip("\n").split("\t") for l in open(sys.argv[1]) if l.strip()]
def sig(r):
    t=" ".join(r).lower()
    if "cannot call a class" in t: return "H4 cannot-call-class"
    if "circular structure" in t: return "H5 circular-json"
    return "otra"
def loc(ts):  # UTC -> -03:00
    return (datetime.datetime.strptime(ts[:19],"%Y-%m-%dT%H:%M:%S")-datetime.timedelta(hours=3))
c=collections.Counter(sig(r) for r in rows)
print("   por firma:",dict(c))
for s in sorted(c):
    ts=sorted(loc(r[0]) for r in rows if sig(r)==s)
    print(f"   {s}: primera {ts[0]:%H:%M:%S} ultima {ts[-1]:%H:%M:%S}")
h=collections.Counter(loc(r[0]).hour for r in rows)
print("   por hora -03:00:"," ".join(f"{k:02d}:{h[k]}" for k in sorted(h)))
otras=collections.Counter(r[3][:110] for r in rows if sig(r)=="otra")
for k,v in otras.most_common(4): print("   otra:",v,k)
PY
done
echo listo
