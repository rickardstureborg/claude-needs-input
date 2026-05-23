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

# Trace every fire and where it exits, to debug real-flow branching.
trace() { echo "$(date '+%H:%M:%S') | $*" >> "$LOG"; }
trace "fired | input_len=${#INPUT}"

# Reuse the color helpers + tty resolver that drive the AskUserQuestion pulse.
# shellcheck source=scripts/notify/lib.sh
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
        set_tab_rgb "$TTY" 40 200 80   # solid green
    fi
}

# No transcript → can't classify, but still settle the tab to "done" green.
trace "transcript=$TRANSCRIPT exists=$([ -f "$TRANSCRIPT" ] && echo y || echo n)"

if [ -z "$TRANSCRIPT" ] || [ ! -f "$TRANSCRIPT" ]; then
    trace "exit: no transcript -> CLOSING"
    apply_color CLOSING
    exit 0
fi

# Walk the transcript. The Stop hook can fire before Claude Code has flushed the
# assistant's closing message to disk; walk_transcript then returns empty
# (parse_header empty) and the caller retries with backoff for the writer.
walk_transcript() {
    python3 - "$TRANSCRIPT" 2>>"$LOG" <<'PY'
import json, sys
entries = []
with open(sys.argv[1]) as f:
    for line in f:
        line = line.strip()
        if not line: continue
        try: entries.append(json.loads(line))
        except: pass

# Claude Code appends bookkeeping entries (last-prompt, ai-title, pr-link,
# file-history-snapshot, attachment, summary, ...) to the transcript AFTER the
# assistant's closing message — so the literal last line is normally metadata,
# not conversation. Judge completeness, and walk the turn, from conversation
# entries (type user/assistant) only.
msgs = [e for e in entries if e.get("type") in ("user", "assistant")]

# The Stop hook can fire before Claude Code has flushed the assistant's closing
# message. A turn-final assistant entry has text and no trailing tool call
# (AskUserQuestion is itself a turn-ender). If the last conversation entry isn't
# yet such an entry, the closing text isn't on disk — exit empty to signal a
# retry, rather than grading a stale earlier line (e.g. a text -> tool -> text
# turn where only the pre-tool text has been written).
def _is_final(e):
    if not e or e.get("type") != "assistant":
        return False
    content = e.get("message", {}).get("content", [])
    has_text = any(c.get("type") == "text" for c in content)
    tool_uses = [c for c in content if c.get("type") == "tool_use"]
    has_auq = any(c.get("name") == "AskUserQuestion" for c in tool_uses)
    return has_auq or (has_text and not tool_uses)

if msgs and not _is_final(msgs[-1]):
    sys.exit(0)

# Walk back through this turn — i.e. since the last *real* user prompt.
# Tool-result entries are also type=user but their content is a list of tool_result
# blocks, not a plain string; they're mid-turn artifacts and shouldn't end the walk.
asst = []
for e in reversed(msgs):
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

# asst is reverse-chronological. The LAST assistant entry can be pure tool_use (no
# text), so walk until we find the most recent entry that actually contains text.
texts = []
for entry in asst:
    found = [c.get("text","") for c in entry.get("message",{}).get("content",[]) if c.get("type")=="text"]
    if found:
        texts = found
        break
print("TEXT")
print("\n".join(texts))
PY
}

# Retry the walk a few times to defeat the transcript-flush race. Empty parse_header
# means walk_transcript saw an incomplete transcript — no assistant entry yet, or
# the closing text not flushed past the last tool call. Most calls succeed on
# attempt 1 (no added latency).
RESULT=""
PARSE_HEADER=""
for attempt in 1 2 3 4 5; do
    RESULT=$(walk_transcript)
    PARSE_HEADER=$(echo "$RESULT" | head -1)
    if [ -n "$PARSE_HEADER" ]; then
        [ "$attempt" -gt 1 ] && trace "walk succeeded on attempt $attempt"
        break
    fi
    trace "attempt=$attempt incomplete transcript, sleeping 0.3s"
    sleep 0.3
done

trace "parse_header=$PARSE_HEADER result_lines=$(echo "$RESULT" | wc -l | tr -d ' ')"

if [ "$PARSE_HEADER" != "TEXT" ]; then
    trace "exit: parse_header=$PARSE_HEADER (SKIP / parse failed after retries) -> CLOSING"
    apply_color CLOSING
    exit 0
fi

TEXT=$(echo "$RESULT" | tail -n +2)
trace "text_len=${#TEXT} text_tail_80=${TEXT: -80}"
if [ -z "$TEXT" ]; then
    trace "exit: empty text -> CLOSING"
    apply_color CLOSING
    exit 0
fi

# Fast-path: skip the ~4s Haiku call unless the final message looks like it
# might be handing a decision back to the user. A literal "?" or any of these
# input-soliciting phrases (case-insensitive, anywhere in the message) sends it
# to the classifier; anything else is trivially CLOSING.
# A plain multi-line string — NOT a here-doc: this hook runs under /bin/bash,
# which on macOS is 3.2, and bash 3.2 can't parse a here-doc nested in $(...).
TRIGGERS="?
up to you
your call
you decide
your decision
your preference
your input
your thoughts
your approval
let me know
tell me
need your
need you to
i'll wait
waiting for you
want me to
should i
shall i
confirm
go ahead
would you like
how would you
what do you think
option
options
decide
decision
choose
choice
prefer
proceed"
if grep -iqF -- "$TRIGGERS" <<< "$TEXT"; then
    trace "trigger matched -> calling LLM"
else
    trace "exit: no trigger -> CLOSING"
    apply_color CLOSING
    exit 0
fi

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

# Force a known session-id so we can delete the stub `.jsonl` Claude Code still
# writes despite --no-session-persistence (otherwise these clog /resume).
CLASSIFIER_SID=$(uuidgen | tr '[:upper:]' '[:lower:]')

# perl alarm replaces `timeout` — coreutils isn't on macOS by default.
LLM_VERDICT=$(CLAUDE_CLASSIFIER_RUNNING=1 perl -e 'alarm shift @ARGV; exec @ARGV' 20 claude -p "$PROMPT" --model haiku --no-session-persistence --session-id "$CLASSIFIER_SID" 2>>"$LOG" | tr -d '[:space:]' | head -c 20)

rm -f "$HOME"/.claude/projects/*/"$CLASSIFIER_SID".jsonl

echo "$(date '+%Y-%m-%d %H:%M:%S') | session=$SESSION_ID | verdict=$LLM_VERDICT" >> "$LOG"

if [ "$LLM_VERDICT" = "BLOCKING" ]; then
    apply_color BLOCKING
else
    apply_color CLOSING
fi
exit 0
