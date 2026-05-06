#!/bin/bash
# Optional Stop hook — sets the tab solid green on every Stop, unconditionally.
# NOT registered by install.sh; the default classifier (notify-input-needed.sh) already
# sets green on CLOSING turns and orange on BLOCKING turns. Wire this only if you want
# green on EVERY turn end (and accept it racing with the classifier's orange-on-BLOCKING).

source "$(dirname "$0")/lib.sh"

INPUT=$(cat)
SID=$(read_session_id "$INPUT")
TTY=$(resolve_tty)

kill_pulser "$SID"
[ -n "$TTY" ] && [ -e "$TTY" ] && set_tab_rgb "$TTY" 40 200 80
exit 0
