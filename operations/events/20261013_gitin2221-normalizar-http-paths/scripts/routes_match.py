#!/usr/bin/env python3
"""Prueba local (sin red): normaliza paths reales con las plantillas de rutas extraidas de los controllers (routes-origin-main.json).
NormalizedPath = segmentos literales de la plantilla (sin parametros) unidos con '_'. Uso: routes_match.py rutas.json paths.txt"""
import json, re, sys
routes = json.load(open(sys.argv[1]))
tpls = sorted({r["template"] for r in routes})
def parse(t):
    segs = t.strip("/").split("/")
    return [(s[1:-1].lstrip("*").split(":")[0], "opt" if s.endswith("?}") else ("rest" if s.startswith("{*") else "one")) if s.startswith("{") else (s, "lit") for s in segs]
P = [(t, parse(t)) for t in tpls]
def match(path):
    parts = [p for p in path.split("?")[0].strip("/").split("/")]
    best = None
    for t, segs in P:
        i, ok = 0, True
        for j, (name, kind) in enumerate(segs):
            if kind == "lit":
                if i >= len(parts) or parts[i].lower() != name.lower(): ok = False; break
                i += 1
            elif kind == "one":
                if i >= len(parts) or parts[i] == "": ok = False; break
                i += 1
            elif kind == "opt":
                if i < len(parts): i += 1
            else: i = len(parts)
        if ok and i == len(parts):
            score = (sum(1 for _, k in segs if k == "lit"), -sum(1 for _, k in segs if k != "lit"))
            if best is None or score > best[0]: best = (score, t)
    return best[1] if best else None
def norm(t): return "_".join(s for s, k in parse(t) if k == "lit")
paths = sorted({l.strip() for l in open(sys.argv[2]) if l.strip().startswith("/")})
un = []
for p in paths:
    t = match(p)
    print("%-62s -> %s" % (p[:62], norm(t) if t else "SIN COINCIDENCIA"))
    if not t: un.append(p)
print("\nrutas distintas: %d | con coincidencia: %d | sin coincidencia: %d" % (len(paths), len(paths) - len(un), len(un)))
