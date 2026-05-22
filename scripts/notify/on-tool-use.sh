#!/bin/bash
# Pre/PostToolUse hook — kill any in-flight pulser around every tool call.
#   PreToolUse  — a permission_prompt can leave a pulser running with no close
#                 event; the next tool starting signals the user un-blocked us.
#   PostToolUse — the instant a tool finishes (incl. AskUserQuestion) the user
#                 has answered, so stop pulsing before Claude's next — possibly
#                 long — thinking. Current Claude Code never fires the
#                 Notification close-events, so this is the reliable cleanup.

# shellcheck source=lib.sh
source ~/.claude/notify/lib.sh

INPUT=$(cat)
SID=$(read_session_id "$INPUT")
TTY=$(resolve_tty)

kill_pulser "$SID"
[ -n "$TTY" ] && [ -e "$TTY" ] && clear_tab_color "$TTY"
exit 0
