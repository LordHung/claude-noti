#!/bin/bash
# Forward a Claude Code notification to Telegram. Best-effort, async-safe.
# Usage: telegram-send.sh <title> <message>
#
# No-op (exit 0) when ~/.claude/hooks/telegram.env is missing or any of
# TELEGRAM_TOKEN / TELEGRAM_URL / TELEGRAM_CHAT_ID is unset, so it can be
# called unconditionally from notify.sh.

TITLE="${1:-Claude Code}"
MSG="${2:-}"

CONFIG="$HOME/.claude/hooks/telegram.env"
[ -f "$CONFIG" ] || exit 0

# shellcheck disable=SC1090
. "$CONFIG"

[ -n "${TELEGRAM_TOKEN:-}" ]   || exit 0
[ -n "${TELEGRAM_URL:-}" ]     || exit 0
[ -n "${TELEGRAM_CHAT_ID:-}" ] || exit 0

escape() {
  printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'
}

SAFE_TITLE=$(escape "$TITLE")
SAFE_MSG=$(escape "$MSG")

if [ -n "$SAFE_MSG" ]; then
  TEXT="<b>${SAFE_TITLE}</b>
${SAFE_MSG}"
else
  TEXT="<b>${SAFE_TITLE}</b>"
fi

curl -fsS --max-time 5 \
  -d "chat_id=${TELEGRAM_CHAT_ID}" \
  -d "parse_mode=HTML" \
  -d "disable_web_page_preview=true" \
  --data-urlencode "text=${TEXT}" \
  "${TELEGRAM_URL%/}/bot${TELEGRAM_TOKEN}/sendMessage" \
  >/dev/null 2>&1 || true
