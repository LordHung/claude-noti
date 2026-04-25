#!/bin/bash
# Merge Claude Code Notification + Stop hooks into ~/.claude/settings.json
# without clobbering anything else the user has there.
#
# Usage: install-hooks-settings.sh [--with-tmux]
#
# What it does:
#   - Backs up settings.json to settings.json.bak.<timestamp>
#   - Adds (or replaces, if already present with the same identifier)
#     the three hooks Claude Code calls:
#       Notification[matcher=permission_prompt] -> notification.sh Permission ...
#       Notification[matcher=idle_prompt]       -> notification.sh Waiting ...
#       Stop                                    -> stop.sh
#   - --with-tmux is informational only — every hook works the same way
#     regardless; tmux click navigation kicks in automatically when
#     click-action.sh exists at $HOME/.claude/hooks/click-action.sh.

set -euo pipefail

WITH_TMUX=0
[ "${1:-}" = "--with-tmux" ] && WITH_TMUX=1

SETTINGS="$HOME/.claude/settings.json"
HOOKS_DIR="$HOME/.claude/hooks"

if ! command -v jq >/dev/null 2>&1; then
  echo "[error] jq is required to safely merge hooks into settings.json"
  echo "        install with: brew install jq"
  exit 1
fi

mkdir -p "$(dirname "$SETTINGS")"
if [ ! -f "$SETTINGS" ]; then
  echo "{}" > "$SETTINGS"
fi

# Back up before touching anything.
TS="$(date +%Y%m%d-%H%M%S)"
BACKUP="$SETTINGS.bak.$TS"
cp "$SETTINGS" "$BACKUP"
echo "[backup] $BACKUP"

PERM_CMD="$HOOKS_DIR/notification.sh Permission \"Claude needs your permission\" /System/Library/Sounds/Glass.aiff"
IDLE_CMD="$HOOKS_DIR/notification.sh Waiting \"Claude is waiting for your input\" /System/Library/Sounds/Blow.aiff"
STOP_CMD="$HOOKS_DIR/stop.sh"

TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

# Replace (or add) Notification + Stop entries. Matchers:
#   - keep any other Notification matcher the user has
#   - replace any existing entry with the same matcher (idempotent)
jq \
  --arg perm  "$PERM_CMD" \
  --arg idle  "$IDLE_CMD" \
  --arg stop  "$STOP_CMD" \
  '
  .hooks = (.hooks // {})

  # Notification: keep entries for any matcher we are not managing.
  | .hooks.Notification = (
      ((.hooks.Notification // []) | map(select(.matcher != "permission_prompt" and .matcher != "idle_prompt")))
      + [
          {matcher: "permission_prompt", hooks: [{type: "command", command: $perm}]},
          {matcher: "idle_prompt",       hooks: [{type: "command", command: $idle}]}
        ]
    )

  # Stop: keep entries whose command is something other than our stop.sh.
  | .hooks.Stop = (
      ((.hooks.Stop // []) | map(
        select(
          (.hooks // []) | map(.command) | any(. == $stop) | not
        )
      ))
      + [{hooks: [{type: "command", command: $stop}]}]
    )
  ' "$SETTINGS" > "$TMP"

mv "$TMP" "$SETTINGS"
trap - EXIT

echo "[ok] hooks merged into $SETTINGS"
if [ "$WITH_TMUX" = "1" ]; then
  echo "[tmux] click navigation will activate automatically because click-action.sh is installed"
else
  echo "[no-tmux] notifications will fire without click navigation"
fi
