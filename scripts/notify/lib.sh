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

# Record ITERM_SESSION_ID -> tty. dismiss.sh runs as an iTerm2 coprocess: it
# inherits ITERM_SESSION_ID but has no tty of its own, so this map — written by
# the in-session hooks, which do have the tty — is how it finds the right tab.
# Keyed by the stable UUID part of ITERM_SESSION_ID (the wNtMpK prefix changes
# if the tab is moved). Only real ttys are recorded — never /dev/?? etc.
_record_iterm_tty() {
  local tty=$1 uuid=${ITERM_SESSION_ID#*:}
  [ -n "$uuid" ] && [ -n "$tty" ] && [ -e "$tty" ] || return 0
  printf '%s\n' "$tty" 2>/dev/null > "/tmp/claude-iterm-$uuid"
}

# Hooks are children of Claude Code, which has the iTerm2 tab as its tty.
resolve_tty() {
  local t
  { t=$(tty < /dev/tty); } 2>/dev/null
  if [ -n "$t" ] && [ -e "$t" ]; then _record_iterm_tty "$t"; echo "$t"; return; fi
  t=$(ps -o tty= -p "$PPID" 2>/dev/null | tr -d ' ')
  if [ -n "$t" ]; then _record_iterm_tty "/dev/$t"; echo "/dev/$t"; fi
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
# dismiss.sh to stop the pulse on exactly the tab the user invoked it from.
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
