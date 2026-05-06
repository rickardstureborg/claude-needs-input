#!/bin/bash
# PreToolUse hook — kill any in-flight pulser before the tool runs.
# Catches the case where a permission_prompt left a pulser running and there's
# no explicit close-event when the user accepts: the next tool starting is
# itself the signal that the user un-blocked us.

source ~/.claude/notify/lib.sh

INPUT=$(cat)
SID=$(read_session_id "$INPUT")
TTY=$(resolve_tty)

kill_pulser "$SID"
[ -n "$TTY" ] && [ -e "$TTY" ] && clear_tab_color "$TTY"
exit 0
