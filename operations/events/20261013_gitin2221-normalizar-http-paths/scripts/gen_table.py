#!/usr/bin/env python3
"""Genera la tabla de rutas para el filtro NormalizedPath de Logstash a partir de las rutas extraidas de los controllers. Sin red."""
import json, sys
src, dst = sys.argv[1], sys.argv[2]
rows = json.load(open(src))
def lits(t): return [s for s in t.strip("/").split("/") if s and not s.startswith("{")]
seen, routes = set(), []
for r in rows:
    t = r["template"].strip("/")
    if t in seen: continue
    seen.add(t); routes.append({"t": t, "n": "_".join(lits(t)) or "root"})
# rutas que no son de controllers (se agregan a mano o desde el codigo del front-end, ver investigation.md):
#  - paginas Blazor/Razor: directivas @page de *.razor/*.cshtml (data/razor-pages.txt, extraidas de origin/main)
#  - hubs de SignalR (MapHub en los Program.cs de Orders y Sales) y rutas de framework
#  - archivos estaticos: por extension (static_suffixes), solo si ninguna plantilla coincide
pages = [l.strip().strip("/") for l in open(sys.argv[3]) if l.strip()] if len(sys.argv) > 3 else []
hubs = ["notificationsCloud", "notifications", "kdsordershub", "hubs/saleorder", "hubs/cash-alerts", "hubs/walletnotifications"]
extras = [("", "root"), ("_blazor/{*rest}", "_blazor"), ("health", "health"), ("_content/{*rest}", "static"), ("_framework/{*rest}", "static")]
extras += [(h + "/{*rest}", "_".join(h.split("/"))) for h in hubs]
extras += [(p, "_".join(x for x in p.split("/") if x and not x.startswith("{")) or "root") for p in pages]
n_extras = 0
for t, n in extras:
    if t not in seen:
        routes.append({"t": t, "n": n, "extra": True}); seen.add(t); n_extras += 1
suffixes = [".css", ".js", ".json", ".map", ".png", ".jpg", ".jpeg", ".gif", ".svg", ".ico", ".webmanifest", ".woff", ".woff2", ".ttf", ".wasm", ".dll", ".pdf"]
json.dump({"source": "SmartFran.Cloud origin/main f88d6d743 (2026-10-07) controllers + %d extras (hubs, framework, Razor pages)" % n_extras,
           "static_suffixes": suffixes, "routes": routes}, open(dst, "w"), indent=0)
print("plantillas: %d (controllers %d + extras %d) | valores distintos de NormalizedPath: %d" % (len(routes), len(routes) - n_extras, n_extras, len({r["n"] for r in routes})))
