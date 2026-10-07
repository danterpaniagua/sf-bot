"""
GITIN-1874 - Validate whether extradata.chain exists at all (vs. exists but never
equals "Grido") in -3 files from before the 2026-08-17 cutoff found during the
DAYSBEFORE=124 backfill (see investigation.md, H8). Distinguishes "the chain field
itself didn't exist yet" from "no Grido orders happened to occur in this period"
as the actual root cause - the backfill logs alone (0/N Grido matches) can't tell
these apart.

Usage: python3 scripts_chain_field_check.py <local -3 file>
"""
import json
import sys
from collections import Counter

path = sys.argv[1]
total = 0
has_extradata = 0
has_chain_key = 0
chain_values = Counter()

with open(path) as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        total += 1
        record = json.loads(line)
        extradata = record.get("extradata")
        if extradata is not None:
            has_extradata += 1
            if "chain" in extradata:
                has_chain_key += 1
                chain_values[extradata.get("chain")] += 1

print(f"file: {path}")
print(f"total records: {total}")
print(f"records with extradata key: {has_extradata}")
print(f"records with extradata.chain key: {has_chain_key}")
print(f"chain value distribution: {dict(chain_values.most_common(20))}")
print()
