#!/bin/bash
# Stop hook — sets end-of-turn tab color based on whether Claude is waiting on user input.
#   BLOCKING (LLM verdict)                          -> orange pulse
#   CLOSING / no '?' fast-path / AskUserQuestion    -> solid green
# CRITICAL: must produce zero stdout — anything printed gets injected into the conversation.

# Recursion guard: this hook spawns `claude -p` to classify. The child inherits the env
# var, so its own Stop hook short-circuits here — no infinite recursion, no API key needed.
[ -n "$CLAUDE_CLASSIFIER_RUNNING" ] && exit 0

INPUT=$(cat)
LOG="/tmp/claude-notify-input-needed.log"

source ~/.claude/notify/lib.sh

json_string() { echo "$INPUT" | grep -o "\"$1\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | head -1 | sed 's/.*:[[:space:]]*"\([^"]*\)"/\1/'; }
TRANSCRIPT=$(json_string "transcript_path")
SESSION_ID=$(json_string "session_id")
TTY=$(resolve_tty)

# Apply the chosen end-of-turn color. Always kills any in-flight pulser first
# (e.g. an unfinished AskUserQuestion pulse) so we start from a clean slate.
apply_color() {
    local verdict=$1
    kill_pulser "$SESSION_ID"
    [ -z "$TTY" ] || [ ! -e "$TTY" ] && return
    if [ "$verdict" = "BLOCKING" ]; then
        nohup bash ~/.claude/notify/pulse.sh "$SESSION_ID" "$TTY" >/dev/null 2>&1 &
        disown
    else
        set_tab_rgb "$TTY" 40 200 80
    fi
}

if [ -z "$TRANSCRIPT" ] || [ ! -f "$TRANSCRIPT" ]; then
    apply_color CLOSING
    exit 0
fi

# Returns "SKIP" (AskUserQuestion used in this turn — Notification hook owns the tab)
# or "TEXT\n<last assistant text>".
RESULT=$(python3 - "$TRANSCRIPT" 2>>"$LOG" <<'PY'
import json, sys
entries = []
with open(sys.argv[1]) as f:
    for line in f:
        line = line.strip()
        if not line: continue
        try: entries.append(json.loads(line))
        except: pass

# Walk back through this turn — i.e. since the last *real* user prompt.
# Tool-result entries are also type=user but their content is a list of tool_result
# blocks, not a plain string; they're mid-turn artifacts and shouldn't end the walk.
asst = []
for e in reversed(entries):
    if e.get("type") == "user":
        c = e.get("message", {}).get("content")
        if isinstance(c, str):
            break
    elif e.get("type") == "assistant":
        asst.append(e)
if not asst:
    sys.exit(0)

# AskUserQuestion check spans the whole turn, not just the last message —
# the elicitation can fire mid-turn and the model may continue past it.
for e in asst:
    for c in e.get("message", {}).get("content", []):
        if c.get("type") == "tool_use" and c.get("name") == "AskUserQuestion":
            print("SKIP")
            sys.exit(0)

texts = [c.get("text","") for c in asst[0].get("message",{}).get("content",[]) if c.get("type")=="text"]
print("TEXT")
print("\n".join(texts))
PY
)

PARSE_HEADER=$(echo "$RESULT" | head -1)

if [ "$PARSE_HEADER" != "TEXT" ]; then
    apply_color CLOSING
    exit 0
fi

TEXT=$(echo "$RESULT" | tail -n +2)
if [ -z "$TEXT" ]; then
    apply_color CLOSING
    exit 0
fi

# Fast-path: no '?' anywhere → trivially CLOSING. Saves the ~4s LLM call on the common case.
case "$TEXT" in
    *"?"*) ;;
    *)
        echo "$(date '+%Y-%m-%d %H:%M:%S') | session=$SESSION_ID | verdict=CLOSING (fast-path no ?)" >> "$LOG"
        apply_color CLOSING
        exit 0
        ;;
esac

PROMPT="You are classifying the final message of an AI coding assistant's turn into one of two categories:

BLOCKING — the assistant has paused mid-task and genuinely needs the user's input or decision before it can continue working on the assigned task. Without an answer, the assigned work cannot proceed.

CLOSING — the assistant has finished the work it was assigned (or as much as it can do without further direction) and is signing off. Any question present is a polite offer for follow-up work, not a blocker.

Distinguishing principle: ask \"if the user said nothing, would the originally-assigned task be left half-done?\" If yes → BLOCKING. If no → CLOSING.

BLOCKING examples:
- \"I found two files matching config.ts. Which one should I edit?\"
- \"Should I delete the old migration or keep it as a backup before I run the new one?\"
- \"Three approaches come to mind — quick patch, refactor, or rewrite. Which do you want?\"
- \"I need your AWS profile name to continue the deploy. What is it?\"
- \"The tests fail in two different ways. Want me to fix the type errors first or the logic bug first?\"

CLOSING examples (questions present but NOT blocking):
- \"Done. Anything else I can help with?\"
- \"Tests pass and the PR is up. Want me to do anything else?\"
- \"Pushed to main. Does that look good?\"
- \"Ready to ship. Let me know if you'd like changes.\"
- \"Refactor complete — let me know what you think.\"

Edge cases:
- A message with BOTH a genuine blocker AND a closing pleasantry is BLOCKING (the blocker dominates).
- \"Should I commit?\" after completing the work IS blocking — the assistant is mid-workflow waiting for permission to proceed.
- \"Want me to also add tests?\" after completing the assigned work is CLOSING — tests weren't part of the assignment.

The message to classify:
<message>
$TEXT
</message>

Reply with exactly one word: BLOCKING or CLOSING. No explanation, no punctuation."

# perl alarm replaces `timeout` — coreutils isn't on macOS by default.
LLM_VERDICT=$(CLAUDE_CLASSIFIER_RUNNING=1 perl -e 'alarm shift @ARGV; exec @ARGV' 20 claude -p "$PROMPT" --model haiku --no-session-persistence 2>>"$LOG" | tr -d '[:space:]' | head -c 20)

echo "$(date '+%Y-%m-%d %H:%M:%S') | session=$SESSION_ID | verdict=$LLM_VERDICT" >> "$LOG"

if [ "$LLM_VERDICT" = "BLOCKING" ]; then
    apply_color BLOCKING
else
    apply_color CLOSING
fi
exit 0
