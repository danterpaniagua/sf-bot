#!/bin/sh
# systemd-sleep hook: after the system comes back from suspend, restart the audio services of the desktop user.
# Installed as /usr/lib/systemd/system-sleep/restart-audio-after-resume (root-owned, mode 0755). systemd calls it as: <script> pre|post suspend|hibernate|...
# Every step is logged to the system journal with the tag "restart-audio" (journalctl -t restart-audio).
#
# Why it schedules the restart with systemd-run instead of a background "sleep 5 && ...":
# systemd-suspend.service is Type=oneshot with KillMode=control-group, so a process left running by the hook is killed when the
# service ends right after the resume (the first version did exactly that: the manual test worked, the real resume logged nothing).
# systemd-run starts the work from the system manager, in its own unit and cgroup.
#
# Hypothesis behind the whole hook (not verified): after a resume from s2idle the audio nodes are re-created and the sound can be robotic
# until the audio services restart.
USER_NAME=dpaniagua

restart_audio() {
  UID_=$(id -u "$USER_NAME") || { logger -t restart-audio "user $USER_NAME not found"; exit 0; }
  if [ ! -S "/run/user/$UID_/bus" ]; then
    logger -t restart-audio "no user session bus for $USER_NAME after $1, nothing restarted"
    exit 0
  fi
  if runuser -u "$USER_NAME" -- env XDG_RUNTIME_DIR="/run/user/$UID_" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$UID_/bus" \
       systemctl --user restart wireplumber pipewire pipewire-pulse; then
    logger -t restart-audio "restarted wireplumber, pipewire and pipewire-pulse of $USER_NAME after $1"
  else
    logger -t restart-audio "restart FAILED for $USER_NAME after $1"
  fi
}

case "$1" in
  post)
    logger -t restart-audio "resume detected ($2), restart scheduled in 5 s"
    systemd-run --quiet --no-block --on-active=5 --description="Restart audio services after resume" "$0" run "$2" \
      || logger -t restart-audio "systemd-run FAILED, nothing scheduled"
    ;;
  run)
    restart_audio "$2"
    ;;
esac
exit 0
