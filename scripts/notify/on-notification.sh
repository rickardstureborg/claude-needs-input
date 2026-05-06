#!/bin/bash
# Notification hook — dispatch by notification subtype.
#   open  (elicitation_dialog | permission_prompt | idle_prompt) -> start orange pulse
#   close (elicitation_response | elicitation_complete | auth_success) -> kill pulse, clear tab
# We grep the raw JSON for the literal subtype because the field name has shifted
# between Claude Code versions; the payload log below lets us re-tune if needed.

source "$(dirname "$0")/lib.sh"

INPUT=$(cat)

# Latest-payload log for schema debugging — overwritten each event, never read by the hook.
echo "$INPUT" > /tmp/claude-notification-payload.json

SID=$(read_session_id "$INPUT")
TTY=$(resolve_tty)

# Append-only log of every notification subtype seen, for debugging missing close events.
NTYPE=$(echo "$INPUT" | python3 -c 'import json,sys; print(json.loads(sys.stdin.read()).get("notification_type",""))' 2>/dev/null)
echo "$(date '+%H:%M:%S') | type=$NTYPE | sid=$SID" >> /tmp/claude-notification-events.log

# Idle-timer escalations are intentionally suppressed — too noisy.
echo "$INPUT" | grep -q '"notification_type":"idle_prompt"' && exit 0

# Close events: known names plus common variations. The grep matches the raw JSON
# because the exact field path has shifted between Claude Code versions. Add new
# event names here as they're discovered via /tmp/claude-notification-events.log.
is_close=0
echo "$INPUT" | grep -qE 'elicitation_response|elicitation_complete|elicitation_completed|elicitation_dismissed|elicitation_resolved|permission_response|permission_decision|permission_resolved|permission_granted|permission_denied|auth_success' && is_close=1

if [ "$is_close" -eq 1 ]; then
    kill_pulser "$SID"
    [ -n "$TTY" ] && [ -e "$TTY" ] && clear_tab_color "$TTY"
    exit 0
fi

# Open path: start pulser if not already running.
PF=$(pulse_pidfile "$SID")
if [ -f "$PF" ] && kill -0 "$(cat "$PF" 2>/dev/null)" 2>/dev/null; then
    exit 0
fi

nohup bash "$(dirname "$0")/pulse.sh" "$SID" "$TTY" >/dev/null 2>&1 &
disown
exit 0
