#!/bin/bash
# Interactive Telegram setup.
#
# What it does:
#   1. Reads TELEGRAM_TOKEN + TELEGRAM_URL from $ENV_FILE (default: <repo>/.env).
#   2. Calls /getMe to confirm the token works and learn the bot's @username.
#   3. Asks the user to send any message to the bot.
#   4. Calls /getUpdates and picks the most recent chat_id.
#   5. Writes ~/.claude/hooks/telegram.env (mode 600) with token/url/chat_id.
#   6. Sends a confirmation message to verify end-to-end delivery.
#
# Re-running is safe — the file is overwritten in place.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="${ENV_FILE:-$REPO_ROOT/.env}"
TARGET="$HOME/.claude/hooks/telegram.env"
TGSEND="$HOME/.claude/hooks/telegram-send.sh"

if ! command -v jq >/dev/null 2>&1; then
  echo "[error] jq is required (brew install jq)"
  exit 1
fi
if ! command -v curl >/dev/null 2>&1; then
  echo "[error] curl is required"
  exit 1
fi

if [ ! -f "$ENV_FILE" ]; then
  cat <<EOF
[error] cannot find $ENV_FILE

Create it with:
  TELEGRAM_TOKEN=<your bot token from @BotFather>
  TELEGRAM_URL=https://api.telegram.org

See .env.example in this repo.
EOF
  exit 1
fi

read_env() {
  grep -E "^${1}=" "$ENV_FILE" | head -1 | cut -d= -f2- | sed -e 's/^"//;s/"$//;s/^'\''//;s/'\''$//'
}

TELEGRAM_TOKEN="$(read_env TELEGRAM_TOKEN)"
TELEGRAM_URL="$(read_env TELEGRAM_URL)"
TELEGRAM_URL="${TELEGRAM_URL%/}"

if [ -z "$TELEGRAM_TOKEN" ] || [ -z "$TELEGRAM_URL" ]; then
  echo "[error] TELEGRAM_TOKEN or TELEGRAM_URL missing in $ENV_FILE"
  exit 1
fi

echo "[telegram] verifying token via /getMe…"
ME="$(curl -fsS --max-time 10 "${TELEGRAM_URL}/bot${TELEGRAM_TOKEN}/getMe" || true)"
OK="$(echo "$ME" | jq -r '.ok // false' 2>/dev/null || echo false)"
if [ "$OK" != "true" ]; then
  echo "[error] Telegram API rejected the token. Response:"
  echo "$ME"
  exit 1
fi
BOT_USERNAME="$(echo "$ME" | jq -r '.result.username')"
BOT_NAME="$(echo "$ME" | jq -r '.result.first_name')"
echo "[ok] bot: $BOT_NAME (@$BOT_USERNAME)"

cat <<EOF

To receive notifications you must DM the bot at least once so it can
discover your chat_id.

  1. Open Telegram (phone or desktop).
  2. Search for @$BOT_USERNAME and tap "Start", or send any message.
  3. Press Enter here once you've sent the message.
EOF

# Read from the controlling tty so this still works when piped via Make.
if [ -r /dev/tty ]; then
  read -r _ < /dev/tty || true
else
  read -r _ || true
fi

echo "[telegram] fetching updates…"
UPDATES="$(curl -fsS --max-time 10 "${TELEGRAM_URL}/bot${TELEGRAM_TOKEN}/getUpdates")"
CHAT_ID="$(echo "$UPDATES" | jq -r '
  [ .result[]
    | (.message.chat.id // .edited_message.chat.id // .channel_post.chat.id // .my_chat_member.chat.id)
  ]
  | map(select(. != null))
  | last // empty
')"

if [ -z "$CHAT_ID" ]; then
  cat <<EOF
[error] no recent messages found for @$BOT_USERNAME.

Make sure you actually sent a message to the bot, then re-run:
  make setup-telegram

If the bot was previously DMd a long time ago, Telegram may have dropped
the update — send a fresh message and try again.
EOF
  exit 1
fi

mkdir -p "$(dirname "$TARGET")"
umask 077
cat > "$TARGET" <<EOF
TELEGRAM_TOKEN=$TELEGRAM_TOKEN
TELEGRAM_URL=$TELEGRAM_URL
TELEGRAM_CHAT_ID=$CHAT_ID
EOF
chmod 600 "$TARGET"

echo "[ok] wrote $TARGET (chat_id=$CHAT_ID)"

if [ -x "$TGSEND" ]; then
  "$TGSEND" "Claude Code" "Telegram notifications are wired up via @$BOT_USERNAME."
  echo "[ok] sent test message — check Telegram."
else
  cat <<EOF
[warn] $TGSEND not installed yet. Run:
         make install-hooks
       (or 'make setup' / 'make setup-tmux') to get the helper in place.
EOF
fi
