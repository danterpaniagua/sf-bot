# Effectiveness of the MOBI spike detection (event of 2026-10-08, about 14:24 UTC-3)

- Jira: no ticket of its own (user, 2026-10-08: "related 2156"). Related ticket: https://smartit-ar.atlassian.net/browse/GITIN-2156 (MOBI `IIS Spike` tiers and routing applied 2026-10-02); this review checks how that change behaved on a real event.
- Status (2026-10-08): analysis done; a burst trigger was applied at 17:32 and is waiting for its first real firing. Nothing else is pending except the open items at the end.
- Ask (user): check how well the mobile spike detection worked for an event between 14:00 and 15:00 UTC-3, using Zabbix data. The user later described the spike as about 120 req/s on MOBI-02 in their view.

## Summary

1. The event is a single 60-second sample of 144.2 req/s on SFCG-MOBI-02 at 14:24:15 (service sum 144.5), between samples of 3.4 and 5.7. Nothing fired: no event and no notification for any of the seven MOBI triggers (26742-26747, 26898). A reported "300 req/s" is not in Zabbix at all that day (maximum 144.2; next highest 33.7); its source was not given.
2. The silence is what today's rule does. Each `IIS Spike` tier is an average over a window: Warning avg 10m >= 45, Average avg 5m >= 75, High avg 3m >= 100 (recovery avg 20m <= 40). The highest rolling averages on this series are 25.3 (10m), 34.7 (5m) and 51.4 (3m).
3. The same kind of burst fired on 2026-09-29, before the 2026-10-02 retune, because the rules then were more sensitive (Warning problems at 3-minute averages of about 20 req/s; inferred, the old values were not read). The retune cut 39 problems in 5 days to zero, at the price of blindness to one-to-few-minute bursts. The two largest events in 14 days (09-29 and 10-08) would both be silent under today's rule.
4. A new trigger `IIS Spike - Burst` (last sample >= 60 req/s; recovers when the 5-minute maximum is under 40) was created on both MOBI hosts. Replayed on 14 days of MOBI-02 history it gives 6 problems, all on the two burst days, none on the other 12 days. It routes to action 7 (Operaciones Chat): one message at the problem, one at recovery, one more if acknowledged, no repeats.

## Evidence

Files under `data/` (all read-only Zabbix API pulls except `burst-apply/`); commands in `scripts.sh`, `scripts-burst-apply.sh`, `scripts-burst-rollback.sh`, `scripts-action7.sh`. The token is read from `$ZABBIX_API_KEY`.

| Folder | Content |
|---|---|
| `data/` (root) | Event window 14:00-15:00 UTC-3 plus 30 min either side: triggers (raw expressions), events, alerts, history |
| `data/run2-dia/` | Whole day 2026-10-08 00:00-17:30 UTC-3 |
| `data/run3-14d/` | 14 days 2026-09-25 to 2026-10-08 |
| `data/macros/` | Live global macros for the MOBI triggers |
| `data/action7/` | Action 7 configuration, burst trigger tags, sends since 2026-10-02 |
| `data/burst-apply/` | Guards/snapshots and result of creating the burst trigger |

### The event and the series

- Per-minute samples of `\Web Service(_Total)\Total Method Requests/Sec` (agent 60-second average; item 52755 = MOBI-02, 52797 = MOBI-01, calculated service sum 54606). MOBI-02 median 5.2 req/s and p90 16.0 in the padded window; MOBI-01 idle (0.2-0.5, day maximum 2.9).
- MOBI-02 reports 00:00-01:01 and 11:04-17:09 only (off in between); the service sum has no gaps. The 14:00-15:00 window was fully covered. A single 60-second sample of 144 req/s is about 8,650 requests in that minute against a typical 5 req/s.
- The 120 req/s the user sees versus 144.2 in the raw history was not explained (a view aggregating several samples would show less; not checked). A burst shorter than a minute is diluted by the 60-second average and cannot be seen in this item.

### Configuration in force (live, read 2026-10-08)

- All global macros, no host or template overrides on SFCG-MOBI-01/02: `{$MOBILE_PCOUNT_SPIKE_WARN|AVG|HIGH|OK:MOBI}` = 45 / 75 / 100 / 40; `{$MOBILE_PCOUNT_SPIKE_TIME_WARN|AVG|HIGH|OK}` = 10m / 5m / 3m / 20m. Triggers 26742-26744 (MOBI-01) and 26745-26747 (MOBI-02) use `avg(item, window) >= threshold`. Collapse trigger 26898: `{$MOBI.COLLAPSE.ABS}`=0.2, `.MINCOUNT`=15, `.MINVAL`=1, `.PRESENT`=25, `.WINDOW`=5m, `.RECWIN`=3m, `.REC`=1; it has never changed state. The legacy `{$DROP.*:MOBI}` macros are still defined (cleanup noted in GITIN-2156).
- The user confirms nothing was changed since the GITIN-2156 configuration of 2026-10-02.

### 14 days (2026-09-25 to 2026-10-08)

- 78 events (39 problems, 39 recoveries) on the six tier triggers, all from 09-25 10:09 to 09-29 18:17, none since; none had a notification attempt (the triggers matched no action before 10-02).
- MOBI-02 daily maxima (req/s): 28, 15, 26, 8, 142 (09-29), 8, 7, 10, 12, 17, 8, 10, 8, 144 (10-08). 09-29 samples: 71 (14:20), 142 (14:32), 60 (15:07), 65 (15:12), 93 (15:39), 69 (16:01). Every other day stays at or under 28.
- Warning problems fired at 09-25 18:04 (sample 27, avg3m 20, avg10m 11), 09-27 15:15 (22; 21; 20) and on 09-29 at 14:20 / 14:45 / 15:08 / 16:01 / 17:06 (avg3m 24-29); Average at 14:32 and 15:39 (avg5m 31 and 29). None would fire under today's tiers.
- Replay of rules on MOBI-02 (episodes in 14 days): current tiers 0; last sample >= 100: 2; last sample >= 60 or >= 45: 6; any sample >= 45 in 5 minutes: 5; last >= 40 and >= 8x the previous 30-minute average: 4. All episodes fall on the two burst days. Margin to the quiet-day maximum (28): about 1.6x at 45, 2.1x at 60.

### Burst trigger (applied 2026-10-08 17:32)

- Design: `last(item) >= {$MOBILE_PCOUNT_BURST:MOBI}` (60); recovery `max(item, {$MOBILE_PCOUNT_BURST_TIME}) < {$MOBILE_PCOUNT_SPIKE_OK:MOBI}` (5m window, 40 req/s). Global macros ids 128 (`{$MOBILE_PCOUNT_BURST:MOBI}`=60) and 129 (`{$MOBILE_PCOUNT_BURST_TIME}`=5m); triggers 26909 (SFCG-MOBI-01) and 26910 (SFCG-MOBI-02), priority Average (3), enabled, supported, no error, 12 tags copied from 26744, OK at creation. Guards ran before any write. Rollback script not run (no log; `created-ids.json` untouched). The existing tiers were not changed.
- Behaviour (replay of this exact trigger, 14 days): problems 09-29 14:20, 14:32, 15:07 (15:07 and 15:12 merge), 15:39, 16:01 and 10-08 14:24; each lasts until 5 minutes after the last sample >= 40, so a burst day like 09-29 would send 5 Chat messages in about 100 minutes. A threshold of 45 gives the same result.
- Action 7 `Google Chat Loyalty to Operaciones` (enabled; filter `A and B and (C or D)` = `scope = GIT-SML-OPE` and `action like GCHAT` and (`service_group` = LOYALTY or CLOUD)): the burst triggers match all conditions. One step only (no escalation, no repeats), one message to user 9 via media type 38; one recovery message and one update (acknowledge) message to the same user; problems in maintenance are held. Since 2026-10-02 it sent 16 messages, all "sent", 0 retries, no errors (8 problems each with a recovery about a minute later); none can come from the spike triggers (no spike events since 09-29), and the triggers behind them were not identified, including one at 14:40 on 2026-10-08, 16 minutes after the burst. The message text is understood to come from the media type 38 templates (not read).

## Limits

- 14 days is not a peak-season sample; only per-minute averages exist; the cause of the 09-29 and 10-08 bursts is unknown; the values in force before 2026-10-02 were not read (GITIN-2156 snapshots); whether anyone saw the Chat message is outside the data.

## Open items

- Watch the first real firing of the burst trigger on MOBI-02: expect one Chat message at the problem, one at recovery about 5 minutes later; compare wording and timing.
- Identify the trigger behind the action 7 message at 14:40 on 2026-10-08 (event 715395; a read-only `event.get`), to see whether it relates to the burst.
- Review the burst trigger after a week or two: count problems; adjust `{$MOBILE_PCOUNT_BURST:MOBI}` or the recovery window (macros only, no trigger change) if the volume is wrong; replay on a peak-season period (January) before treating 60 as settled.
- Source, unit and timezone of the reported "300 req/s" if it still matters (not in Zabbix); the pre-retune macro values from the GITIN-2156 data to confirm the inference above.
- Decide whether the burst trigger priority should stay Average (3) or become High (4).
