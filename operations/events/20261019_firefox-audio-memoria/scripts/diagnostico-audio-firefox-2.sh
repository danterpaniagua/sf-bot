#!/usr/bin/env bash
# Second read-only pass: date of the Firefox upgrade, which application owns each audio stream (English locale, the first pass printed nothing for `pactl info` because of the Spanish locale),
# a summary of the user-journal audio warnings other than "No object for name", kernel audio messages, suspend/resume events and the Firefox audio preferences.
# Usage: bash diagnostico-audio-firefox-2.sh > <output file> 2>&1
export LC_ALL=C
echo "== host: $(hostname) user: $(whoami) date: $(date '+%F %T %z') =="
echo "== firefox: installed version, binary date, policy =="; dpkg-query -W -f='${Package} ${Version}\n' firefox 2>&1; ls -l --time-style=long-iso /usr/lib/firefox/firefox-bin 2>&1; apt-cache policy firefox 2>&1 | head -12
echo "== firefox upgrade transactions in apt history (date, version change) =="
for f in /var/log/apt/history.log /var/log/apt/history.log.*.gz; do
  [ -r "$f" ] || continue
  case "$f" in *.gz) zcat "$f" ;; *) cat "$f" ;; esac | awk -v F="$f" '/^Start-Date/ {d=$0} /^(Upgrade|Install|Remove):/ { if (match($0, /firefox:amd64 \([^)]*\)/)) print F ": " d " | " substr($0, RSTART, RLENGTH) }'
done
echo "== firefox process start =="; ps -o pid,lstart,etime,args -p "$(pgrep -o -f '^/usr/bin/firefox$' | head -1)" 2>&1 | cut -c1-160
echo "== audio server =="; pactl info 2>&1 | grep -E 'Server Name|Server Version|Default Sink|Default Source'; pipewire --version 2>&1 | head -2; wireplumber --version 2>&1 | head -2
echo "== wpctl status =="; wpctl status 2>&1 | head -45
echo "== sink inputs (who plays what) =="; pactl list sink-inputs 2>&1 | grep -E 'Sink Input #|application.name|application.process.binary|media.name|State:|Corked|Sample Specification|Latency:|Resample' | cut -c1-160
echo "== user journal: audio warnings except 'No object for name', last 3 days, normalised and counted =="
journalctl --user --since "3 days ago" -p warning --no-pager 2>/dev/null | grep -iE 'pipewire|pulse|wireplumber|alsa|firefox|cubeb' | grep -v 'No object for name' | sed -E 's/^[A-Za-z]{3} [0-9]+ [0-9:]+ [^ ]+ //; s/\[[0-9]+\]//; s/0x[0-9a-f]+/0xX/g' | sort | uniq -c | sort -rn | head -20
echo "== user journal: last 15 audio warnings except 'No object for name' =="
journalctl --user --since "3 days ago" -p warning --no-pager 2>/dev/null | grep -iE 'pipewire|pulse|wireplumber|alsa|firefox|cubeb' | grep -v 'No object for name' | tail -15 | cut -c1-200
echo "== user journal: 'No object for name' lines per day and hour =="
journalctl --user --since "3 days ago" -p warning --no-pager 2>/dev/null | grep 'No object for name' | awk '{print $1, $2, substr($3,1,2)}' | sort | uniq -c
echo "== kernel audio messages, last 3 days =="; journalctl -k --since "3 days ago" --no-pager 2>&1 | grep -iE 'sof|snd_|hda|audio|firmware' | tail -20 | cut -c1-200
echo "== suspend / resume events, last 3 days =="; journalctl --since "3 days ago" --no-pager 2>/dev/null | grep -E 'PM: suspend (entry|exit)|systemd-sleep' | tail -10 | cut -c1-160
echo "== firefox audio-related preferences (names and values of cubeb, rdd, audioipc, audio only) =="
for p in "$HOME"/.mozilla/firefox/*/prefs.js "$HOME"/.mozilla/firefox/*/user.js; do
  [ -f "$p" ] || continue
  echo "-- $p"; grep -E 'cubeb|media\.audioipc|media\.rdd|audio' "$p" | cut -c1-160 | head -30
done
echo "== pipewire clock settings (rate, quantum) =="; pw-metadata -n settings 2>&1 | head -12 | cut -c1-160
echo "== pipewire per-node load and xruns (pw-top batch, 2 iterations; ERR = xruns) =="; timeout 8 pw-top -b -n 2 2>&1 | cut -c1-170 | head -40
echo "== sinks: state, format, latency, active port =="; pactl list sinks 2>&1 | grep -E 'Name:|State:|Sample Specification|Latency:|Active Port|api.alsa.pcm.card|alsa.card_name' | cut -c1-160
