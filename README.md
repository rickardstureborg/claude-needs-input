# claude-needs-input

Make your iTerm2 tab **pulse orange** when Claude Code is waiting on you, and **turn green** when it's done. Stop babysitting the terminal.

![demo](docs/demo.gif)

> **Status:** macOS + iTerm2 + Claude Code only. Works with the user's existing OAuth — no API key required.

## Install

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/rickardstureborg/claude-needs-input/main/install.sh)
```

Then restart Claude Code (or open `/hooks`) so the new hooks load.

## What it does

| Tab state | When |
|---|---|
| 🟧 **pulsing orange** | Claude is asking via `AskUserQuestion`, a permission prompt, OR ended a turn with a real blocking question |
| 🟩 **solid green** | Claude finished a turn cleanly |
| ⬜ **default (no tint)** | You just submitted a new prompt; Claude is working |

The tricky part — and the reason this isn't just regex — is distinguishing a *real* blocking question (`"Which file should I edit?"`) from a *closing pleasantry* (`"Anything else I can help with?"`). A small Haiku call classifies the turn-ending message; turns that contain no `?` skip the call entirely (fast path).

## Requirements

- [x] macOS (for the iTerm2 OSC tab-color escapes)
- [x] [iTerm2](https://iterm2.com/) as your terminal
- [x] [Claude Code](https://claude.com/code) installed (`claude` on PATH)
- [x] Python 3 (ships with macOS)
- [x] Perl (ships with macOS)

No `ANTHROPIC_API_KEY` needed — the classifier piggybacks on your existing Claude Code OAuth.

## How it works

A few Claude Code hooks, all installed under `~/.claude/`:

```
~/.claude/
├── notify-input-needed.sh         # Stop hook: classifies turn → green or orange
└── notify/
    ├── lib.sh                     # color helpers + tty resolver
    ├── pulse.sh                   # background pulser daemon
    ├── on-notification.sh         # Notification hook: dispatch by subtype
    ├── on-prompt.sh               # UserPromptSubmit hook: clear color
    ├── on-tool-use.sh             # Pre/PostToolUse hook: stop pulse around tool calls
    ├── on-stop.sh                 # (optional) unconditional green on Stop
    └── dismiss.sh                 # manual kill switch (bind to an iTerm2 key)
```

End-of-turn classification flow:

```
Stop event
  ├─ no transcript / AskUserQuestion was used / empty text  →  GREEN
  ├─ message contains no "?"                                →  GREEN  (fast path, ~0s)
  └─ message contains "?"                                   →  call Haiku
                                                                 ├─ BLOCKING → orange pulse
                                                                 └─ CLOSING  → GREEN
```

The classifier call uses `claude -p --model haiku --no-session-persistence` and inherits a `CLAUDE_CLASSIFIER_RUNNING=1` env var to short-circuit its own Stop hook (no recursion, no API key).

## Stop the pulse yourself

Seen the orange, but not ready to answer yet? `dismiss.sh` clears the current
tab's color and stops its pulse — leaving every other tab alone, whatever color
they're showing. Once the pulser is dead nothing overwrites the tab color, so a
color you set yourself afterwards (e.g. iTerm2's right-click **tab color** menu)
stays put.

Bind it to an iTerm2 key:

1. **iTerm2 → Settings → Keys → Key Bindings → `+`**
2. Press the shortcut you want — e.g. **⌥⌘⌫** (Option-Command-Delete).
3. Set **Action** to `Run Coprocess`.
4. Set the command to exactly:

   ```
   bash ~/.claude/notify/dismiss.sh
   ```

It runs as a coprocess with no terminal of its own, but iTerm2 hands it
`ITERM_SESSION_ID`. The in-session hooks record that id against the tab's tty
(see `resolve_tty` in `lib.sh`), so `dismiss.sh` resolves exactly which tab
launched it — and touches only that one, even mid-`AskUserQuestion` or during a
permission prompt.

You can also run it from Claude Code's `!` prefix:

```
! ~/.claude/notify/dismiss.sh
```

## Customization

All knobs live in the installed scripts under `~/.claude/notify/` — edit in place.

**Pulse color or speed.** Edit `~/.claude/notify/pulse.sh`:
```bash
RAMP_R=(255 245 230 215 205 195 205 215 230 245)  # red channel ramp
RAMP_G=(140 135 125 115 108 100 108 115 125 135)  # green channel ramp
# ...
sleep 0.32                                         # frame delay
```

**Done-turn color.** Edit `~/.claude/notify-input-needed.sh`, find:
```bash
set_tab_rgb "$TTY" 40 200 80   # solid green (R,G,B)
```

**Skip the LLM, fast-path everything.** Edit `~/.claude/notify-input-needed.sh` and replace the `claude -p` block with `LLM_VERDICT=CLOSING`. You'll lose blocker-detection on `?`-ending turns but every classification becomes instant.

**Faster classification.** If you have an `ANTHROPIC_API_KEY` and want the classifier to run in ~1s instead of ~4s, change the `claude -p` invocation in `~/.claude/notify-input-needed.sh` to add `--bare`:
```bash
LLM_VERDICT=$(... claude -p "$PROMPT" --model haiku --no-session-persistence --bare ...)
```

## Uninstall

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/rickardstureborg/claude-needs-input/main/uninstall.sh)
```

Removes the hook entries from `settings.json` (with timestamped backup) and deletes the installed scripts. Your other Claude Code hooks are untouched.

## License

MIT — see [`LICENSE`](LICENSE).
