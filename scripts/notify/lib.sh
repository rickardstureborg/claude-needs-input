# shellcheck shell=bash
# iTerm2 tab color helpers, sourced by the other scripts in this dir.
# OSC 6 ; 1 ; bg ; <channel> ; brightness ; <0-255> BEL  — sets one RGB channel.
# OSC 6 ; 1 ; bg ; * ; default BEL                       — clears tab color.

set_tab_rgb() {
  local tty=$1 r=$2 g=$3 b=$4
  # 2>/dev/null must precede >"$tty": redirections apply left-to-right, so if the
  # tty open fails the error is already routed to /dev/null. With the other order
  # the open failure leaks to real stderr — which makes iTerm2 flag a coprocess.
  printf '\033]6;1;bg;red;brightness;%d\007'   "$r" 2>/dev/null > "$tty"
  printf '\033]6;1;bg;green;brightness;%d\007' "$g" 2>/dev/null > "$tty"
  printf '\033]6;1;bg;blue;brightness;%d\007'  "$b" 2>/dev/null > "$tty"
}

clear_tab_color() {
  local tty=$1
  printf '\033]6;1;bg;*;default\007' 2>/dev/null > "$tty"
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

kill_pulser() {
  local pf
  pf=$(pulse_pidfile "$1")
  if [ -f "$pf" ]; then
    local pid
    pid=$(cat "$pf" 2>/dev/null)
    [ -n "$pid" ] && kill "$pid" 2>/dev/null
    rm -f "$pf"
  fi
}
