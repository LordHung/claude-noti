#!/bin/bash
# Build a notification title in the form:
#   "Claude Code — <suffix>: <task> [<window>]"
# from a Claude Code hook JSON payload on stdin.
#
# Usage: echo "$INPUT" | build-title.sh <suffix>
#   <suffix> e.g. "Done", "Waiting", "Permission"
#
# Sources:
#   task   = Claude session name (set via /rename in ~/.claude/sessions/<pid>.json)
#            falls back to git branch, then cwd basename
#   window = tmux window name (from $TMUX_PANE)

SUFFIX="${1:-}"
INPUT=$(cat)

CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')
PANE="${TMUX_PANE:-}"

SESSION_NAME=""
if [ -n "$SESSION_ID" ]; then
  SESSION_NAME=$(jq -r --arg sid "$SESSION_ID" \
    'select(.sessionId==$sid) | .name // empty' \
    ~/.claude/sessions/*.json 2>/dev/null | head -1)
fi

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

WINDOW=""
if [ -n "$PANE" ] && command -v tmux >/dev/null 2>&1; then
  WINDOW=$(tmux display-message -p -t "$PANE" '#{window_name}' 2>/dev/null)
fi

PREFIX="Claude Code"
[ -n "$SUFFIX" ] && PREFIX="$PREFIX — $SUFFIX"

if [ -n "$TASK" ] && [ -n "$WINDOW" ]; then
  echo "$PREFIX: $TASK [$WINDOW]"
elif [ -n "$TASK" ]; then
  echo "$PREFIX: $TASK"
elif [ -n "$WINDOW" ]; then
  echo "$PREFIX: $WINDOW"
else
  echo "$PREFIX"
fi
