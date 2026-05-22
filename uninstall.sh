#!/bin/bash
# Uninstaller for claude-needs-input.
# Removes hook entries from settings.json (with backup) and deletes the installed scripts.

set -e

CLAUDE_DIR="$HOME/.claude"
NOTIFY_DIR="$CLAUDE_DIR/notify"
SETTINGS="$CLAUDE_DIR/settings.json"

red()   { printf '\033[0;31m%s\033[0m\n' "$*"; }
green() { printf '\033[0;32m%s\033[0m\n' "$*"; }
dim()   { printf '\033[2m%s\033[0m\n' "$*"; }

echo ""
echo "claude-needs-input uninstaller"
dim "------------------------------"

# Kill any running pulsers.
for pf in /tmp/claude-pulse-*.pid; do
    [ -f "$pf" ] || continue
    pid=$(head -1 "$pf" 2>/dev/null)   # line 1 = PID (line 2 = tty)
    [ -n "$pid" ] && kill "$pid" 2>/dev/null || true
    rm -f "$pf"
done

# Strip hook entries pointing at our scripts.
if [ -f "$SETTINGS" ]; then
    BACKUP="${SETTINGS}.bak.$(date +%s)"
    cp "$SETTINGS" "$BACKUP"
    python3 - "$SETTINGS" <<'PY'
import json, sys, pathlib
p = pathlib.Path(sys.argv[1])
data = json.loads(p.read_text())
hooks = data.get("hooks", {})

OUR_PATHS = ("/.claude/notify/", "/.claude/notify-input-needed.sh")

for event in list(hooks.keys()):
    new_entries = []
    for entry in hooks.get(event, []):
        kept = [h for h in entry.get("hooks", [])
                if not any(p in h.get("command", "") for p in OUR_PATHS)]
        if kept:
            entry["hooks"] = kept
            new_entries.append(entry)
    if new_entries:
        hooks[event] = new_entries
    else:
        del hooks[event]

if not hooks:
    data.pop("hooks", None)
else:
    data["hooks"] = hooks

p.write_text(json.dumps(data, indent=2) + "\n")
PY
    green "✓ hook entries removed from $SETTINGS"
    dim "Backup: $BACKUP"
fi

# Remove installed scripts.
rm -f "$CLAUDE_DIR/notify-input-needed.sh"
rm -rf "$NOTIFY_DIR"
green "✓ scripts removed from $CLAUDE_DIR"

# Clean up temp files.
rm -f /tmp/claude-notify-input-needed.log /tmp/claude-notification-payload.json
rm -f /tmp/claude-stop-notified-* /tmp/claude-iterm-* /tmp/claude-dismiss.log

echo ""
green "Uninstall complete."
echo ""
