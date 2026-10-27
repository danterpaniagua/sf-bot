#!/usr/bin/env python3
"""Read-only jitter / loss probe (GITIN-2288). Appends one CSV row per target.

Usage:
  jitter-probe.py <label> <csv-file> [--count N] [--interval S] [--https] [target ...]

  label     where the probe runs, e.g. wired-vm, wifi-probe (goes into every row)
  csv-file  file the rows are appended to (header written when the file is empty)
  target    hosts to ping; default: the default gateway and 1.1.1.1
  --https   also times 10 empty HTTPS requests to speed.cloudflare.com (curl)

Jitter = mean absolute difference between consecutive round-trip times (RFC 3550 style,
simple average). Sends ICMP pings and, with --https, small HTTPS requests; changes nothing.
Standard library only; needs `ping` and, for --https, `curl`.
"""
import re
import subprocess
import sys
import time
from datetime import datetime, timezone

HEADER = "timestamp,label,target,sent,received,loss_pct,min_ms,avg_ms,p95_ms,max_ms,jitter_ms"


def stats(samples, sent):
    n = len(samples)
    received = n
    loss = 100.0 * (sent - received) / sent if sent else 100.0
    if n == 0:
        return sent, received, loss, None, None, None, None, None
    s = sorted(samples)
    p95 = s[min(n - 1, int(0.95 * n))]
    jit = (sum(abs(samples[i] - samples[i - 1]) for i in range(1, n)) / (n - 1)) if n > 1 else 0.0
    return sent, received, loss, s[0], sum(samples) / n, p95, s[-1], jit


def ping(target, count, interval):
    cmd = ["ping", "-n", "-c", str(count), "-i", str(interval), "-W", "1", target]
    out = subprocess.run(cmd, capture_output=True, text=True, timeout=count * (interval + 1) + 10).stdout
    times = [float(m) for m in re.findall(r"time[=<]([0-9.]+)\s*ms", out)]
    return stats(times, count)


def https(count):
    times = []
    for _ in range(count):
        r = subprocess.run(["curl", "-s", "-o", "/dev/null", "--max-time", "10", "-w", "%{time_total}",
                            "https://speed.cloudflare.com/__down?bytes=0"], capture_output=True, text=True)
        try:
            times.append(float(r.stdout) * 1000.0)
        except ValueError:
            pass
        time.sleep(1)
    return stats(times, count)


def default_gateway():
    out = subprocess.run(["ip", "route", "show", "default"], capture_output=True, text=True).stdout
    m = re.search(r"default via (\S+)", out)
    return m.group(1) if m else None


def fmt(v, nd=2):
    return "" if v is None else ("%.*f" % (nd, v))


def main(argv):
    args = list(argv)
    count, interval, do_https = 50, 0.2, False
    pos = []
    while args:
        a = args.pop(0)
        if a == "--count":
            count = int(args.pop(0))
        elif a == "--interval":
            interval = float(args.pop(0))
        elif a == "--https":
            do_https = True
        else:
            pos.append(a)
    if len(pos) < 2:
        print(__doc__)
        return 2
    label, csv_path, targets = pos[0], pos[1], pos[2:]
    if not targets:
        gw = default_gateway()
        targets = ([gw] if gw else []) + ["1.1.1.1"]
    try:
        need_header = open(csv_path).read(1) == ""
    except FileNotFoundError:
        need_header = True
    with open(csv_path, "a") as f:
        if need_header:
            f.write(HEADER + "\n")
        for t in targets:
            ts = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
            sent, recv, loss, mn, avg, p95, mx, jit = ping(t, count, interval)
            f.write(",".join([ts, label, t, str(sent), str(recv), "%.1f" % loss, fmt(mn), fmt(avg), fmt(p95), fmt(mx), fmt(jit)]) + "\n")
        if do_https:
            ts = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
            sent, recv, loss, mn, avg, p95, mx, jit = https(10)
            f.write(",".join([ts, label, "https:speed.cloudflare.com", str(sent), str(recv), "%.1f" % loss, fmt(mn), fmt(avg), fmt(p95), fmt(mx), fmt(jit)]) + "\n")
    print(csv_path)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
