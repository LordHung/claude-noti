#!/bin/bash
# Claude Code notification helper.
# Usage: notify.sh <title> <message> [sound_file]
#
# Behavior:
#   - Plays the sound (if given and present).
#   - Sends the notification via the Claude-branded terminal-notifier
#     (~/.claude/hooks/Claude Notifier.app), falling back to a Homebrew
#     terminal-notifier on PATH, then to osascript.
#   - When $TMUX_PANE is set AND click-action.sh is installed, attaches
#     -execute so clicking the notification jumps back to the originating
#     tmux pane in your terminal emulator.

TITLE="${1:-Claude Code}"
MSG="${2:-Notification}"
SOUND="${3:-}"

[ -n "$SOUND" ] && [ -f "$SOUND" ] && afplay "$SOUND" &

# Fan out to Telegram in the background. No-op when telegram.env isn't set up.
TGSEND="$HOME/.claude/hooks/telegram-send.sh"
[ -x "$TGSEND" ] && "$TGSEND" "$TITLE" "$MSG" >/dev/null 2>&1 &

PANE="${TMUX_PANE:-}"
TMUX_BIN="$(command -v tmux)"
ICON="$HOME/.claude/hooks/claude-icon.png"
CLICK="$HOME/.claude/hooks/click-action.sh"

# Prefer the Claude-branded notifier; fall back to whatever's on PATH.
CUSTOM_TN="$HOME/.claude/hooks/Claude Notifier.app/Contents/MacOS/terminal-notifier"
if [ -x "$CUSTOM_TN" ]; then
  TN="$CUSTOM_TN"
else
  TN="$(command -v terminal-notifier)"
fi

if [ -n "$TN" ]; then
  ARGS=(-title "$TITLE" -message "$MSG")

  # Branded notifier already ships the Claude icon; only add -appIcon
  # when falling back to Homebrew terminal-notifier.
  if [ "$TN" != "$CUSTOM_TN" ] && [ -f "$ICON" ]; then
    ARGS+=(-appIcon "file://$ICON")
  fi

  # Wire click navigation only when inside tmux AND the handler is installed.
  if [ -n "$PANE" ] && [ -x "$CLICK" ] && [ -n "$TMUX_BIN" ]; then
    WINDOW_TARGET="$("$TMUX_BIN" display-message -p -t "$PANE" '#{session_name}:#{window_index}' 2>/dev/null)"
    SESSION="$("$TMUX_BIN" display-message -p -t "$PANE" '#{session_name}' 2>/dev/null)"
    if [ -n "$WINDOW_TARGET" ]; then
      ARGS+=(-execute "$CLICK '$PANE' '$WINDOW_TARGET' '$SESSION'")
    fi
  fi

  "$TN" "${ARGS[@]}" >/dev/null 2>&1
  exit 0
fi

# Last-resort fallback: macOS osascript (no click handler, no icon).
osascript -e "display notification \"${MSG//\"/\\\"}\" with title \"${TITLE//\"/\\\"}\""
