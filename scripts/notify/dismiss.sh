#!/bin/bash
# User-invoked kill switch — clear THIS tab's color and stop its pulse.
# Only ever touches one tab; if it can't identify the tab it does nothing.
#
# Bind it to an iTerm2 key (Settings → Keys → Key Bindings), Action
# "Run Coprocess", with the command:
#     bash ~/.claude/notify/dismiss.sh
#
# A coprocess has no tty of its own, but iTerm2 gives it ITERM_SESSION_ID. The
# in-session hooks record that id -> tty (see lib.sh resolve_tty), so we look up
# exactly which tab launched us. Run from Claude Code's `!` prefix it resolves
# the tty directly; an explicit tty path may also be passed as $1.

# shellcheck source=lib.sh
source ~/.claude/notify/lib.sh

TTY=${1:-}
if [ -z "$TTY" ] || [ ! -e "$TTY" ]; then
  TTY=$(resolve_tty)
fi
# Coprocess path: no tty of our own — look it up by ITERM_SESSION_ID.
if [ -z "$TTY" ] || [ ! -e "$TTY" ]; then
  [ -n "${ITERM_SESSION_ID:-}" ] &&
    TTY=$(head -1 "/tmp/claude-iterm-${ITERM_SESSION_ID#*:}" 2>/dev/null)
fi

if [ -n "$TTY" ] && [ -e "$TTY" ]; then
  kill_pulser_by_tty "$TTY"
  clear_tab_color "$TTY"
fi
exit 0
