#!/bin/bash
# User-invoked kill switch — stop the orange pulse and reset the tab color.
#
# Bind it to an iTerm2 key: Settings → Keys → Key Bindings → +, pick a shortcut,
# set Action to "Run Coprocess", and set the command to exactly:
#     bash ~/.claude/notify/dismiss.sh
#
# A coprocess has no tty of its own and can't tell which tab triggered it, so it
# resets every tab the tool has tinted (pulsing OR solid) and stops every pulser.
# Run instead from Claude Code's `!` prefix and it resolves the current tty and
# resets just that tab. An explicit tty path may also be passed as $1.
#
# Once a pulser is dead nothing overwrites that tab color, so a color you set
# yourself afterwards (e.g. iTerm2's right-click tab menu) stays put.

# shellcheck source=lib.sh
source ~/.claude/notify/lib.sh

# Use an explicitly-passed tty if it's a real device; otherwise try resolve_tty
# (works from the `!` prefix, where we're a child of Claude Code). A coprocess
# has neither — fall through to resetting every tinted tab.
TTY=${1:-}
if [ -z "$TTY" ] || [ ! -e "$TTY" ]; then
  TTY=$(resolve_tty)
fi

if [ -n "$TTY" ] && [ -e "$TTY" ]; then
  kill_pulser_by_tty "$TTY"
  clear_tab_color "$TTY"
else
  dismiss_all
fi
exit 0
