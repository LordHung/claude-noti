#!/bin/bash
# Invoked by terminal-notifier -execute when a Claude notification is clicked.
# Args: <pane-id> <window-target> <session-name>
PANE="$1"
WINDOW="$2"
SESSION="$3"

exec >> /tmp/nf-click.log 2>&1
echo "--- click $(date) pane=$PANE window=$WINDOW session=$SESSION PATH=$PATH ---"

TMUX_BIN="$(command -v tmux || echo /opt/homebrew/bin/tmux)"
"$TMUX_BIN" switch-client -t "$SESSION"
"$TMUX_BIN" select-window -t "$WINDOW"
"$TMUX_BIN" select-pane -t "$PANE"
/usr/bin/open -a Alacritty
