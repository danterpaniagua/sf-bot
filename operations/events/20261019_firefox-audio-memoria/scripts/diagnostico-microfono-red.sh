#!/usr/bin/env bash
# Read-only pass for "others hear me like an old radio" in a call from Firefox: microphone (source) settings, Bluetooth, WebRTC preferences,
# network quality (local gateway and upstream) and CPU load. Best run during a call. The ping tests send 30 small packets each (about 6 s each).
# Usage: bash diagnostico-microfono-red.sh > <output file> 2>&1
export LC_ALL=C
echo "== host: $(hostname) user: $(whoami) date: $(date '+%F %T %z') =="
echo "== default source and sources (state, mute, volume, port, rate) =="
pactl info 2>&1 | grep -E 'Default Source'
pactl list sources 2>&1 | grep -E 'Source #|Name:|Description:|State:|Mute:|Volume:|Sample Specification|Active Port|device.bus|device.form_factor|alsa.card_name' | cut -c1-170
echo "== source outputs (who captures what) =="
pactl list source-outputs 2>&1 | grep -E 'Source Output #|application.name|application.process.binary|media.name|Sample Specification|Source:|Corked|Resample' | cut -c1-170
echo "== wpctl default source =="; wpctl inspect @DEFAULT_AUDIO_SOURCE@ 2>&1 | grep -E 'node.name|node.description|audio.rate|audio.channels|audio.format|node.latency|api.alsa.pcm|device.profile|priority' | cut -c1-160
echo "== cards and bluetooth =="; pactl list cards short 2>&1; bluetoothctl devices Connected 2>&1 | head -5
echo "== firefox webrtc / getusermedia preferences (names and values) =="
for p in "$HOME"/.mozilla/firefox/*/prefs.js "$HOME"/.mozilla/firefox/*/user.js; do
  [ -f "$p" ] || continue
  echo "-- $p"; grep -E 'media\.(getusermedia|navigator|peerconnection)|webrtc' "$p" | cut -c1-160 | head -30
done
echo "== network: active connections and wifi link =="
nmcli -t -f NAME,TYPE,DEVICE connection show --active 2>&1
for d in $(iw dev 2>/dev/null | awk '$1=="Interface"{print $2}'); do echo "-- $d"; iw dev "$d" link 2>&1 | cut -c1-120; done
GW=$(ip route 2>/dev/null | awk '/^default/{print $3; exit}')
echo "== ping local gateway ($GW), 30 packets =="; [ -n "$GW" ] && ping -c 30 -i 0.2 -q "$GW" 2>&1 | tail -3
echo "== ping 8.8.8.8, 30 packets =="; ping -c 30 -i 0.2 -q 8.8.8.8 2>&1 | tail -3
echo "== cpu load =="; uptime; nproc; top -b -n 1 -w 160 2>&1 | head -14 | cut -c1-150
