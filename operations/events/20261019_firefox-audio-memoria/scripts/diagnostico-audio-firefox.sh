#!/usr/bin/env bash
# Read-only diagnosis of audio problems after a Firefox update on the user's Linux workstation, plus a memory check (Firefox and Unity processes).
# Usage: bash diagnostico-audio-firefox.sh > <output file> 2>&1
echo "== host: $(hostname) user: $(whoami) date: $(date '+%F %T %z') =="
echo "== firefox =="; firefox --version 2>/dev/null; which -a firefox; snap list firefox 2>/dev/null; dpkg -l 2>/dev/null | grep -i '^ii.*firefox'; flatpak list 2>/dev/null | grep -i firefox
echo "== update history =="; grep -i firefox /var/log/apt/history.log 2>/dev/null | tail -5; snap changes 2>/dev/null | tail -5
echo "== audio server =="; pactl info 2>/dev/null | grep -E 'Server Name|Server Version|Default Sink'; systemctl --user is-active pipewire pipewire-pulse wireplumber pulseaudio
echo "== sinks and streams =="; pactl list short sinks; pactl list short sink-inputs
echo "== audio warnings, last 2 days =="; journalctl --user --since "2 days ago" -p warning --no-pager 2>/dev/null | grep -iE 'pipewire|pulse|wireplumber|alsa|firefox' | tail -30
echo "== memory =="; free -h; ps -eo pid,rss,etime,comm --sort=-rss | head -12
echo "== firefox and unity processes =="; ps -eo pid,rss,etime,args --sort=-rss | grep -iE '[f]irefox|[u]nity' | cut -c1-150 | head -15
