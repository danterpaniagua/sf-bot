#!/usr/bin/env python3
"""Converts the roadmap table of outputs/tabla-roadmap.md into a CSV the PM can filter.

Differences with the markdown table, on purpose:
  - the column "Prioridad OPE (criticidad / esfuerzo)" is split into "Criticidad" and "Esfuerzo" so each can be filtered; the original text is kept as "Prioridad OPE";
  - markdown links [GITIN-1234](url) become "GITIN-1234 (url)";
  - the estimate column header carries the unit.
Usage: tabla-a-csv.py <tabla-roadmap.md> <output.csv>
"""
import csv
import re
import sys

src, dst = sys.argv[1], sys.argv[2]
link = re.compile(r"\[([^\]]+)\]\(([^)]+)\)")


def plain(text):
    return link.sub(lambda m: f"{m.group(1)} ({m.group(2)})", text).strip()


rows = []
for line in open(src, encoding="utf-8"):
    if not line.startswith("|"):
        continue
    cells = [c.strip() for c in line.strip().strip("|").split(" | ")]
    rows.append(cells)

header, body = rows[0], [r for r in rows[2:] if re.fullmatch(r"\d+(\.[a-z])?", r[0])]
assert len(header) == 9, header
assert all(len(r) == 9 for r in body), [len(r) for r in body]

out_header = header[:7] + ["Prioridad OPE", "Criticidad", "Esfuerzo", "Estimación (días de trabajo de una persona de SRE, no fechas de entrega)"]
with open(dst, "w", encoding="utf-8-sig", newline="") as f:
    w = csv.writer(f, quoting=csv.QUOTE_MINIMAL)
    w.writerow(out_header)
    for r in body:
        prio = r[7]
        crit, esf = [p.strip() for p in prio.split(" / ")]
        w.writerow([plain(c) for c in r[:7]] + [prio, crit, esf, plain(r[8])])
print(f"{len(body)} rows written to {dst}")
