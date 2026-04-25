#!/bin/bash
# Notification hook handler. Reads Claude Code Notification JSON on stdin,
# builds a title that includes the session name + tmux window, and dispatches
# to notify.sh with the right sound.
#
# Usage: notification.sh <suffix> <default_message> <sound_path>
#   <suffix>          e.g. "Waiting", "Permission"
#   <default_message> fallback if .notification_message is missing
#   <sound_path>      e.g. /System/Library/Sounds/Blow.aiff

SUFFIX="${1:-}"
DEFAULT_MSG="${2:-}"
SOUND="${3:-}"

INPUT=$(cat)
MSG=$(echo "$INPUT" | jq -r --arg d "$DEFAULT_MSG" '.notification_message // $d')
TITLE=$(echo "$INPUT" | ~/.claude/hooks/build-title.sh "$SUFFIX")

exec ~/.claude/hooks/notify.sh "$TITLE" "$MSG" "$SOUND"
