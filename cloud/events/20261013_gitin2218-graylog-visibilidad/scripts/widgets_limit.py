#!/usr/bin/env python3
"""GITIN-2218 — fija el limite de filas (top N) de los 8 widgets "<Servicio> Endpoints" del dashboard Operations.
Uso:  widgets_limit.py [N]   (N=10 por defecto). Sin APPLY=1 solo arma el payload y muestra los cambios (no escribe en Graylog).
Guarda el estado previo en data/limit-before-view.json y data/limit-before-search.json (respaldo). Token en $GRAYLOG_API_KEY."""
import os, sys, json, copy, base64, urllib.request, urllib.error
BASE = "https://sfcloud-monitoreo.smartfran.com/graylog/api"
OUT = "/home/dpaniagua/Documentos/git/bots/cloud/events/20261013_gitin2218-graylog-visibilidad/data"
VID = "6ace703e41759be0a237ff89"
N = int(sys.argv[1]) if len(sys.argv) > 1 else 10
APPLY = os.environ.get("APPLY") == "1"
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

view = api("GET", "/views/" + VID); search = api("GET", "/views/search/" + view["search_id"])
save("limit-before-view.json", view); save("limit-before-search.json", search)
tab = list(view["state"].keys())[0]; S = view["state"][tab]
if len(view["state"]) != 1 or len(S["widgets"]) != 24: sys.exit("GUARDA: se esperaban 1 pestana y 24 widgets, hay %d pestanas y %d widgets" % (len(view["state"]), len(S["widgets"])))
ep = [w for w in S["widgets"] if S["titles"]["widget"].get(w["id"], "").endswith(" Endpoints")]
if len(ep) != 8: sys.exit("GUARDA: se esperaban 8 widgets Endpoints, hay %d" % len(ep))
st_by_id = {st["id"]: st for q in search["queries"] for st in q["search_types"]}
for w in ep:
    st = st_by_id[S["widget_mapping"][w["id"]][0]]
    rp, rg = w["config"]["row_pivots"][0], st["row_groups"][0]
    if rp["fields"] != ["Path"] or rg["fields"] != ["Path"]: sys.exit("GUARDA: %s no agrupa por Path" % S["titles"]["widget"][w["id"]])
    print("%-24s limite %s -> %d (widget) | %s -> %d (search)" % (S["titles"]["widget"][w["id"]], rp["config"]["limit"], N, rg["limit"], N))
    rp["config"]["limit"] = N; rg["limit"] = N
save("limit-after-view.json", view); save("limit-after-search.json", search)
if not APPLY: print("simulacion: no se escribio nada en Graylog (usar APPLY=1)"); sys.exit(0)
s = copy.deepcopy(search); s.pop("id", None)
new_sid = api("POST", "/views/search", s)["id"]
body = copy.deepcopy(view); body["search_id"] = new_sid
api("PUT", "/views/" + VID, {"entity": body})
chk = api("GET", "/views/" + VID)
lims = [w["config"]["row_pivots"][0]["config"]["limit"] for st in chk["state"].values() for w in st["widgets"] if st["titles"]["widget"].get(w["id"], "").endswith(" Endpoints")]
print("aplicado: search_id %s, widgets %d, limites de Endpoints: %s" % (new_sid, sum(len(st["widgets"]) for st in chk["state"].values()), lims))
