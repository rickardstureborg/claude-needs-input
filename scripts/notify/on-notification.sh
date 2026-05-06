#!/bin/bash
# Notification hook — dispatch by notification subtype.
#   open  (elicitation_dialog | permission_prompt) -> start orange pulse
#   close (elicitation_response | elicitation_complete | auth_success) -> kill pulse, clear tab
#   idle_prompt -> intentional no-op (the idle escalation is too noisy to flash for)
# We grep the raw JSON for the literal subtype because the field name has shifted
# between Claude Code versions; the payload log below lets us re-tune if needed.

source "$(dirname "$0")/lib.sh"

INPUT=$(cat)

# Latest-payload log for schema debugging — overwritten each event, never read by the hook.
echo "$INPUT" > /tmp/claude-notification-payload.json

SID=$(read_session_id "$INPUT")
TTY=$(resolve_tty)

# idle_prompt is suppressed: don't start, don't clear an in-flight pulse.
echo "$INPUT" | grep -q '"notification_type":"idle_prompt"' && exit 0

is_close=0
echo "$INPUT" | grep -qE 'elicitation_response|elicitation_complete|auth_success' && is_close=1

if [ "$is_close" -eq 1 ]; then
    kill_pulser "$SID"
    [ -n "$TTY" ] && [ -e "$TTY" ] && clear_tab_color "$TTY"
    exit 0
fi

PF=$(pulse_pidfile "$SID")
if [ -f "$PF" ] && kill -0 "$(cat "$PF" 2>/dev/null)" 2>/dev/null; then
    exit 0
fi

nohup bash "$(dirname "$0")/pulse.sh" "$SID" "$TTY" >/dev/null 2>&1 &
disown
exit 0
