#!/usr/bin/env bash
# tmux-agent-picker bootstrap: binds @agent-picker-key (default a) after the
# prefix to the agent picker popup.

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

key=$(tmux show-option -gqv @agent-picker-key)
tmux bind-key "${key:-a}" run-shell "'$CURRENT_DIR/scripts/agent-picker.sh' pick '#{client_name}' '#{pane_id}'"
