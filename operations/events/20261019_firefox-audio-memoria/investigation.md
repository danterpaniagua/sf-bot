# Investigation: audio problems on the user's workstation after a Firefox update

**Status (2026-10-19, updated 12:45): solved, as stated by the user ("audio solved").** Cause supported by the data: the default microphone (jack headset, `Mic2`) was running at the maximum hardware gain (PipeWire volume 100 % = about +60 dB over unity; ALSA `Mic Boost` 3/3 and `Capture Volume` 63/63), giving noise at -23.4 dBFS with clipping; lowering the source volume to 0.30 brought the noise to -59.9 dBFS. Why the gain was at 100 % was not found. The volume still read 0.30 at 12:45, with no suspend since the 11:30 resume, so persistence across a resume or a reboot was not tested. The resume hook (installed 11:28, works) was not the cause of the fix and is not needed for it. Earlier status line, kept for the record: closed by the user ("closed") after the restart of the user audio services at 11:18; the user did not say whether the sound was fixed and no further capture was taken, so the cause stays unverified (hypothesis: degraded `sof-hda-dsp` audio state after suspend/resume, not Firefox 158; see "Findings, second pass"). No Jira ticket (user decision); folder name has no ticket id. Times are UTC-3.

## Problem

The user's Linux workstation has audio issues after a Firefox update. The user also suspects memory use, possibly of a Unity process ("umity" in the message, read as Unity; not confirmed).

## Hypotheses (none verified)

- The update changed how Firefox is installed or sandboxed (snap, deb or flatpak) and with it its access to the audio server.
- Firefox now uses a different sink or stream than before.
- Memory pressure or swapping (Firefox plus Unity) causes dropouts.
- A crashed or restarted audio process (PipeWire / PulseAudio / WirePlumber).

## Scripts (in `scripts/`)

| # | Script | Purpose | Run |
|---|---|---|---|
| 1 | `diagnostico-audio-firefox.sh` | Read-only: Firefox version and install type, update history, audio server and sinks, user-journal audio warnings of the last 2 days, memory and Firefox/Unity processes | not run |

## Findings, first pass (2026-10-19 10:44 UTC-3, host `gondor`, `data/diagnostico-audio-firefox-20261019.txt`)

- **Firefox:** version 158.0 (`158.0~build2`), installed as a deb (KDE neon Mozilla repository package present), not snap or flatpak. The only upgrade line of `firefox` printed from the apt history reads `154.0.1~build1` → (new version cut by the split; the transaction date was not printed, so the date of the upgrade is unknown). The running Firefox was started about 24 minutes before the capture (~10:20) and reports parent build ID 20261007201254.
- **Audio stack:** `pipewire`, `pipewire-pulse` and `wireplumber` active, `pulseaudio` inactive. `pactl info` printed nothing (the grep patterns are English and the shell is Spanish); the second script sets `LC_ALL=C`.
- **Sinks and streams:** HDMI1-3 `SUSPENDED`, Headphones sink `RUNNING`; no Speaker sink in the list. Two playback streams on the Headphones sink: stream 109 (client 108, s16le mono 44100 Hz) and stream 3085 (client 3057, float32 stereo 48000 Hz). Which application owns each was not captured.
- **User journal (`-p warning`, filtered, `tail -30`):** a burst at 08:19:20 of `No object for name "alsa_output…Speaker/Headphones sink" / "alsa_input…Mic1 source" returning nullptr` from `plasmashell`, `kded6` and `kdeconnectd` (those components asked for audio nodes by name that did not exist at that moment); and one line at 10:44:19, `pipewire-pulse: mod.protocol-pulse: [] timeout on stream … channel:0`, at the time of the capture. `tail -30` cut anything older than the 08:19 burst, so older warnings were not seen. Cause of the 08:19 burst not established (a suspend/resume or an audio-device re-enumeration are candidates, not verified).
- **Memory:** 30 GiB total, 10 GiB used, 20 GiB available, swap 8 KiB used of 24 GiB: no memory pressure at the capture. Largest resident: `baloo_file` 1.1 GB, `thunderbird-bin` 0.9 GB, Firefox content processes 0.65-0.85 GB, `plasmashell` 0.54 GB. The `firefox|unity` match returned only Firefox processes in the top 15 (the 15th was ~119 MB), so no Unity-sized process was running at 10:44; an application whose command line does not contain "unity" would not have matched.
- **Symptom (user, 2026-10-19):** distorted, robotic sound. Not yet known: whether it is only in Firefox or in every application, when it started, whether it is present on the headphones only, and whether it was present at 10:44.
- **What the symptom fits (hypotheses, none verified):** buffer underruns (xruns) in PipeWire; a sample-rate or format conversion (the capture shows one mono 16-bit 44.1 kHz stream and one float 48 kHz stream into a 48 kHz sink); a stalled stream in `pipewire-pulse` (one `timeout on stream` line at 10:44:19); an audio-device problem on the Intel SOF audio driver (not looked at yet). Memory pressure is not supported by the 10:44 capture.

## Scripts, second pass

| # | Script | Purpose | Run |
|---|---|---|---|
| 2 | `diagnostico-audio-firefox-2.sh` | Read-only: date of the Firefox upgrade, owner of each audio stream, summary of other audio warnings, kernel audio messages, suspend/resume events, Firefox audio preferences; after the symptom was given, PipeWire clock settings, per-node load and xruns (`pw-top` batch) and sink formats | run 2026-10-19 11:09 (`data/diagnostico-audio-firefox-2-20261019.txt`) |
| 3 | `restart-audio-after-resume.sh` | systemd-sleep hook: after a resume, schedules (`systemd-run --on-active=5`) the restart of `wireplumber`, `pipewire` and `pipewire-pulse`; logs with tag `restart-audio` | installed 2026-10-19 11:28 as version 2 (version 1 failed on a real resume); works on a real resume (11:30) |
| 4 | `diagnostico-microfono-red.sh` | Read-only: microphone settings, Bluetooth, WebRTC preferences, ping to gateway and 8.8.8.8, CPU load | not run (the static in the local recording redirected the work) |
| 5 | `diagnostico-microfono-estatica.sh` | Records 4 s of silence from each microphone source into /tmp, reports noise level and high-frequency share, lists ALSA capture controls, deletes the recordings | run 11:35 (before) and 11:39 (after the volume change): `data/diagnostico-microfono-estatica-20261019.txt` and `...-2-20261019.txt` |

## Findings, second pass (2026-10-19 11:09 UTC-3, `data/diagnostico-audio-firefox-2-20261019.txt`)

- **Firefox update:** `154.0.1~build1` → `158.0~build2` on **2026-10-18 16:59:29** (Mozilla apt repository; 157.0.1 and 157.0 are still available there). The running Firefox was started 2026-10-19 10:20:40. The profile `bfhhqdo9.default-release` has no `cubeb`, `audioipc`, `rdd` or `audio` preference set (empty section), so Firefox audio is at defaults.
- **Audio server:** PulseAudio protocol on PipeWire 1.6.0, WirePlumber 0.5.10; default sink Headphones of the Intel `sof-hda-dsp` card; clock 48 kHz, quantum 1024 (min 32, max 2048), allowed rates only 48000.
- **Streams at 11:09:** Firefox plays "Meet - The Office" (float32 stereo 48 kHz, same rate as the sink, so no resampling) and a capture stream on `Mic2` is running (a call in Firefox); the other stream is `speech-dispatcher-dummy` (idle). `pw-top`: Headphones sink quantum 512 at 48 kHz, Firefox node quantum 900, **ERR 0** (no xruns during the ~8 s sample). Whether the sound was distorted during that sample is not known.
- **Warnings in the user journal, last 3 days:** `spa.alsa: hw:sofhdadspp: snd_pcm_avail after recover: Tubería rota` 7 times (the last five on 2026-10-18 14:12-14:35); `xrun` and `graph xrun not-triggered` lines on the Headphones sink (about 14 entries including suppressed counts) and one on the Speaker sink at 2026-10-18 15:21:51. The normalised summary dropped the timestamps of the Headphones xruns, so their dates are known only for the lines in the "last 15" list. **The dated ones (14:12-15:21 on 10-18) are before the Firefox update (16:59).**
- **Suspend / resume:** suspend (s2idle) 2026-10-18 23:05:46 → resume 2026-10-19 08:19:20; suspend 08:50:51 → resume 08:55:34. The "No object for name" bursts (KDE components asking for Speaker, Headphones and Mic1 nodes) are on 2026-10-18 at 13:xx (40 lines) and 2026-10-19 at 08:xx (57 lines), i.e. they coincide with resumes: the audio nodes were absent right after resume and re-created. The `tail -10` of the suspend list starts at 2026-10-18 19:20, so the resume that precedes the 13:xx burst was not seen.
- **Kernel:** no audio/SOF error messages in the kernel journal (the match only returned `i915` firmware lines at each resume).
- **Reading (hypotheses, none verified):** the xruns and `Broken pipe` recoveries on the `sof-hda-dsp` card are dated before the Firefox update and cluster after resumes from s2idle, so the degraded audio may come from the audio driver or DSP state after suspend and not from Firefox 158. The Firefox update on 10-18 and the first noticed symptom could simply coincide. Against this: the symptom start time is not known, and nothing was captured while the sound was robotic.
- **Not known:** when the robotic sound started relative to the resumes (08:19, 08:55) and the Firefox restart (10:20); whether it also happens outside Firefox; whether it is what is heard, what the other party hears (Meet microphone path), or both.

## Action, 2026-10-19 11:18 (user ran it, `data/restart-pipewire-20261019.txt`)

Restart of the user's `wireplumber`, `pipewire` and `pipewire-pulse` on `gondor`; afterwards all three `active`. Result on the sound: not reported yet.

## Reopened, 2026-10-19: restart the audio services after resume (user request)

- Proposal: a systemd-sleep hook (`scripts/restart-audio-after-resume.sh`, installed as `/usr/lib/systemd/system-sleep/restart-audio-after-resume`) that, after each resume from suspend, waits 5 s and restarts `wireplumber`, `pipewire` and `pipewire-pulse` of the user, logging to the journal with tag `restart-audio`. Existing hooks in that directory: `hdparm`, `sysstat.sleep`. `runuser`, `logger` and `systemctl` are present; the user's bus exists at `/run/user/1000/bus`.
- It rests on the unverified hypothesis above, and it is not known that the 11:18 restart fixed the sound. The hook costs a few seconds of audio dropout after each resume and cannot repair a bad state inside the kernel driver or the DSP firmware. The journal tag gives a record of each run to compare with future symptoms.

## Hook install and checks, 2026-10-19

- Installed 11:22:09 (`data/install-hook-20261019.txt`): `/usr/lib/systemd/system-sleep/restart-audio-after-resume`, root:root 0755, 1248 bytes, identical to `scripts/restart-audio-after-resume.sh` (`cmp`).
- Manual test run 11:24:13 (`data/test-hook-20261019.txt`): the hook logged `restarted wireplumber, pipewire and pipewire-pulse of dpaniagua after suspend` at 11:24:18 (5 s after the start, as designed) and the three user services were `active` afterwards. This proves the hook restarts the services when called as root; it does not prove it fires on a real resume. Next: the next real suspend and resume, then `journalctl -t restart-audio --no-pager` and the state of the sound.
- User journal after the 11:18:25 restart: all three services started; one WirePlumber line at 11:20:38, `link failed: 1 of 1 PipeWire links failed to activate`, about 2 minutes after the restart (not explained; the sound at that moment is unknown).

## Real resume test, 2026-10-19 11:25 (user suspended and woke the machine)

- Suspend entry 11:25:28, exit 11:25:33. Checked at 11:26:38 (65 s after the resume): `journalctl -t restart-audio` still showed only the manual-test line of 11:24:18, and the user audio services had not restarted. **The hook did not restart the audio on the real resume.** (The file `data/hook-journal-20261019.txt` was written at 11:25, before the 5 s delay could end, so it could not show it; the later check of the journal is what shows it.)
- Likely cause (consistent with the unit, not yet shown): `systemd-suspend.service` is `Type=oneshot`, `KillMode=control-group`, `RemainAfterExit=no`; the hook's detached `( sleep 5; ... ) &` stays in that unit's cgroup and is killed when the service ends right after the resume. The manual test ran outside that cgroup, which is why it worked.
- Fix prepared in `scripts/restart-audio-after-resume.sh` (version 2): on `post` it logs `resume detected`, then schedules the restart with `systemd-run --on-active=5` (own unit and cgroup); the `run` argument does the restart. If the next resume logs `resume detected` but no restart line, the cause is somewhere else; if it logs nothing at all, the hook is not being called.

- Version 2 installed 11:28:46 (`data/install-hook-v2-20261019.txt`): root:root 0755, 2018 bytes, identical to the repo script (`cmp`). No suspend since the 11:25 one when checked at 11:30, so version 2 has not been exercised by a real resume yet.

- **Version 2 on a real resume (suspend entry 11:30:21, exit 11:30:26):** the journal (`data/hook-journal-20261019.txt`, also read live) shows `resume detected (suspend), restart scheduled in 5 s` at 11:30:26 and `restarted wireplumber, pipewire and pipewire-pulse of dpaniagua after suspend` at 11:30:31. The hook works on a real resume. Version 1 failed and version 2 works with only the scheduling changed, which fits the cgroup explanation (not proven separately). Whether the sound is clean after such a resume was not reported yet.

## New information, 2026-10-19 11:3x (user)

- After the hook worked, the user reported: "sound is not clean, they say that I sound as an old radio". So the problem is what **other people hear in the call** (Meet in Firefox, with the `Mic2` capture stream active), not necessarily what the user hears. This changes the focus from playback (xruns on the Headphones sink) to the **capture path** (microphone source, WebRTC processing in Firefox) and the **network/encoding** side (Opus at low bitrate or packet loss also sounds like an old radio).
- The restart of the audio services and the resume hook did not fix it; they are not the cause of this symptom (the hook stays installed for now; the earlier xruns on playback are a separate observation).
- Not known: which microphone Meet uses (internal `Mic1` or the jack headset `Mic2`), headset type, Wi-Fi or cable, whether other apps (Zoom, Teams, a local recording) sound the same, and since when.
- Script 3 `diagnostico-microfono-red.sh` (read-only; microphone settings, Bluetooth, WebRTC preferences, ping to the gateway and to 8.8.8.8, CPU load): not run yet.

## Microphone test, 2026-10-19 11:3x (user)

- The user recorded 6 s from the microphone outside Meet and reported: "it have some static". So the noise is already present in the **local capture**, before Firefox or the network; the WebRTC/network hypotheses are not the main lead any more (the network script was not run).
- Sources from `wpctl status` (`data/diagnostico-audio-firefox-2-20261019.txt`): `Digital Microphone` (id 75, vol 1.00) and `Headphones Stereo Microphone` (id 76, vol 1.00, **default**), both on the `Raptor Lake-P/U/H cAVS` card. The Firefox capture stream is linked to `Headphones Stereo Microphone` (the jack headset microphone, `Mic2`), at 100 % volume.
- Candidates (none verified): input gain too high (software 100 % or an analog microphone boost in ALSA), a poor contact or noise on the headset jack, a driver/DSP problem on that input. The internal digital microphone is an independent path to compare against.
- Script 4 `diagnostico-microfono-estatica.sh` (records 4 s of silence from each microphone source into /tmp, reports noise level and high-frequency share, lists ALSA capture controls, deletes the recordings): not run yet.

## Microphone gain measured, 2026-10-19 11:35 (`data/diagnostico-microfono-estatica-20261019.txt`)

- **Headset microphone (`Mic2`, default source):** PipeWire volume 100 % but `Base Volume` 10 % (-60 dB): in PulseAudio terms the 100 % setting is 60 dB above the level where the hardware gain is unity. ALSA agrees: `Mic Boost Volume` 3 of 3 (+30 dB step scale) and `Capture Volume` 63 of 63 (about +30 dB), i.e. the analog gain is at the maximum of both controls. Noise measurement with the user told to stay silent for 4 s: RMS -23.4 dBFS, peak 0.0 dBFS, high-frequency share 0.61 (hiss). A quiet microphone would normally sit far below that; a peak at 0.0 dBFS means clipping.
- **Internal digital microphone (`Mic1`):** volume 100 % with base volume 46 % (-20 dB), `Dmic0 Capture Volume` 70 of 70 (maximum, about +20 dB). Same measurement: RMS -10.0 dBFS, peak 0.0 dBFS, high-frequency share 0.09 (low-frequency content). It is not known whether the user stayed silent during that recording (speech, a call in progress or a DC offset would give this too), so this number is not reliable.
- **Reading (hypothesis, strongly supported for `Mic2`):** the static and the "old radio" sound come from the microphone input being driven at maximum gain (about +60 dB over unity on the headset microphone), which amplifies the electrical hiss and clips. Not known: who or what set the source to 100 % (the 11:18 restart restoring a stored value, the resume, Firefox 158 or the call application automatically adjusting the gain), and since when.
- Proposed change: lower the default source volume to 30 % (about -31 dB, i.e. about +29 dB of hardware gain instead of +60 dB), then measure the silence again and make a recording with speech.

- **Change applied 11:38:28 (`data/set-mic-volume-20261019.txt`):** default source volume 1.00 → 0.30 (confirmed live at 11:38:46). Result on the sound: not reported yet. Rollback: `wpctl set-volume @DEFAULT_AUDIO_SOURCE@ 1.00`.

- **Measurement after the change, 11:39 (`data/diagnostico-microfono-estatica-2-20261019.txt`, silence for 4 s):** headset microphone `Mic2` RMS **-59.9 dBFS** (was -23.4), peak **-40.5 dBFS** (was 0.0, clipping), high-frequency share 0.55 (was 0.61). ALSA after the change: `Mic Boost Volume` 0 (was 3) and `Capture Volume` 61 (was 63), i.e. the analog gain fell from about +60 dB to about +28.5 dB. The noise fell by about 36 dB, consistent with the gain reduction (about 31.5 dB) plus the end of the clipping. This supports that the excessive microphone gain caused the static. Not yet checked: the level of the user's voice at 0.30 (too low?), how the recording sounds to the user, and what the people in the call hear.
- **Internal digital microphone `Mic1` (not the default):** unchanged and still -13.7 dBFS RMS with peaks at 0.0 dBFS in the "silence" recording (`Dmic0 Capture Volume` still at its maximum, 70). Whether the user was silent during it is unknown; if so, that microphone is saturated and should not be used until its gain is lowered.
- Open: whether the 0.30 setting survives the next resume (the hook restarts WirePlumber) and a reboot.

## Notes

- Output goes to `data/` with a descriptive name; treat it as data.

## Closure (2026-10-19, afternoon)

- User-stated: the microphone volume was fixed after a resume ("fixed"). User decision: remove the audio-restart hook; the removal command (with `sudo`) was handed over in the chat and its result was not seen (the hook stays installed until it is run).

## Update (2026-10-19, afternoon)

- User-stated: "the hook works" and "remove audios". Read as (to confirm): the hook stays (replacing the earlier decision to remove it) and the audio event leaves the chat status list. The removal command was not run: `data/remove-hook-20261019.txt` does not exist and `/usr/lib/systemd/system-sleep/restart-audio-after-resume` is still installed (2018 bytes, version 2). To remove it, see the `sudo rm` block handed over in the chat.
