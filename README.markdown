# Claude Code Notifier (terminal-notifier fork)

A Claude-branded fork of [`terminal-notifier`](https://github.com/julienXX/terminal-notifier) for sending **macOS notifications from [Claude Code](https://docs.claude.com/en/docs/claude-code/) hooks** with **click-to-jump-back-to-tmux-pane** behavior.

When Claude finishes a task or needs your input, you get a native macOS notification with the Claude icon, the actual task content, and a single click takes you straight back to the tmux pane where that Claude session lives.

```
┌───────────────────────────────────────────────────────────────┐
│ ✦  Claude Code — Done                                         │
│    refactor auth middleware to use new session token storage  │
└───────────────────────────────────────────────────────────────┘
        ↑ click → switch to tmux session:window.pane in Alacritty
```

---

## What this fork changes vs. upstream

| Property | Upstream `terminal-notifier` | This fork |
|---|---|---|
| `CFBundleIdentifier` | `fr.julienxx.oss.terminal-notifier` | `com.anthropic.claudecode-notifier` |
| `CFBundleName` / `CFBundleDisplayName` | `terminal-notifier` | `Claude Code` |
| App icon (`Terminal.icns`) | macOS terminal icon | Claude logo |
| CLI executable name | `terminal-notifier` | `terminal-notifier` (unchanged — drop-in replacement) |
| Source code | (no changes) | (no changes) |

Renaming the bundle ID is the important part: macOS treats this as a separate app in *System Settings → Notifications*, so you can grant notification permission to **Claude Code** without affecting any other `terminal-notifier` install.

---

## Why click-handlers needed a custom binary

The default Claude Code Notification hook uses `osascript -e 'display notification ...'`, which on macOS has **no click handler** — clicks open the Script Editor instead of doing something useful. `terminal-notifier`'s `-execute` flag fixes that, but to display notifications under a "Claude Code" identity (with the Claude icon and "Claude Code" header) you need a separately-branded bundle. Hence this fork.

---

## Prerequisites

| Tool | Required for | macOS install |
|---|---|---|
| Xcode + Command Line Tools | Building the bundle | App Store, then `xcode-select --install` |
| [Claude Code](https://docs.claude.com/en/docs/claude-code/) | The whole point | `npm i -g @anthropic-ai/claude-code` |
| `tmux` | Click-to-jump-back-to-pane | `brew install tmux` |
| [Alacritty](https://alacritty.org/) (or any terminal) | Where Claude runs | `brew install --cask alacritty` |
| `jq` | Stop-hook transcript parsing | `brew install jq` |

---

## Build & install

```bash
# 1. Clone this fork
git clone https://github.com/LordHung/terminal-notifier.git ~/code/terminal-notifier
cd ~/code/terminal-notifier

# 2. Build (needs Xcode + Command Line Tools)
xcodebuild \
  -project "Terminal Notifier.xcodeproj" \
  -scheme "Terminal Notifier" \
  -configuration Release \
  MACOSX_DEPLOYMENT_TARGET=10.13 \
  PRODUCT_BUNDLE_IDENTIFIER=com.anthropic.claudecode-notifier \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  build

# 3. Copy the built bundle to a stable location
SRC=$(find ~/Library/Developer/Xcode/DerivedData \
        -name "terminal-notifier.app" -path "*Release*" | head -1)
mkdir -p ~/.claude/hooks
cp -R "$SRC" "$HOME/.claude/hooks/Claude Notifier.app"

# 4. Register with LaunchServices so macOS shows it in Notifications settings
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
  -f "$HOME/.claude/hooks/Claude Notifier.app"

# 5. Smoke-test
"$HOME/.claude/hooks/Claude Notifier.app/Contents/MacOS/terminal-notifier" \
  -title "Claude Code" -message "Install OK"
```

---

## macOS notification permissions (CRITICAL)

This step is the #1 source of "I clicked the notification but nothing happened" — because if notifications are denied, macOS still renders the notification through a **fallback path that has no click handler**. There is no error; clicks just silently no-op.

1. Open **System Settings → Notifications**.
2. Find **Claude Code** in the app list (it appears after step 4 above; you may need to fire one notification first).
3. Set:
   - **Allow notifications:** ON
   - **Alert style:** **Persistent** (not Banner — Banner notifications can dismiss before you click)
   - Show in: Desktop, Notification Center (your choice)

If "Claude Code" is missing from the list, run the smoke-test command from step 5 above to register it.

---

## Claude Code hooks setup

This is the bit that wires the notifier into Claude Code so it fires on the right events with the right content, and clicks navigate back to the originating tmux pane.

### File layout

```
~/.claude/
├── settings.json          # Claude Code hooks configuration
└── hooks/
    ├── Claude Notifier.app/   # the rebuilt bundle (from build step above)
    ├── claude-icon.png        # only used by the homebrew terminal-notifier fallback
    ├── notify.sh              # main notification helper
    ├── click-action.sh        # tmux focus + Alacritty activation on click
    └── stop.sh                # Stop-hook helper that extracts task content
```

### `~/.claude/hooks/notify.sh`

```bash
#!/bin/bash
# Usage: notify.sh <title> <message> [sound_file]
# Reads $TMUX_PANE inherited from the Claude Code process so clicking the
# notification jumps to the originating tmux window/pane in Alacritty.

TITLE="${1:-Claude Code}"
MSG="${2:-Notification}"
SOUND="${3:-}"

[ -n "$SOUND" ] && [ -f "$SOUND" ] && afplay "$SOUND" &

PANE="${TMUX_PANE:-}"
TMUX_BIN="$(command -v tmux)"
ICON="$HOME/.claude/hooks/claude-icon.png"

# Prefer custom-rebuilt notifier (Claude-branded) over homebrew terminal-notifier.
CUSTOM_TN="$HOME/.claude/hooks/Claude Notifier.app/Contents/MacOS/terminal-notifier"
if [ -x "$CUSTOM_TN" ]; then
  TN="$CUSTOM_TN"
else
  TN="$(command -v terminal-notifier)"
fi

if [ -n "$PANE" ] && [ -n "$TN" ] && [ -n "$TMUX_BIN" ]; then
  WINDOW_TARGET="$("$TMUX_BIN" display-message -p -t "$PANE" '#{session_name}:#{window_index}' 2>/dev/null)"
  SESSION="$("$TMUX_BIN" display-message -p -t "$PANE" '#{session_name}' 2>/dev/null)"
  if [ -n "$WINDOW_TARGET" ]; then
    APPICON_FLAG=()
    if [ "$TN" != "$CUSTOM_TN" ] && [ -f "$ICON" ]; then
      APPICON_FLAG=(-appIcon "file://$ICON")
    fi
    "$TN" \
      -title "$TITLE" \
      -message "$MSG" \
      "${APPICON_FLAG[@]}" \
      -execute "$HOME/.claude/hooks/click-action.sh '$PANE' '$WINDOW_TARGET' '$SESSION'" \
      >/dev/null 2>&1
    exit 0
  fi
fi

# Fallback: plain osascript notification (no click handler).
osascript -e "display notification \"${MSG//\"/\\\"}\" with title \"${TITLE//\"/\\\"}\""
```

### `~/.claude/hooks/click-action.sh`

```bash
#!/bin/bash
# Invoked by terminal-notifier -execute when a Claude notification is clicked.
# Args: <pane-id> <window-target> <session-name>
PANE="$1"
WINDOW="$2"
SESSION="$3"

exec >> /tmp/nf-click.log 2>&1
echo "--- click $(date) pane=$PANE window=$WINDOW session=$SESSION ---"

TMUX_BIN="$(command -v tmux || echo /opt/homebrew/bin/tmux)"
"$TMUX_BIN" switch-client -t "$SESSION"
"$TMUX_BIN" select-window -t "$WINDOW"
"$TMUX_BIN" select-pane -t "$PANE"
/usr/bin/open -a Alacritty
```

> Replace `Alacritty` with your terminal app name if different (`Terminal`, `iTerm`, `Ghostty`, `WezTerm`, etc.).

### `~/.claude/hooks/stop.sh`

```bash
#!/bin/bash
# Stop hook: build a notification title from
#   1) the Claude Code session name (set via /rename, lives in
#      ~/.claude/sessions/<pid>.json as `.name`)
#   2) the tmux window name (set via tmux rename-window)
# falling back to git branch / cwd basename if no session name is set.
# Body is the most recent real user prompt from the transcript.

INPUT=$(cat)
TP=$(echo "$INPUT" | jq -r '.transcript_path // empty')
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')
PANE="${TMUX_PANE:-}"

# --- Claude Code session name (set via /rename) ---
SESSION_NAME=""
if [ -n "$SESSION_ID" ]; then
  SESSION_NAME=$(jq -r --arg sid "$SESSION_ID" \
    'select(.sessionId==$sid) | .name // empty' \
    ~/.claude/sessions/*.json 2>/dev/null | head -1)
fi

# --- Fallback to git branch / cwd basename if no session name ---
TASK=""
if [ -n "$SESSION_NAME" ]; then
  TASK="$SESSION_NAME"
elif [ -n "$CWD" ] && [ -d "$CWD" ]; then
  B=$(git -C "$CWD" rev-parse --abbrev-ref HEAD 2>/dev/null)
  if [ -n "$B" ] && [ "$B" != "HEAD" ]; then
    TASK="$B"
  else
    TASK="$(basename "$CWD")"
  fi
fi

# --- tmux window name ---
WINDOW=""
if [ -n "$PANE" ] && command -v tmux >/dev/null 2>&1; then
  WINDOW=$(tmux display-message -p -t "$PANE" '#{window_name}' 2>/dev/null)
fi

# --- compose title ---
if [ -n "$TASK" ] && [ -n "$WINDOW" ]; then
  TITLE="Claude Code — $TASK [$WINDOW]"
elif [ -n "$TASK" ]; then
  TITLE="Claude Code — $TASK"
elif [ -n "$WINDOW" ]; then
  TITLE="Claude Code — $WINDOW"
else
  TITLE="Claude Code — Done"
fi

# --- Body: most recent real user prompt from transcript ---
BODY="Task complete"
if [ -f "$TP" ]; then
  E=$(jq -rs '[.[] | select(.type=="user" and (.message.content|type)=="string" and (.message.content|startswith("<")|not))] | last | .message.content // empty' "$TP" 2>/dev/null \
        | tr '\n' ' ' | tr -s ' ' | sed 's/^ //;s/ $//' | cut -c 1-160)
  [ -n "$E" ] && [ "$E" != "null" ] && BODY="$E"
fi

exec ~/.claude/hooks/notify.sh "$TITLE" "$BODY" /System/Library/Sounds/Ping.aiff
```

The Stop notification title shows, in order of preference:
1. The Claude Code session name (set via `/rename github-issue-airdrop-implementation`)
2. The git branch (when no session name is set)
3. The cwd basename (when not in a git repo)
4. "Done" (last resort)

Plus the tmux window name in `[brackets]` as a suffix when running inside tmux.

Examples:
- `Claude Code — github-issue-airdrop-implementation [airdrop]`
- `Claude Code — claude-code-branding [terminal-notifier]`
- `Claude Code — Done`

### `~/.claude/settings.json` (hooks section)

```json
{
  "hooks": {
    "Notification": [
      {
        "matcher": "permission_prompt",
        "hooks": [
          {
            "type": "command",
            "command": "INPUT=$(cat); MSG=$(echo \"$INPUT\" | jq -r '.notification_message // \"Claude needs your permission\"'); ~/.claude/hooks/notify.sh \"Claude Code — Permission\" \"$MSG\" /System/Library/Sounds/Glass.aiff"
          }
        ]
      },
      {
        "matcher": "idle_prompt",
        "hooks": [
          {
            "type": "command",
            "command": "INPUT=$(cat); MSG=$(echo \"$INPUT\" | jq -r '.notification_message // \"Claude is waiting for your input\"'); ~/.claude/hooks/notify.sh \"Claude Code — Waiting\" \"$MSG\" /System/Library/Sounds/Blow.aiff"
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          { "type": "command", "command": "~/.claude/hooks/stop.sh" }
        ]
      }
    ]
  }
}
```

Don't forget to `chmod +x ~/.claude/hooks/*.sh`.

### Hook coverage

| Hook | Title | Message source | Sound |
|---|---|---|---|
| `Notification` permission_prompt | Claude Code — Permission | `notification_message` from hook | Glass |
| `Notification` idle_prompt | Claude Code — Waiting | `notification_message` from hook | Blow |
| `Stop` | Claude Code — &lt;session/branch&gt; [&lt;tmux-window&gt;] | Latest user prompt (truncated to 160 chars) | Ping |

The `SubagentStop` hook is intentionally omitted — subagent completions are noisy and don't carry useful context for the human (you didn't ask the subagent for anything; Claude did). Add one back via the same pattern if you want it.

---

## How click-to-tmux-pane works

```
┌───────────────────────────────────────────────────────────────┐
│ Claude session running in tmux pane %293 (Alacritty)          │
└───────────────────────────────────────────────────────────────┘
                            │
                  Stop hook fires after Claude responds
                            │
                            ▼
        notify.sh captures $TMUX_PANE = %293
        resolves to session "9", window "9:28"
        bakes into terminal-notifier -execute command:
            click-action.sh '%293' '9:28' '9'
                            │
                            ▼
          terminal-notifier shows native notification
                            │
                  user clicks notification body
                            │
                            ▼
                  click-action.sh runs:
            tmux switch-client -t 9
            tmux select-window -t 9:28
            tmux select-pane -t %293
            open -a Alacritty
                            │
                            ▼
        ┌─────────────────────────────────────────┐
        │ Alacritty foreground, tmux on pane %293 │
        └─────────────────────────────────────────┘
```

**Key insight:** `$TMUX_PANE` is captured **at hook spawn time** (when Claude Code spawns the hook, it inherits the env from the tmux client). The pane ID is then baked into the click command as a string literal, so even though terminal-notifier's click subshell has no `$TMUX` env, it knows exactly which pane to navigate to.

---

## Customization

### Different terminal emulator

Edit `~/.claude/hooks/click-action.sh` and replace `Alacritty` with your terminal app name (e.g., `Terminal`, `iTerm`, `Ghostty`, `WezTerm`). Use the exact name as it appears in `/Applications/`.

### No tmux (single shell)

Skip `click-action.sh` entirely. In `notify.sh`, replace the `-execute` value with just `open -a YourTerminal`. Click will only foreground the terminal — no pane navigation.

### Customize the notifier icon

Replace `Terminal.icns` in this repo with a different `.icns` file (build via `iconutil -c icns YourIcon.iconset`), then rebuild and re-install.

### Per-message icon override

If you want a different icon per notification (without rebuilding), pass `-appIcon "file:///path/to/icon.png"` to `terminal-notifier`. The custom-rebuilt bundle's default icon will be overridden.

---

## Troubleshooting

### "I see notifications but clicks don't navigate"

99% of the time this is the **notification permission gotcha**. Open System Settings → Notifications → Claude Code, and make sure:
- Allow notifications is ON
- Alert style is Persistent

If notifications are off, macOS routes them through a fallback path that has no click handler. You'll see them but clicks silently no-op.

### "I see no notifications at all"

Run the smoke test:
```bash
"$HOME/.claude/hooks/Claude Notifier.app/Contents/MacOS/terminal-notifier" \
  -title "Test" -message "Hello"
```

If you still see nothing, check:
- macOS Focus / Do Not Disturb is off
- LaunchServices recognizes the bundle: `lsregister -dump | grep claudecode-notifier`

### "Click jumps to Alacritty but wrong tmux pane"

Look at `/tmp/nf-click.log` — it logs every click with the pane it tried to navigate to. Common causes:
- Claude Code wasn't launched from inside tmux when the hook fired (no `$TMUX_PANE` to capture)
- The pane was killed between the notification firing and you clicking
- Multiple tmux servers (rare)

### "I want to use the homebrew `terminal-notifier` instead of rebuilding"

Skip the build steps. `notify.sh` will fall back to whatever `terminal-notifier` is on `$PATH`. You'll see "terminal-notifier" as the notification header (with the terminal icon), but click-to-tmux still works.

---

## Credits

This fork is a thin rebrand on top of [`terminal-notifier`](https://github.com/julienXX/terminal-notifier) by [Eloy Durán](https://github.com/alloy) and [Julien Blanchard](https://github.com/julienXX). All the actual notification work is theirs — this fork only changes the bundle identity to play nicely with macOS's per-app permission model so it can be branded as "Claude Code".

The Claude logo and the "Claude Code" name are trademarks of [Anthropic](https://anthropic.com). This fork is unaffiliated with Anthropic — it's a personal customization for the [Claude Code](https://docs.claude.com/en/docs/claude-code/) CLI.

## License

MIT, same as upstream. See [`LICENSE.md`](LICENSE.md).
