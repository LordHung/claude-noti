#!/bin/bash
# Stop hook: notify when Claude finishes a task.
# Title is built by build-title.sh (session name + tmux window).
# Body is the most recent real user prompt from the transcript.

INPUT=$(cat)
TP=$(echo "$INPUT" | jq -r '.transcript_path // empty')

TITLE=$(echo "$INPUT" | ~/.claude/hooks/build-title.sh "Done")

BODY="Task complete"
if [ -f "$TP" ]; then
  E=$(jq -rs '[.[] | select(.type=="user" and (.message.content|type)=="string" and (.message.content|startswith("<")|not))] | last | .message.content // empty' "$TP" 2>/dev/null \
        | tr '\n' ' ' | tr -s ' ' | sed 's/^ //;s/ $//' | cut -c 1-160)
  [ -n "$E" ] && [ "$E" != "null" ] && BODY="$E"
fi

exec ~/.claude/hooks/notify.sh "$TITLE" "$BODY" /System/Library/Sounds/Ping.aiff
