#!/bin/bash
# Installer for claude-needs-input.
# Idempotent — re-running is safe. Backs up settings.json before merging hook entries.

set -e

REPO_RAW="https://raw.githubusercontent.com/rickardstureborg/claude-needs-input/main"
CLAUDE_DIR="$HOME/.claude"
NOTIFY_DIR="$CLAUDE_DIR/notify"
SETTINGS="$CLAUDE_DIR/settings.json"

red()    { printf '\033[0;31m%s\033[0m\n' "$*"; }
green()  { printf '\033[0;32m%s\033[0m\n' "$*"; }
yellow() { printf '\033[0;33m%s\033[0m\n' "$*"; }
dim()    { printf '\033[2m%s\033[0m\n' "$*"; }

echo ""
echo "claude-needs-input installer"
dim "----------------------------"

# --- Pre-flight checks --------------------------------------------------------

if [ "$(uname)" != "Darwin" ]; then
    red "ERROR: macOS only (you are on $(uname)). The OSC tab-color escapes are iTerm2-specific."
    exit 1
fi

if [ ! -d "$CLAUDE_DIR" ]; then
    red "ERROR: $CLAUDE_DIR does not exist. Install Claude Code first: https://claude.com/code"
    exit 1
fi

if ! command -v claude >/dev/null 2>&1; then
    yellow "WARN: 'claude' CLI not found on PATH. The classifier will fail silently until it is."
fi

if ! command -v python3 >/dev/null 2>&1; then
    red "ERROR: python3 not found. (Should ship with macOS — try \`xcode-select --install\`.)"
    exit 1
fi

if ! command -v perl >/dev/null 2>&1; then
    red "ERROR: perl not found. (Should ship with macOS.)"
    exit 1
fi

if [ -f "$SETTINGS" ]; then
    if ! python3 -c "import json,sys; json.load(open('$SETTINGS'))" 2>/dev/null; then
        red "ERROR: $SETTINGS is not valid JSON. Fix it before installing."
        exit 1
    fi
fi

# --- Source resolution: local checkout vs. piped curl -------------------------

# If running from a local checkout (sibling dirs `scripts/`), copy from there.
# Otherwise download from the repo at $REPO_RAW.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || echo "")"
if [ -n "$SCRIPT_DIR" ] && [ -d "$SCRIPT_DIR/scripts/notify" ]; then
    SOURCE_MODE="local"
    SOURCE_BASE="$SCRIPT_DIR"
    dim "Source: local checkout at $SCRIPT_DIR"
else
    SOURCE_MODE="remote"
    SOURCE_BASE="$REPO_RAW"
    dim "Source: $REPO_RAW"
fi

fetch_to() {
    local rel=$1 dest=$2
    if [ "$SOURCE_MODE" = "local" ]; then
        cp "$SOURCE_BASE/$rel" "$dest"
    else
        curl -fsSL "$SOURCE_BASE/$rel" -o "$dest"
    fi
}

# --- Install scripts ----------------------------------------------------------

mkdir -p "$NOTIFY_DIR"

fetch_to "scripts/notify/lib.sh"             "$NOTIFY_DIR/lib.sh"
fetch_to "scripts/notify/pulse.sh"           "$NOTIFY_DIR/pulse.sh"
fetch_to "scripts/notify/on-notification.sh" "$NOTIFY_DIR/on-notification.sh"
fetch_to "scripts/notify/on-prompt.sh"       "$NOTIFY_DIR/on-prompt.sh"
fetch_to "scripts/notify/on-stop.sh"         "$NOTIFY_DIR/on-stop.sh"
fetch_to "scripts/notify/on-tool-use.sh"     "$NOTIFY_DIR/on-tool-use.sh"
fetch_to "scripts/notify/dismiss.sh"         "$NOTIFY_DIR/dismiss.sh"
fetch_to "scripts/notify-input-needed.sh"    "$CLAUDE_DIR/notify-input-needed.sh"

chmod +x "$NOTIFY_DIR"/*.sh "$CLAUDE_DIR/notify-input-needed.sh"

green "✓ scripts installed under $NOTIFY_DIR/ and $CLAUDE_DIR/notify-input-needed.sh"

# --- Merge hook entries into settings.json ------------------------------------

BACKUP="${SETTINGS}.bak.$(date +%s)"
if [ -f "$SETTINGS" ]; then
    cp "$SETTINGS" "$BACKUP"
    dim "Backup: $BACKUP"
else
    echo '{}' > "$SETTINGS"
    dim "Created empty $SETTINGS"
fi

python3 - "$SETTINGS" <<'PY'
import json, sys, pathlib

p = pathlib.Path(sys.argv[1])
data = json.loads(p.read_text())
hooks = data.setdefault("hooks", {})

REGISTRATIONS = [
    ("Notification",     "bash ~/.claude/notify/on-notification.sh"),
    ("UserPromptSubmit", "bash ~/.claude/notify/on-prompt.sh"),
    ("PreToolUse",       "bash ~/.claude/notify/on-tool-use.sh"),
    ("PostToolUse",      "bash ~/.claude/notify/on-tool-use.sh"),
    ("Stop",             "bash ~/.claude/notify-input-needed.sh"),
]

added, skipped = [], []
for event, cmd in REGISTRATIONS:
    entries = hooks.setdefault(event, [])
    already = any(
        h.get("command") == cmd
        for entry in entries
        for h in entry.get("hooks", [])
    )
    if already:
        skipped.append((event, cmd))
        continue
    entries.append({"hooks": [{"type": "command", "command": cmd}]})
    added.append((event, cmd))

p.write_text(json.dumps(data, indent=2) + "\n")

for event, cmd in added:
    print(f"  + {event}: {cmd}")
for event, cmd in skipped:
    print(f"  = {event}: {cmd}  (already present, skipped)")
PY

green "✓ hooks merged into $SETTINGS"

# --- Done ---------------------------------------------------------------------

echo ""
green "Install complete."
echo ""
dim "Restart Claude Code (or open /hooks) for the new hooks to load."
echo ""
echo "Behavior:"
echo "  • Tab pulses orange when Claude is asking AskUserQuestion or a permission prompt"
echo "  • Tab pulses orange when Claude ends a turn with a real blocking question"
echo "  • Tab is solid green when Claude finishes a turn cleanly"
echo "  • Tab clears to default when you submit a new prompt"
echo ""
echo "Optional — stop a pulse on demand with a keyboard shortcut:"
echo "  In iTerm2 → Settings → Keys → Key Bindings → +, add a binding:"
echo "    • Shortcut:  Option-Command-Delete  (or any key you prefer)"
echo "    • Action:    Run Coprocess"
echo "    • Command:   bash ~/.claude/notify/dismiss.sh"
dim "  Stops the pulse and resets the tab color. Details in the README"
dim "  section \"Stop the pulse yourself\"."
echo ""
dim "To uninstall:  bash <(curl -fsSL $REPO_RAW/uninstall.sh)"
echo ""
