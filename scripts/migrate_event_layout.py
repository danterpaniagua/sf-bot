#!/usr/bin/env python3
"""Migra las carpetas events/ de los 4 proyectos al layout de eventos (CLAUDE.md raiz -> "Event folder layout"):
   raiz = investigation.md, ops.md, ops-events.md y emails/tickets (*_jira.md, *_pm.md, *_it.md, email*.md);
   scripts/ = scripts y archivos que ellos leen; data/ = salida cruda y evidencia; outputs/ = reportes generados (html/svg).
Uso:  migrate_event_layout.py                 simulacion: NO mueve nada; escribe el manifiesto y lista lo que queda para revision
      APPLY=1 migrate_event_layout.py         aplica los movimientos y la reescritura de referencias; guarda el manifiesto de deshacer
      APPLY=1 migrate_event_layout.py undo    revierte todo lo que registro el manifiesto de deshacer
      ONLY=cloud (o loyalty, smartpedidos, operations)   limita a un proyecto
Reglas (archivos en la raiz de cada evento):
   se quedan:     investigation/ops/ops-events .md (tambien con prefijo largo), email*.md, *_jira.md, *_pm.md, *_it.md
   -> scripts/:   .sh .ps1 .py .sql .js .rb .patch .conf .ashx; los .sh/.py/.ps1/.js que usan rutas relativas (data/..., dirname, $0, __file__)
                  NO se mueven (quedan en revision: al bajar un nivel dejarian de encontrar sus archivos)
   -> data/:      .json .jsonl .csv .tsv .txt .tbl .table .xml .zip .cer .jpg .jpeg .png .log .xlsx .pdf
   -> outputs/:   .html .htm .svg
   revision:      todo lo demas (otros .md, extensiones desconocidas, carpetas distintas de data/scripts/outputs); no se toca
Despues de mover, en los archivos de texto del mismo evento se reescribe la ruta absoluta o relativa al repo
   "<evento>/<archivo>" -> "<evento>/<carpeta>/<archivo>". Los nombres sueltos entre comillas invertidas no se tocan.
Nunca sobrescribe: si el destino existe, el archivo queda en revision."""
import os, re, sys, json, shutil, glob
ROOT = "/home/dpaniagua/Documentos/git/bots"
OUTD = os.path.join(ROOT, "scripts")
PROJECTS = [os.environ["ONLY"]] if os.environ.get("ONLY") else ["loyalty", "smartpedidos", "operations", "cloud"]
APPLY = os.environ.get("APPLY") == "1"
MODE = sys.argv[1] if len(sys.argv) > 1 else "apply"
MAN_PLAN = os.path.join(OUTD, "migrate-layout-plan.tsv")
MAN_UNDO = os.path.join(OUTD, "migrate-layout-undo.json")

KEEP = re.compile(r"(^|_)(investigation|ops|ops-events)\.md$|(^|_)email[_a-z0-9-]*\.md$|_(jira|pm|it)\.md$", re.I)
SCRIPTS = {".sh", ".ps1", ".py", ".sql", ".js", ".rb", ".patch", ".conf", ".ashx"}
DATA = {".json", ".jsonl", ".csv", ".tsv", ".txt", ".tbl", ".table", ".xml", ".zip", ".cer", ".jpg", ".jpeg", ".png", ".log", ".xlsx", ".pdf"}
OUTPUTS = {".html", ".htm", ".svg"}
RELATIVE = re.compile(r"(?<![/\w.~$\"'-])(\./)?data/|\$\{?0\}?|__file__|BASH_SOURCE|dirname|Split-Path|\$PSScriptRoot")
TEXT = {".md", ".sh", ".py", ".ps1", ".js", ".sql", ".txt", ".patch", ".conf", ".rb"}

def classify(path, name):
    ext = os.path.splitext(name)[1].lower()
    if KEEP.search(name): return None, "se queda en la raiz"
    if ext in SCRIPTS:
        if ext in {".sh", ".py", ".ps1", ".js"}:
            try:
                if RELATIVE.search(open(path, errors="ignore").read()): return "review", "script con rutas relativas (data/, dirname, $0, __file__)"
            except OSError: return "review", "no se pudo leer"
        return "scripts", "script"
    if ext in DATA: return "data", "dato / evidencia"
    if ext in OUTPUTS: return "outputs", "reporte generado"
    return "review", "extension o nombre sin regla" if ext else "sin extension"

def plan():
    rows = []
    for p in PROJECTS:
        for ev in sorted(glob.glob(os.path.join(ROOT, p, "events", "*", ""))):
            ev = ev.rstrip("/"); evn = os.path.basename(ev)
            for name in sorted(os.listdir(ev)):
                path = os.path.join(ev, name)
                if os.path.isdir(path):
                    if name in ("data", "scripts", "outputs"): continue
                    if name == "__pycache__": rows.append((p, evn, name, "scripts", "carpeta de cache de Python")); continue
                    rows.append((p, evn, name, "review", "carpeta distinta de data/scripts/outputs")); continue
                dest, why = classify(path, name)
                if dest is None: continue
                if dest != "review" and os.path.exists(os.path.join(ev, dest, name)): dest, why = "review", "el destino ya existe"
                rows.append((p, evn, name, dest, why))
    return rows

def undo():
    if not os.path.exists(MAN_UNDO): sys.exit("no hay manifiesto de deshacer: " + MAN_UNDO)
    u = json.load(open(MAN_UNDO))
    print("deshacer: %d movimientos, %d reescrituras" % (len(u["moves"]), len(u["rewrites"])))
    if not APPLY: print("simulacion: no se revirtio nada (usar APPLY=1)"); return
    for f, old, new in reversed(u["rewrites"]):
        s = open(f, errors="surrogateescape").read(); open(f, "w", errors="surrogateescape").write(s.replace(new, old))
    for src, dst in reversed(u["moves"]):
        if os.path.exists(dst) and not os.path.exists(src): shutil.move(dst, src)
    print("revertido")

def rewrite_refs(ev, moved, rewrites):
    rel = os.path.relpath(ev, ROOT)
    for dirpath, _, files in os.walk(ev):
        if "/data" in dirpath.replace(ev, "", 1): continue
        for fn in files:
            fp = os.path.join(dirpath, fn)
            if os.path.splitext(fn)[1].lower() not in TEXT or fp.endswith((".json",)): continue
            try: s = open(fp, errors="surrogateescape").read()
            except OSError: continue
            t = s
            for name, dest in moved:
                for base in (ev, rel):
                    old = "%s/%s" % (base, name); new = "%s/%s/%s" % (base, dest, name)
                    t2 = re.sub(r"(?<![\w.])" + re.escape(old) + r"(?=[^\w.-]|$|\.(?!\w))", new, t)
                    if t2 != t: rewrites.append((fp, old, new)); t = t2
            if t != s: open(fp, "w", errors="surrogateescape").write(t)

def main():
    if MODE == "undo": return undo()
    rows = plan(); os.makedirs(OUTD, exist_ok=True)
    with open(MAN_PLAN, "w") as f:
        f.write("project\tevent\tfile\taction\treason\n")
        for r in rows: f.write("\t".join(r) + "\n")
    cnt = {}
    for r in rows: cnt[r[3]] = cnt.get(r[3], 0) + 1
    print("eventos revisados: %d | movimientos propuestos: scripts=%d data=%d outputs=%d | en revision (no se tocan): %d" % (
        len({(r[0], r[1]) for r in rows}), cnt.get("scripts", 0), cnt.get("data", 0), cnt.get("outputs", 0), cnt.get("review", 0)))
    print("manifiesto:", MAN_PLAN)
    rv = {}
    for r in rows:
        if r[3] == "review": rv[r[4]] = rv.get(r[4], 0) + 1
    for k, v in sorted(rv.items(), key=lambda x: -x[1]): print("  revision: %4d  %s" % (v, k))
    if not APPLY: print("simulacion: no se movio nada (usar APPLY=1)"); return
    undo_log = {"moves": [], "rewrites": []}
    by_event = {}
    for p, evn, name, dest, why in rows:
        if dest == "review": continue
        ev = os.path.join(ROOT, p, "events", evn)
        os.makedirs(os.path.join(ev, dest), exist_ok=True)
        src, dst = os.path.join(ev, name), os.path.join(ev, dest, name)
        shutil.move(src, dst); undo_log["moves"].append((src, dst)); by_event.setdefault(ev, []).append((name, dest))
    for ev, moved in by_event.items(): rewrite_refs(ev, moved, undo_log["rewrites"])
    json.dump(undo_log, open(MAN_UNDO, "w"), indent=1)
    print("aplicado: %d movimientos, %d reescrituras; deshacer: APPLY=1 migrate_event_layout.py undo" % (len(undo_log["moves"]), len(undo_log["rewrites"])))

main()
