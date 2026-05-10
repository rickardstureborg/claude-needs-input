# shellcheck shell=bash
# iTerm2 tab color helpers, sourced by the other scripts in this dir.
# OSC 6 ; 1 ; bg ; <channel> ; brightness ; <0-255> BEL  — sets one RGB channel.
# OSC 6 ; 1 ; bg ; * ; default BEL                       — clears tab color.

# A marker file (/tmp/claude-tint-<tty basename>) tracks every tab we've tinted.
# It lets dismiss.sh reset a solid-colored tab that has no pulser — which an
# iTerm2 coprocess could not otherwise discover (it has no tty of its own).

set_tab_rgb() {
  local tty=$1 r=$2 g=$3 b=$4
  # 2>/dev/null must precede >"$tty": redirections apply left-to-right, so if the
  # tty open fails the error is already routed to /dev/null. With the other order
  # the open failure leaks to real stderr — which makes iTerm2 flag a coprocess.
  printf '\033]6;1;bg;red;brightness;%d\007'   "$r" 2>/dev/null > "$tty"
  printf '\033]6;1;bg;green;brightness;%d\007' "$g" 2>/dev/null > "$tty"
  printf '\033]6;1;bg;blue;brightness;%d\007'  "$b" 2>/dev/null > "$tty"
  [ -n "$tty" ] && printf '%s\n' "$tty" 2>/dev/null > "/tmp/claude-tint-${tty##*/}"
}

clear_tab_color() {
  local tty=$1
  printf '\033]6;1;bg;*;default\007' 2>/dev/null > "$tty"
  [ -n "$tty" ] && rm -f "/tmp/claude-tint-${tty##*/}"
}

# Hooks are children of Claude Code, which has the iTerm2 tab as its tty.
resolve_tty() {
  local t
  { t=$(tty < /dev/tty); } 2>/dev/null
  if [ -n "$t" ] && [ -e "$t" ]; then echo "$t"; return; fi
  t=$(ps -o tty= -p "$PPID" 2>/dev/null | tr -d ' ')
  [ -n "$t" ] && echo "/dev/$t"
}

read_session_id() {
  local json=$1
  python3 -c 'import json,sys; print(json.loads(sys.stdin.read()).get("session_id",""))' <<< "$json" 2>/dev/null
}

pulse_pidfile() {
  echo "/tmp/claude-pulse-${1:-unknown}.pid"
}

# Pidfiles hold the pulser PID on line 1 and its tty on line 2 (see pulse.sh).
kill_pulser() {
  local pf
  pf=$(pulse_pidfile "$1")
  if [ -f "$pf" ]; then
    local pid
    pid=$(head -1 "$pf" 2>/dev/null)
    [ -n "$pid" ] && kill "$pid" 2>/dev/null
    rm -f "$pf"
  fi
}

# Stop the pulser bound to a given tty, regardless of session id — used by
# dismiss.sh when it does know a specific tty (run from the `!` prefix).
kill_pulser_by_tty() {
  local want=${1:-} pf pid tty
  [ -n "$want" ] || return 0
  for pf in /tmp/claude-pulse-*.pid; do
    [ -f "$pf" ] || continue
    pid=""; tty=""
    { IFS= read -r pid; IFS= read -r tty; } < "$pf" 2>/dev/null
    if [ "$tty" = "$want" ]; then
      [ -n "$pid" ] && kill "$pid" 2>/dev/null
      rm -f "$pf"
    fi
  done
}

# Stop every pulser and reset every tab the tool has tinted — pulsing or solid.
# dismiss.sh uses this when it has no specific tty: an iTerm2 coprocess can't
# tell which tab triggered it, so it resets them all.
dismiss_all() {
  local pf pid m tty
  for pf in /tmp/claude-pulse-*.pid; do
    [ -f "$pf" ] || continue
    pid=$(head -1 "$pf" 2>/dev/null)
    [ -n "$pid" ] && kill "$pid" 2>/dev/null
    rm -f "$pf"
  done
  for m in /tmp/claude-tint-*; do
    [ -f "$m" ] || continue
    tty=$(head -1 "$m" 2>/dev/null)
    if [ -n "$tty" ] && [ -e "$tty" ]; then
      clear_tab_color "$tty"
    else
      rm -f "$m"
    fi
  done
}
