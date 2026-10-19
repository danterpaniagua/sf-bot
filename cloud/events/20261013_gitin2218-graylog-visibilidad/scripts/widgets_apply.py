#!/usr/bin/env python3
"""GITIN-2218 — agrega/ajusta widgets del dashboard Operations (pestana HTTP) de Graylog de SmartCloud.
Modos:  widgets_apply.py apply      construye los 24 widgets (7 existentes ajustados + 17 nuevos), 24 h, y los escribe
        widgets_apply.py rollback   restaura la definicion guardada por C7 (data/c7-view.json, data/c7-search.json)
Por defecto NO escribe en Graylog: arma el payload en data/, corre las guardas y muestra los cambios. Solo con APPLY=1 hace POST/PUT.
OFFLINE=1: usa data/c7-*.json como estado actual, sin red (prueba local del armado; nunca escribe).
Token en $GRAYLOG_API_KEY (nunca literal)."""
import os, sys, json, uuid, copy, time, base64, urllib.request, urllib.error
BASE = "https://sfcloud-monitoreo.smartfran.com/graylog/api"
OUT = "/home/dpaniagua/Documentos/git/bots/cloud/events/20261013_gitin2218-graylog-visibilidad/data"
VID = "6ace703e41759be0a237ff89"
MODE = sys.argv[1] if len(sys.argv) > 1 else ""
OFFLINE = os.environ.get("OFFLINE") == "1"
APPLY = os.environ.get("APPLY") == "1" and not OFFLINE
TR = {"from": 86400, "type": "relative"}          # 24 h para todos
if MODE not in ("apply", "rollback"):
    sys.exit("uso: widgets_apply.py apply|rollback")
if not OFFLINE:
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

def load(name): return json.load(open(os.path.join(OUT, name)))
def save(name, obj): json.dump(obj, open(os.path.join(OUT, name), "w"), indent=1)

backup_view, backup_search = load("c7-view.json"), load("c7-search.json")
cur_view = backup_view if OFFLINE else api("GET", "/views/" + VID)
tab = list(backup_view["state"].keys())[0]
cur_ids = {w["id"] for s in cur_view["state"].values() for w in s["widgets"]}
bak_ids = {w["id"] for s in backup_view["state"].values() for w in s["widgets"]}

def post_search(search):
    s = copy.deepcopy(search); s.pop("id", None)
    return api("POST", "/views/search", s)["id"]

def put_view(base_view, state, search_id):
    body = copy.deepcopy(base_view); body["state"] = state; body["search_id"] = search_id
    # Graylog 7.1: el 400 "entity cannot be null" (CreateEntityRequest) indica que espera {"entity": <vista>}; no confirmado hasta ver el resultado
    return api("PUT", "/views/" + VID, {"entity": body})

# ---------------------------------------------------------------- rollback
if MODE == "rollback":
    print("rollback: restaura %d widgets de data/c7-view.json (la vista actual tiene %d)" % (len(bak_ids), len(cur_ids)))
    if not APPLY:
        print("simulacion: no se escribio nada (usar APPLY=1)"); sys.exit(0)
    new_sid = post_search(backup_search)
    put_view(cur_view, backup_view["state"], new_sid)
    print("restaurado; search_id nuevo", new_sid); sys.exit(0)

# ---------------------------------------------------------------- apply: especificacion de los 24 widgets
SVC = [  # clave, prefijo de titulo, filtro Service, stream, titulo esperado del stream
 ("Sales",    "Sales",    "Sales",                          "6a47c5c94b3c88a95fad7a7a", "PROD-Sales-AppServicePlan"),
 ("Business", "Business", '"SmartFran.Cloud.Business.API"', "6a452a0d18ebc987b1ca003a", "PROD-Business-AppServicePlan"),
 ("Catalog",  "Catalog",  '"SmartFran.Cloud.Catalog.API"',  "6a7cb1924814bcaed30a87aa", "PROD-Catalog-AppServicePlan"),
 ("Orders",   "Orders",   '"SmartFran.Cloud.Orders.API"',   "6a7cb1944814bcaed30a87bf", "PROD-Orders-AppServicePlan"),
 ("Person",   "Person",   '"SmartFran.Cloud.Person.API"',   "6a7cb18d4814bcaed30a8774", "PROD-Person-AppServicePlan"),
 ("Platform", "Platform", '"SmartFran.Cloud.Platform.API"', "6a7cb18a4814bcaed30a875a", "PROD-Platform-AppServicePlan"),
 ("Client",   "Client",   '"SmartFran.Cloud.Client.Web"',   "6a7cb18f4814bcaed30a8791", "PROD-Admin-AppServicePlan"),
 ("POS WASM", "POS WASM", '"smartfran-pos-wasm"',           "6aa981d5961fa056c1730210", "PROD-PosWasmRelay-FunctionApp"),
]
TAIL = 'NOT Method: ("OPTIONS") AND Service:%s'
QS = {"method":   '_exists_:Method AND ' + TAIL,
      "status":   '_exists_:("Method" AND "StatusCode") AND ' + TAIL,
      "endpoint": '_exists_:("Method" AND "Path") AND ' + TAIL}
SUFFIX = {"method": "Method", "status": "(Status Code)", "endpoint": "Endpoints"}
titles_cur = {t: wid for wid, t in backup_view["state"][tab]["titles"]["widget"].items()}
w_by_id = {w["id"]: w for w in backup_view["state"][tab]["widgets"]}
tmpl_cfg = copy.deepcopy(w_by_id[titles_cur["Sales Method"]]["config"])

def cfg_line(col):
    c = copy.deepcopy(tmpl_cfg); c["column_pivots"][0]["fields"] = [col]; return c
def cfg_table():
    return {"row_pivots": [{"fields": ["Path"], "type": "values", "config": {"limit": 20, "skip_empty_values": True}}], "units": {},
            "column_pivots": [], "series": [{"config": {"name": None, "thresholds": []}, "function": "count()"}],
            "sort": [{"type": "series", "field": "count()", "direction": "Descending"}], "visualization": "table",
            "visualization_config": None, "formatting_settings": None, "rollup": True, "event_annotation": False,
            "column_limit": None, "row_limit": None}
def groups(pivots):
    out = []
    for p in pivots:
        g = {"type": p["type"], "fields": p["fields"]}
        if p["type"] == "time": g["interval"] = p["config"]["interval"]
        else: g.update({"limit": p["config"]["limit"], "skip_empty_values": p["config"].get("skip_empty_values", False)})
        out.append(g)
    return out
def search_type(w, st_id):
    c = w["config"]
    def ser(s):
        fn = s["function"]; inner = fn[fn.index("(") + 1:-1]
        return {"type": "count", "id": fn, "field": inner or None}
    return {"timerange": w["timerange"], "query": w["query"], "streams": w["streams"], "stream_categories": [], "id": st_id,
            "name": "chart", "series": [ser(s) for s in c["series"]], "sort": c["sort"], "rollup": c["rollup"], "type": "pivot",
            "row_groups": groups(c["row_pivots"]), "column_groups": groups(c["column_pivots"]), "filter": None, "filters": []}

# validar el conversor contra los search_types existentes (sin cambiar nada): debe reproducirlos
bst = {st["id"]: st for q in backup_search["queries"] for st in q["search_types"]}
bad = [t for wid, t in backup_view["state"][tab]["titles"]["widget"].items()
       if search_type(w_by_id[wid], backup_view["state"][tab]["widget_mapping"][wid][0]) != bst[backup_view["state"][tab]["widget_mapping"][wid][0]]]
print("conversor widget->search_type contra los 7 existentes: %s" % ("IGUAL en todos" if not bad else "DIFIERE en: %s" % bad))

state = copy.deepcopy(backup_view["state"]); S = state[tab]
widgets, positions, mapping, titles, stypes, changes = [], {}, {}, {}, [], []
for row, (key, pre, flt, sid, _) in enumerate(SVC):
    for col, kind in zip((1, 5, 9), ("method", "status", "endpoint")):
        title = "%s %s" % (pre, SUFFIX[kind])
        old_id = titles_cur.get(title)
        wid = old_id or str(uuid.uuid4()); stid = (backup_view["state"][tab]["widget_mapping"][old_id][0] if old_id else str(uuid.uuid4()))
        w = {"id": wid, "type": "aggregation", "filter": None, "filters": [], "timerange": TR,
             "query": {"type": "elasticsearch", "query_string": QS[kind] % flt}, "streams": [sid], "stream_categories": [],
             "config": cfg_table() if kind == "endpoint" else cfg_line("Method" if kind == "method" else "StatusCode"),
             "description": None, "context": None}
        if old_id:  # existente: conserva configuracion y posicion; solo cambian rango y, en Status Code, la consulta
            w["config"] = w_by_id[old_id]["config"]; positions[wid] = S["positions"][old_id]
            changes.append("AJUSTA %-24s rango 24 h%s" % (title, "; consulta nueva" if w_by_id[old_id]["query"] != w["query"] else ""))
        else:
            positions[wid] = {"col": col, "row": 1 + 4 * row, "height": 4, "width": 4}
            changes.append("NUEVO  %-24s stream %s, col %d fila %d" % (title, sid, col, 1 + 4 * row))
        widgets.append(w); mapping[wid] = [stid]; titles[wid] = title; stypes.append(search_type(w, stid))
S["widgets"], S["positions"], S["widget_mapping"] = widgets, positions, mapping
S["titles"]["widget"] = titles
new_search = copy.deepcopy(backup_search); new_search["queries"][0]["search_types"] = stypes
print("\n".join(changes)); print("total widgets: %d (existentes %d, nuevos %d)" % (len(widgets), len(bak_ids), len(widgets) - len(bak_ids)))
save("apply-state.json", state); save("apply-search.json", new_search)

# guardas
if cur_ids != bak_ids or cur_view.get("search_id") != backup_view.get("search_id") and not OFFLINE:
    print("GUARDA: el dashboard cambio desde C7 (widgets o search_id); correr C7 de nuevo antes de aplicar"); sys.exit(1)
if not OFFLINE:
    streams = {s["id"]: s["title"] for s in api("GET", "/streams")["streams"]}
    for key, _, _, sid, exp in SVC:
        if streams.get(sid) != exp: print("GUARDA: stream %s es %r, se esperaba %r" % (sid, streams.get(sid), exp)); sys.exit(1)
    print("streams: los 8 ids existen con el titulo esperado")
    now = time.time(); iso = lambda t: time.strftime("%Y-%m-%dT%H:%M:%S.000Z", time.gmtime(t))
    qs = [{"id": key, "query": {"type": "elasticsearch", "query_string": QS["method"] % flt}, "filter": {"type": "stream", "id": sid},
           "timerange": {"type": "absolute", "from": iso(now - 3600), "to": iso(now)}, "search_types": [{"id": "m", "type": "messages", "limit": 1, "offset": 0}]}
          for key, _, flt, sid, _ in SVC]
    sid_ = api("POST", "/views/search", {"queries": qs})["id"]; job = api("POST", "/views/search/%s/execute" % sid_, {})["id"]
    for _ in range(40):
        st = api("GET", "/views/search/status/" + job)
        if st["execution"].get("done"): break
        time.sleep(3)
    save("apply-stream-check.json", st)
    empty = []
    for key, *_ in SVC:
        n = st["results"][key]["search_types"]["m"]["total_results"] if st["results"][key]["state"] == "COMPLETED" else None
        print("  stream %-9s ultima hora: %s mensajes con Method" % (key, n)); 
        if not n: empty.append(key)
    if empty and APPLY: print("GUARDA: sin mensajes en el stream para", empty); sys.exit(1)
if not APPLY:
    print("simulacion: no se escribio nada en Graylog (payloads en data/apply-state.json y data/apply-search.json; usar APPLY=1 para aplicar)"); sys.exit(0)
new_sid = post_search(new_search)
put_view(cur_view, state, new_sid)
chk = api("GET", "/views/" + VID)
print("aplicado: search_id %s, widgets ahora %d" % (new_sid, sum(len(s["widgets"]) for s in chk["state"].values())))
