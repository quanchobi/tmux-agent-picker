#!/usr/bin/env bash
# Runs `agent-picker.sh list` against a private tmux server with fake agents:
# detection by argv[0], by an interpreter's script, and in a pane's
# descendants; omp's title chrome stripped; urgency ordering with
# tmux-agent-indicator state; the calling pane last; no state column without
# the indicator.
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
picker=$root/scripts/agent-picker.sh
socket=agent-picker-test-$$
tmp=$(mktemp -d)
# A new server copies the caller's environment into its global one; state
# inherited from an outer tmux-agent-indicator (TMUX_AGENT_PANE_%N_*, names a
# shell can't unset) would leak into the test.
clean=()
while IFS= read -r var; do clean+=(-u "$var"); done < <(env | grep -o '^TMUX_AGENT_[^=]*' || true)
t() { env "${clean[@]}" tmux -L "$socket" -f /dev/null "$@"; }
trap 't kill-server 2>/dev/null || true; rm -rf "$tmp"' EXIT

failures=0
check() {
    if [ "$2" = "$3" ]; then
        printf 'ok   %s\n' "$1"
    else
        printf 'FAIL %s\n  expected: %s\n  actual:   %s\n' "$1" "$3" "$2"
        failures=$((failures + 1))
    fi
}

# `list`, stripped of colour and reduced to "<pane> <agent> [<state>]".
list() {
    TMUX="$(t display -p '#{socket_path}'),0,0" "$picker" list "$1" |
        sed -E 's/\x1b\[[0-9;]*m//g; s/●//' |
        awk -F '\t' '{ split($2, f, " "); print $1, (indicator ? f[2] " " f[1] : f[1]) }' indicator="${2:-}"
}

# The label column of pane $1's row, before the indicator adds a state
# column: the text between the location and the dimmed directory.
label() {
    TMUX="$(t display -p '#{socket_path}'),0,0" "$picker" list "$shell" |
        awk -F '\t' -v p="$1" '$1 == p { s = $2; sub(/  \033\[2m.*/, "", s); sub(/^[^ ]+ +[^ ]+ +/, "", s); print s }'
}

# A process whose argv[0] is $1 (bash, so the name doesn't change behaviour;
# `; :` keeps it from exec'ing sleep in its place).
fake() { printf "bash -c 'exec -a %s bash -c \"sleep 600; :\"'" "$1"; }
printf 'sleep 600\n' >"$tmp/codex.js"

shell=$(t new-session -d -s main -x 200 -y 50 -P -F '#{pane_id}' 'sleep 600')
direct=$(t split-window -d -t main -P -F '#{pane_id}' "$(fake claude)")
interp=$(t split-window -d -t "$direct" -P -F '#{pane_id}' "bash -c 'exec -a node bash $tmp/codex.js'")
nested=$(t new-window -d -t main -P -F '#{pane_id}' "$(fake omp); sleep 600")
other=$(t new-window -d -t main -P -F '#{pane_id}' "$(fake not-an-agent)")
t set -g @agent-picker-processes 'claude,codex,omp'
sleep 0.5

check 'agents by argv[0], interpreter script and descendant; pane order' \
    "$(list "$shell" | tr '\n' ';')" \
    "$direct claude;$interp codex;$nested omp;"
check 'non-agent pane is not listed' "$(list "$shell" | grep -c "^$other " || true)" 0

cwd=$(basename "$(t display -p -t "$nested" '#{pane_current_path}')")
for case in 'π ⠋ Fix the parser|Fix the parser' 'π: Fix the parser|Fix the parser' \
    "π > $cwd|" 'π !|' 'custom title|custom title'; do
    t select-pane -t "$nested" -T "${case%%|*}"
    check "omp title '${case%%|*}'" "$(label "$nested")" "${case#*|}"
done
t select-pane -t "$direct" -T 'π ⠋ kept'
check 'π chrome kept for non-omp agents' "$(label "$direct")" 'π ⠋ kept'

t set-environment -g TMUX_AGENT_INDICATOR_DIR /nonexistent
t set-environment -g "TMUX_AGENT_PANE_${nested}_STATE" needs-input
t set-environment -g "TMUX_AGENT_PANE_${interp}_STATE" 'done'
t set-environment -g "TMUX_AGENT_PANE_${direct}_STATE" running
t set-environment -g "TMUX_AGENT_PANE_${shell}_STATE" 'done'
t set-environment -g "TMUX_AGENT_PANE_${shell}_AGENT" aider

check 'indicator state orders needs-input, done, running; caller last' \
    "$(list "$nested" 1 | tr '\n' ';')" \
    "$shell aider done;$interp codex done;$direct claude running;$nested omp needs-input;"

[ "$failures" -eq 0 ]
