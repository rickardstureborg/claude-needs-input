#!/bin/bash
# User-invoked kill switch — clear THIS tab's color and stop its pulse.
# Only ever touches one tab.
#
# Bind an iTerm2 key (Settings → Keys → Key Bindings) with Action "Run Coprocess"
# and the command exactly:  bash ~/.claude/notify/dismiss.sh
#
# A coprocess has no tty of its own, but iTerm2 gives it ITERM_SESSION_ID. The
# in-session hooks record that id -> tty (see resolve_tty in lib.sh), so we look
# up exactly which tab launched us. Also works from Claude Code's `!` prefix.

# shellcheck source=lib.sh
source ~/.claude/notify/lib.sh

[ -n "${ITERM_SESSION_ID:-}" ] || exit 0
TTY=$(head -1 "/tmp/claude-iterm-${ITERM_SESSION_ID#*:}" 2>/dev/null)

if [ -n "$TTY" ] && [ -e "$TTY" ]; then
  kill_pulser_by_tty "$TTY"
  clear_tab_color "$TTY"
fi
exit 0
