#!/usr/bin/env python3
"""Extrae las rutas completas de los *Controller.cs de SmartFran.Cloud (origin/main) y las normaliza. Solo lectura."""
import re, subprocess, sys, json
REPO = "/home/dpaniagua/Documentos/git/bots/cloud/repo/SmartFran.Cloud"
REF = "origin/main"
def git(*a): return subprocess.run(["git", "-C", REPO, *a], capture_output=True, text=True, check=True).stdout
files = [f for f in git("ls-tree", "-r", "--name-only", REF).splitlines() if f.endswith("Controller.cs")]
ATTR = re.compile(r'\[\s*(Route|Http(?:Get|Post|Put|Patch|Delete))\s*(?:\(\s*"([^"]*)"[^)]*\))?\s*\]')
rows = []
for f in files:
    src = git("show", f"{REF}:{f}")
    m = re.search(r'class\s+(\w+)Controller\b', src)
    if not m: continue
    ctrl = m.group(1)
    head, body = src[:m.start()], src[m.start():]
    cls_routes = [t for k, t in ATTR.findall(head) if k == "Route" and t]
    cls_route = cls_routes[-1] if cls_routes else ""
    # metodos: atributos acumulados hasta la firma "public ... Name("
    pending = []
    for line in body.splitlines():
        for k, t in ATTR.findall(line): pending.append((k, t))
        sm = re.search(r'\bpublic\s+(?:async\s+)?[\w<>\[\],\.\? ]+?\s+(\w+)\s*\(', line)
        if sm and pending:
            action = sm.group(1)
            verbs = [(k, t) for k, t in pending if k.startswith("Http")]
            routes = [t for k, t in pending if k == "Route" and t]
            for k, t in (verbs or []):
                tpl = t or (routes[0] if routes else "")
                full = (cls_route.rstrip("/") + "/" + tpl.lstrip("/")) if tpl and not tpl.startswith("~") else (tpl.lstrip("~/") if tpl else cls_route)
                if tpl == "" and not routes: full = cls_route
                full = full.replace("[controller]", ctrl).replace("[action]", action)
                rows.append({"file": f, "controller": ctrl, "verb": k[4:].upper(), "action": action, "template": full.strip("/")})
            pending = []
        elif sm: pending = []
json.dump(rows, open(sys.argv[1], "w"), indent=1)
withp = [r for r in rows if "{" in r["template"]]
print("controllers (archivos):", len(files), "| rutas extraidas:", len(rows), "| con parametros en la ruta:", len(withp))
no_action_tpl = [r for r in rows if r["template"].count("/") <= 2]
print("plantillas distintas:", len({r["template"] for r in rows}))
