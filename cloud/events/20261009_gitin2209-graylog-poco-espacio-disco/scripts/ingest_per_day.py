#!/usr/bin/env python3
"""Local only, reads data/ingest-cat-indices.json (OpenSearch _cat/indices, bytes=b, format=json) and estimates GB per day.
Each index covers the time from its creation to the creation of the next index of the same index set (the active one: until now); its
stored size is spread evenly over that interval. Stored size is the compressed size on disk, not the raw ingest, and an even spread
inside one index is an assumption: treat the result as an estimate."""
import json, re, sys, os, datetime as dt, collections
OUT = "/home/dpaniagua/Documentos/git/bots/cloud/events/20261009_gitin2209-graylog-poco-espacio-disco/data"
rows = json.load(open(os.path.join(OUT, "ingest-cat-indices.json")))
now = dt.datetime.now(dt.timezone.utc)
def parse(s): return dt.datetime.fromisoformat(s.replace("Z", "+00:00"))
sets = collections.defaultdict(list)
for r in rows:
    name = r.get("index", "")
    m = re.match(r"^(.*?)_(\d+)$", name)
    if not m or name.startswith("."): continue
    sets[m.group(1)].append({"index": name, "n": int(m.group(2)), "created": parse(r["creation.date.string"]), "bytes": int(r.get("store.size") or 0), "docs": int(r.get("docs.count") or 0)})
per_index, daily, daily_set = [], collections.defaultdict(float), collections.defaultdict(lambda: collections.defaultdict(float))
for key, lst in sets.items():
    lst.sort(key=lambda x: x["created"])
    for i, ix in enumerate(lst):
        end = lst[i + 1]["created"] if i + 1 < len(lst) else now
        days = max((end - ix["created"]).total_seconds() / 86400, 1e-6)
        gb = ix["bytes"] / 2**30
        per_index.append((key, ix["index"], ix["created"], end, days, gb, gb / days, ix["docs"]))
        t = ix["created"]
        while t < end:
            nxt = min(end, (t + dt.timedelta(days=1)).replace(hour=0, minute=0, second=0, microsecond=0))
            frac = (nxt - t).total_seconds() / (end - ix["created"]).total_seconds()
            daily[t.date()] += gb * frac; daily_set[key][t.date()] += gb * frac
            t = nxt
with open(os.path.join(OUT, "ingest-per-index.tsv"), "w") as f:
    f.write("set\tindex\tcreated_utc\tuntil_utc\tdays\tGB\tGB_per_day\tdocs\n")
    for r in sorted(per_index, key=lambda x: (x[0], x[2])):
        f.write("%s\t%s\t%s\t%s\t%.2f\t%.2f\t%.2f\t%d\n" % (r[0], r[1], r[2].strftime("%Y-%m-%d %H:%M"), r[3].strftime("%Y-%m-%d %H:%M"), r[4], r[5], r[6], r[7]))
top = [k for k, _ in sorted(((k, sum(v.values())) for k, v in daily_set.items()), key=lambda x: -x[1])[:4]]
days_list = sorted(daily)[-14:]
with open(os.path.join(OUT, "ingest-gb-per-day.tsv"), "w") as f:
    f.write("day_utc\ttotal_GB\t" + "\t".join(top) + "\n")
    for d in days_list:
        f.write("%s\t%.1f\t%s\n" % (d, daily[d], "\t".join("%.1f" % daily_set[k].get(d, 0) for k in top)))
print("indices:", len(per_index), "| sets:", len(sets), "| total stored GB: %.1f" % (sum(r[5] for r in per_index)))
print(open(os.path.join(OUT, "ingest-gb-per-day.tsv")).read())
print("(estimate: stored size spread evenly over each index's active period; the last day is partial)")
