#!/bin/bash
# UserPromptSubmit hook — user is back. Kill any pulser, clear the tab color.

source "$(dirname "$0")/lib.sh"

INPUT=$(cat)
SID=$(read_session_id "$INPUT")
TTY=$(resolve_tty)

kill_pulser "$SID"
[ -n "$TTY" ] && [ -e "$TTY" ] && clear_tab_color "$TTY"
exit 0
