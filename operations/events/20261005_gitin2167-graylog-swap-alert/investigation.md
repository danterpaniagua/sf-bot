# GITIN-2167 — [OPE] Graylog SWAP Alert

- Jira: https://smartit-ar.atlassian.net/browse/GITIN-2167
- Opened: 2026-10-05
- Status: in progress (not converged)
- Host: OS hostname and OpenSearch node name are both `sfcloud-monitoreo` (`data/opensearch-cat-nodes.txt`, `data/opensearch-xm-flag-sources.txt`; reached over SSH at sf-monitoreo.smartfran.com). Runs Graylog, Logstash, OpenSearch, MongoDB.
- Duplicate heap flags source (H4): `/etc/opensearch/jvm.options` lines 22–23 (`-Xms1g -Xmx1g`, packaged default; lines 11–12 are a commented `4g` pair) and the override `/etc/opensearch/jvm.options.d/heap.options` (`-Xms12g -Xmx12g`). `/etc/default/opensearch` has `OPENSEARCH_JAVA_OPTS` commented out. The `jvm.options.d` override is the standard OpenSearch pattern and the later occurrence wins, so this is expected behavior, not a misconfiguration; no change needed.

## What is known

- Alert is a swap-usage alert on the Graylog host. Alert definition (threshold, Zabbix trigger) not yet looked at.
- Host: 31 GiB RAM, ext4 root, separate XFS volumes mounted at /var/lib/opensearch and /var/lib/mongodb (both `nofail`).
- Swap before work: 4 GiB (`/swapfile`). Swap usage then and now: 3.4 GiB used of 8 GiB total, 11 GiB RAM "available" (`data/free-h-before-and-after.txt`).
- Action taken by the user: created 4 GiB swap file `/var/lib/mongodb/swapfile` (dd bs=1M count=4096, chmod 600, mkswap, swapon). The first command proposed (`bs=1024 count=1048576`) would only have been 1 GiB; corrected to 4 GiB. Total swap is now 8 GiB (4+4, stated by the user; `swapon --show` output not captured). Both swap entries are present in /etc/fstab (`data/etc-fstab.txt`), so it persists across reboot. Swap file lives on the same XFS volume as MongoDB data (user's choice; `/swapfile` on root was the alternative suggested).
- `vm.swappiness` = 10 already.
- Swapped memory by process (kB): logstash java ~1.76 GB, graylog java ~1.2 GB, opensearch java ~0.41 GB, mongod ~0.10 GB (`data/swappiness-and-vmswap-by-process.txt`, `data/java-pid-map-and-vmstat.txt`).
- Live swap I/O is ~0: `vmstat 5 6` rows after the since-boot average show si/so 0–3 KB/s, wa ≤1%. Interpretation (hedged): the 3.4 GiB is most likely cold pages swapped out earlier and never touched again, not ongoing pressure. Not verified for when/why they were swapped out.
- Heap budget: logstash -Xms4g/-Xmx4g, graylog -Xms4g/-Xmx4g, opensearch has both `-Xms1g -Xmx1g` (args 20–21) and `-Xms12g -Xmx12g` (args 37–38). JVM uses the last occurrence, so effective OpenSearch heap is most likely 12 GB, consistent with ~20 GiB "used". Confirmed via OpenSearch API: `heap.max` = 12gb, `heap.percent` = 37 (≈4.4 GB of heap in use), so the 12 GB flags are the effective ones. `ram.percent` = 99 on a 31.3 GB node; this is OpenSearch's view of OS memory and, given `free` showed ~1.2 GiB free with ~10 GiB buff/cache, most likely counts page cache as used (not verified how OpenSearch computes it). `jcmd` attach failed (`data/opensearch-cmdline-xm-flags-and-jcmd-error.txt`), plausibly because OpenSearch uses a private tmpdir and/or jcmd ran as a different user than the process — not a sign the JVM is hung.

## Open items

- Confirm hostname and what the alert threshold/trigger measures (swap % vs absolute) — would the extra 4 GiB clear it, or does it alert on any usage.
- (Done) Effective OpenSearch heap confirmed 12gb via `_cat/nodes`.
- Confirm both swap areas active via `swapon --show` (user stated 4G+4G).
- (Resolved) Duplicate `-Xms1g/-Xmx1g` flags: packaged default plus `jvm.options.d/heap.options` override; leave as is.
- Decide whether reclaiming swapped pages (swapoff/swapon) is worth it; not proposed as necessary.
- Check whether a memory-lock/restart problem recurs (related earlier work: GITIN-1827, per memory index; not re-verified here).
