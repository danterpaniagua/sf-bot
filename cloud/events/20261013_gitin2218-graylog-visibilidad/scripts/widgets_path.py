#!/usr/bin/env python3
"""GITIN-2218 / GITIN-2221 — pasa los 8 widgets "<Servicio> Endpoints" del dashboard Operations de Path a NormalizedPath, top 10.
Reemplaza a widgets_limit.py (que solo cambiaba el limite y no se llego a correr).
Uso:  widgets_path.py            simulacion: lee el dashboard, arma el payload en data/, muestra los cambios; NO escribe en Graylog
      APPLY=1 widgets_path.py    aplica: guarda una busqueda nueva y reemplaza la definicion (PUT /views/{id} con {"entity": ...})
      APPLY=1 widgets_path.py rollback   restaura data/path-before-view.json y path-before-search.json (el estado previo guardado en la simulacion/aplicacion)
Cambia en cada Endpoints: columna de filas Path -> NormalizedPath (widget y search type), limite 20 -> 10 y la consulta
_exists_:("Method" AND "Path") -> _exists_:("Method" AND "NormalizedPath"). Token en $GRAYLOG_API_KEY (nunca literal)."""
import os, sys, json, copy, base64, urllib.request, urllib.error
BASE = "https://sfcloud-monitoreo.smartfran.com/graylog/api"
OUT = "/home/dpaniagua/Documentos/git/bots/cloud/events/20261013_gitin2218-graylog-visibilidad/data"
VID = "6ace703e41759be0a237ff89"
APPLY = os.environ.get("APPLY") == "1"
MODE = sys.argv[1] if len(sys.argv) > 1 else "apply"
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
    bv, bs = load("path-before-view.json"), load("path-before-search.json")
    print("rollback: restaura %d widgets del respaldo (la vista actual tiene %d)" % (sum(len(s["widgets"]) for s in bv["state"].values()), sum(len(s["widgets"]) for s in cur["state"].values())))
    if not APPLY: print("simulacion: no se escribio nada (usar APPLY=1)"); sys.exit(0)
    cur2 = copy.deepcopy(cur); cur2["state"] = bv["state"]
    print("restaurado; search_id nuevo", write(cur2, bs)); sys.exit(0)

search = api("GET", "/views/search/" + cur["search_id"])
if len(cur["state"]) != 1 or sum(len(s["widgets"]) for s in cur["state"].values()) != 24: sys.exit("GUARDA: se esperaban 1 pestana y 24 widgets")
tab = list(cur["state"].keys())[0]; S = cur["state"][tab]
before_view, before_search = copy.deepcopy(cur), copy.deepcopy(search)   # copia previa a cualquier cambio; se guarda solo si pasan todas las guardas
ep = [w for w in S["widgets"] if S["titles"]["widget"].get(w["id"], "").endswith(" Endpoints")]
if len(ep) != 8: sys.exit("GUARDA: se esperaban 8 widgets Endpoints, hay %d" % len(ep))
st_by_id = {st["id"]: st for q in search["queries"] for st in q["search_types"]}
for w in ep:
    title = S["titles"]["widget"][w["id"]]; st = st_by_id[S["widget_mapping"][w["id"]][0]]
    rp, rg = w["config"]["row_pivots"][0], st["row_groups"][0]
    if rp["fields"] != ["Path"] or rg["fields"] != ["Path"]: sys.exit("GUARDA: %s no agrupa por Path (ya cambiado?)" % title)
    q0 = w["query"]["query_string"]
    if '_exists_:("Method" AND "Path")' not in q0: sys.exit("GUARDA: %s tiene una consulta inesperada: %s" % (title, q0))
    q1 = q0.replace('_exists_:("Method" AND "Path")', '_exists_:("Method" AND "NormalizedPath")')
    print("%-22s Path -> NormalizedPath, limite %s -> 10" % (title, rp["config"]["limit"]))
    rp["fields"] = ["NormalizedPath"]; rg["fields"] = ["NormalizedPath"]
    rp["config"]["limit"] = 10; rg["limit"] = 10
    w["query"]["query_string"] = q1; st["query"]["query_string"] = q1
save("path-before-view.json", before_view); save("path-before-search.json", before_search)   # respaldo del estado con Path
save("path-after-view.json", cur); save("path-after-search.json", search)
if not APPLY: print("simulacion: no se escribio nada en Graylog (payloads en data/path-after-*.json; usar APPLY=1)"); sys.exit(0)
new_sid = write(cur, search)
chk = api("GET", "/views/" + VID); cs = list(chk["state"].values())[0]
fields = sorted({w["config"]["row_pivots"][0]["fields"][0] for w in cs["widgets"] if cs["titles"]["widget"].get(w["id"], "").endswith(" Endpoints")})
print("aplicado: search_id %s, widgets %d, campo de las tablas Endpoints: %s" % (new_sid, len(cs["widgets"]), fields))
