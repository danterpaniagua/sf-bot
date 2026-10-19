#!/usr/bin/env python3
"""GITIN-2218 — en el widget "Sales Endpoints" del dashboard Operations, las columnas max/avg/P90 pasan de ElapsedMilliseconds a
ElapsedMillisecondsOpe (el campo que Logstash llena para Sales desde 2026-10-13 ~20:03 UTC). Los otros 7 Endpoints no se tocan.
Uso:  widgets_sales_ope.py            simulacion: lee el dashboard, arma el payload en data/, muestra el cambio; NO escribe en Graylog
      APPLY=1 widgets_sales_ope.py    aplica: guarda una busqueda nueva y reemplaza la definicion (PUT /views/{id} con {"entity": ...})
      APPLY=1 widgets_sales_ope.py rollback   restaura data/salesope-before-view.json y salesope-before-search.json
Token en $GRAYLOG_API_KEY (nunca literal)."""
import os, sys, json, copy, base64, urllib.request, urllib.error
BASE = "https://sfcloud-monitoreo.smartfran.com/graylog/api"
OUT = "/home/dpaniagua/Documentos/git/bots/cloud/events/20261013_gitin2218-graylog-visibilidad/data"
VID = "6ace703e41759be0a237ff89"
APPLY = os.environ.get("APPLY") == "1"
MODE = sys.argv[1] if len(sys.argv) > 1 else "apply"
OLD, NEW = "ElapsedMilliseconds", "ElapsedMillisecondsOpe"
KEY = os.environ.get("GRAYLOG_API_KEY") or sys.exit("definir GRAYLOG_API_KEY en el entorno")
AUTH = "Basic " + base64.b64encode((KEY + ":token").encode()).decode()

def api(method, path, body=None):
    req = urllib.request.Request(BASE + path, method=method, data=(json.dumps(body).encode() if body is not None else None))
    req.add_header("Authorization", AUTH); req.add_header("Accept", "application/json"); req.add_header("X-Requested-By", "cli")
    if body is not None: req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=90) as r: raw = r.read()
    except urllib.error.HTTPError as e:
        print("HTTP", e.code, method, path, e.read()[:2000].decode(errors="replace"), file=sys.stderr); sys.exit(1)
    return json.loads(raw) if raw else None
def save(n, o): json.dump(o, open(os.path.join(OUT, n), "w"), indent=1)
def load(n): return json.load(open(os.path.join(OUT, n)))
def write(view, search):
    s = copy.deepcopy(search); s.pop("id", None)
    new_sid = api("POST", "/views/search", s)["id"]
    body = copy.deepcopy(view); body["search_id"] = new_sid
    api("PUT", "/views/" + VID, {"entity": body})
    return new_sid

cur = api("GET", "/views/" + VID)
if MODE == "rollback":
    bv, bs = load("salesope-before-view.json"), load("salesope-before-search.json")
    print("rollback: restaura el respaldo (%d widgets; la vista actual tiene %d)" % (sum(len(s["widgets"]) for s in bv["state"].values()), sum(len(s["widgets"]) for s in cur["state"].values())))
    if not APPLY: print("simulacion: no se escribio nada (usar APPLY=1)"); sys.exit(0)
    cur2 = copy.deepcopy(cur); cur2["state"] = bv["state"]
    print("restaurado; search_id nuevo", write(cur2, bs)); sys.exit(0)

search = api("GET", "/views/search/" + cur["search_id"])
if len(cur["state"]) != 1 or sum(len(s["widgets"]) for s in cur["state"].values()) != 24: sys.exit("GUARDA: se esperaban 1 pestana y 24 widgets")
tab = list(cur["state"].keys())[0]; S = cur["state"][tab]
before_view, before_search = copy.deepcopy(cur), copy.deepcopy(search)
ws = [w for w in S["widgets"] if S["titles"]["widget"].get(w["id"]) == "Sales Endpoints"]
if len(ws) != 1: sys.exit("GUARDA: se esperaba 1 widget 'Sales Endpoints', hay %d" % len(ws))
w = ws[0]; st = {st["id"]: st for q in search["queries"] for st in q["search_types"]}[S["widget_mapping"][w["id"]][0]]
want = ["count()", "max(%s)" % OLD, "avg(%s)" % OLD, "percentile(%s,90)" % OLD]
if [s["function"] for s in w["config"]["series"]] != want or [s["id"] for s in st["series"]] != want:
    sys.exit("GUARDA: las series de Sales Endpoints no son las esperadas (ya cambiado?): %s" % [s["function"] for s in w["config"]["series"]])
for s in w["config"]["series"]: s["function"] = s["function"].replace(OLD, NEW)
for s in st["series"]:
    s["id"] = s["id"].replace(OLD, NEW)
    if s.get("field") == OLD: s["field"] = NEW
print("Sales Endpoints series: %s" % ", ".join(s["function"] for s in w["config"]["series"]))
save("salesope-before-view.json", before_view); save("salesope-before-search.json", before_search)
save("salesope-after-view.json", cur); save("salesope-after-search.json", search)
if not APPLY: print("simulacion: no se escribio nada en Graylog (payloads en data/salesope-after-*.json; usar APPLY=1)"); sys.exit(0)
new_sid = write(cur, search)
chk = api("GET", "/views/" + VID); cs = list(chk["state"].values())[0]
cw = [x for x in cs["widgets"] if cs["titles"]["widget"].get(x["id"]) == "Sales Endpoints"][0]
print("aplicado: search_id %s, widgets %d, series de Sales Endpoints: %s" % (new_sid, len(cs["widgets"]), [s["function"] for s in cw["config"]["series"]]))
