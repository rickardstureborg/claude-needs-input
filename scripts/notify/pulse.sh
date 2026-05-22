#!/bin/bash
# Background pulser — fades the iTerm2 tab between bright and soft orange until killed.
# Args: $1=session_id  $2=tty_path

set -u
SESSION_ID=${1:-unknown}
TTY=${2:-}

source "$(dirname "$0")/lib.sh"

PIDFILE=$(pulse_pidfile "$SESSION_ID")
# Line 1 = our PID (kill_pulser reads this). Line 2 = the tty, so dismiss.sh can
# stop the pulser bound to a given tab without knowing the Claude Code session id.
printf '%s\n%s\n' "$$" "$TTY" > "$PIDFILE"
trap 'rm -f "$PIDFILE"; exit 0' TERM INT EXIT

[ -z "$TTY" ] || [ ! -e "$TTY" ] && exit 0

# Bright orange (255,140) <-> soft orange (195,100). Higher floor = visible
# even on inactive iTerm2 tabs. 10 frames @ 0.32s = ~3.2s per cycle.
RAMP_R=(255 245 230 215 205 195 205 215 230 245)
RAMP_G=(140 135 125 115 108 100 108 115 125 135)
RAMP_B=(  0   0   0   0   0   0   0   0   0   0)
STEPS=${#RAMP_R[@]}

i=0
while [ -f "$PIDFILE" ] && [ -e "$TTY" ]; do
  set_tab_rgb "$TTY" "${RAMP_R[$i]}" "${RAMP_G[$i]}" "${RAMP_B[$i]}"
  i=$(( (i + 1) % STEPS ))
  sleep 0.32
done
