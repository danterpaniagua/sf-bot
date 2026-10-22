#!/usr/bin/env bash
# Measures the noise of every microphone source and lists the capture settings, to find the cause of static in the microphone recording.
# Records 4 s from each non-monitor source into /tmp (stay SILENT during the recordings, keep the headset as you use it in calls), computes the level
# of the noise (RMS and peak in dBFS and the share of high-frequency energy) with python3, and removes the recordings. No audio is kept in the repository.
# Usage: bash diagnostico-microfono-estatica.sh > <output file> 2>&1
export LC_ALL=C
echo "== host: $(hostname) user: $(whoami) date: $(date '+%F %T %z') =="
echo "== sources: state, mute, volume, active port =="
pactl list sources 2>&1 | grep -E 'Name:|Description:|State:|Mute:|Volume:|Active Port|analog-input|Ports:' | grep -v monitor | cut -c1-170
echo "== alsa capture controls (card 0) =="
amixer -c 0 contents 2>&1 | grep -iE -A3 "numid.*(mic|capture|boost|headset|headphone mic)" | cut -c1-150 | head -60
echo "== noise floor per source, 4 s of silence each =="
D=$(mktemp -d /tmp/mic-noise.XXXXXX)
for name in $(pactl list short sources 2>/dev/null | awk '$2 !~ /monitor/ {print $2}'); do
  echo "-- $name"
  timeout -s INT 6 pw-record --target "$name" --rate 48000 --channels 1 --format s16 "$D/$name.wav" >/dev/null 2>&1 &
  sleep 5; wait
  python3 -I - "$D/$name.wav" <<'EOF'
import sys, wave, array, math
try:
    w = wave.open(sys.argv[1]); n = w.getnframes(); a = array.array("h"); a.frombytes(w.readframes(n))
except Exception as e:
    print("  could not read the recording:", e); sys.exit()
a = a[len(a) // 5:]          # skip the first fifth (start-up)
if not a:
    print("  empty recording"); sys.exit()
rms = math.sqrt(sum(x * x for x in a) / len(a)); peak = max(abs(x) for x in a)
d = [a[i + 1] - a[i] for i in range(len(a) - 1)]
rd = math.sqrt(sum(x * x for x in d) / len(d))
db = lambda v: 20 * math.log10(v / 32768) if v > 0 else -120
print(f"  samples {len(a)}  rms {db(rms):.1f} dBFS  peak {db(peak):.1f} dBFS  high-frequency share (rms of the difference / rms) {rd / rms if rms else 0:.2f}")
EOF
done
rm -rf "$D"
echo "(recordings removed)"
