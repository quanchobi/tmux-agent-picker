#!/usr/bin/env bash
# tmux-agent-picker: fuzzy-find the coding agents running in tmux panes and
# jump to one. Agents are found from each pane's process tree; when
# tmux-agent-indicator is loaded, its per-pane state (running, needs-input,
# done) is shown and agents that need attention are listed first.
set -euo pipefail

DEFAULT_PROCESSES=claude,codex,omp,aider,cursor-agent,opencode,gemini,crush,amp,goose
self=${BASH_SOURCE[0]}

usage() {
    cat <<'EOF'
usage: agent-picker.sh [pick [client [pane]]]  fzf picker; jumps to the selected agent
       agent-picker.sh list [pane]             picker lines: <pane_id>\t<display>
       agent-picker.sh preview <pane>          a pane's screen, for the preview window
       agent-picker.sh jump <pane> [client]    switch the client (or attach) to a pane

client: the tmux client to switch (default: the calling one).
pane: the calling pane, listed last (default: $TMUX_PANE).
EOF
}

# A global tmux option, or $2 when it is unset or empty.
opt() {
    local value
    value=$(tmux show-option -gqv "$1" 2>/dev/null || true)
    printf '%s\n' "${value:-$2}"
}

default_color() {
    case $1 in
    needs-input) echo yellow ;;
    done) echo red ;;
    running) echo green ;;
    *) echo default ;;
    esac
}

# tmux colour (name, brightname, colourN, #rrggbb) -> foreground SGR
# parameters; nothing for default or unknown colours.
sgr() {
    local colour=${1,,} bright=0 n
    if [[ $colour == bright* ]]; then
        bright=60
        colour=${colour#bright}
    fi
    case $colour in
    black) n=0 ;;
    red) n=1 ;;
    green) n=2 ;;
    yellow) n=3 ;;
    blue) n=4 ;;
    magenta) n=5 ;;
    cyan) n=6 ;;
    white) n=7 ;;
    colour[0-9]* | color[0-9]*)
        echo "38;5;${colour##*r}"
        return
        ;;
    \#??????)
        echo "38;2;$((16#${colour:1:2}));$((16#${colour:3:2}));$((16#${colour:5:2}))"
        return
        ;;
    *) return ;;
    esac
    echo "$((30 + bright + n))"
}

cmd_list() {
    local current=${1:-${TMUX_PANE:-}} processes state
    local -a colors=()
    processes="$(opt @agent-picker-processes "$DEFAULT_PROCESSES"),$(opt @agent-indicator-processes '')"
    for state in needs-input 'done' running idle; do
        colors+=("$(sgr "$(opt "@agent-picker-$state-color" "$(default_color "$state")")")")
    done

    # Three inputs, told apart by FILENAME: every process (pid, ppid, argv),
    # the global environment (tmux-agent-indicator state), and every pane.
    # shellcheck disable=SC2016 # awk program
    awk -F '\t' \
        -v procs="$processes" -v current="$current" -v home="$HOME" \
        -v c_needs="${colors[0]}" -v c_done="${colors[1]}" -v c_running="${colors[2]}" -v c_idle="${colors[3]}" '
        BEGIN {
            n = split(procs, p, ",")
            for (i = 1; i <= n; i++) {
                gsub(/^[ \t]+|[ \t]+$/, "", p[i])
                if (p[i] != "") want[p[i]] = 1
            }
            split("node nodejs bun deno ruby sh bash zsh dash", ip, " ")
            for (i in ip) interp[ip[i]] = 1
            rank["needs-input"] = 0; rank["done"] = 1; rank["running"] = 2
            color["needs-input"] = c_needs; color["done"] = c_done
            color["running"] = c_running; color["idle"] = c_idle
            psf = ARGV[1]; envf = ARGV[2]; panef = ARGV[3]
        }
        function base(path,   parts, k) {
            sub(/\/+$/, "", path)
            k = split(path, parts, "/")
            return parts[k]
        }
        # The agent a process runs: argv[0], or the script an interpreter runs.
        function agent_of(pid,   f, k, i, name) {
            k = split(argv[pid], f, " ")
            name = base(f[1])
            sub(/^-/, "", name)
            if (name in want) return name
            if (!(name in interp) && name !~ /^python[0-9.]*$/) return ""
            for (i = 2; i <= k; i++) {
                if (f[i] ~ /^-/) continue
                name = base(f[i])
                sub(/\.(c?js|mjs|ts|py)$/, "", name)
                return (name in want) ? name : ""
            }
            return ""
        }
        # Breadth-first, so the outermost agent wins over agents it spawned.
        function find_agent(root,   queue, kids, head, tail, k, i, pid, a) {
            head = 1; tail = 1; queue[1] = root
            while (head <= tail) {
                pid = queue[head++]
                if ((a = agent_of(pid)) != "") return a
                k = split(children[pid], kids, " ")
                for (i = 1; i <= k; i++) queue[++tail] = kids[i]
            }
            return ""
        }
        # omp titles its terminal "π <mark> <label>" (mark: a spinner frame,
        # "!" for attention, ">" when idle), or "π: <label>" with the spinner
        # off. The label is the session title, else the basename of the cwd.
        function omp_title(t, path) {
            if (!sub(/^π(:| [^ ]+)( |$)/, "", t) && !sub(/^π$/, "", t)) return t
            return (t == base(path)) ? "" : t
        }
        function pad(s, w) { return sprintf("%-" w "s", s) }
        FILENAME == psf {
            line = $0
            sub(/^[ \t]+/, "", line)
            pid = line; sub(/[ \t].*/, "", pid)
            sub(/^[^ \t]+[ \t]+/, "", line)
            ppid = line; sub(/[ \t].*/, "", ppid)
            sub(/^[^ \t]+[ \t]*/, "", line)
            argv[pid] = line
            children[ppid] = children[ppid] " " pid
            next
        }
        FILENAME == envf {
            if ($0 ~ /^TMUX_AGENT_INDICATOR_DIR=/) indicator = 1
            if ($0 !~ /^TMUX_AGENT_PANE_%[0-9]+_(STATE|AGENT)=/) next
            eq = index($0, "=")
            key = substr($0, 17, eq - 17)
            u = index(key, "_")
            if (substr(key, u + 1) == "STATE") st[substr(key, 1, u - 1)] = substr($0, eq + 1)
            else ag[substr(key, 1, u - 1)] = substr($0, eq + 1)
            next
        }
        FILENAME == panef {
            # pane_id pane_pid location path @agent_name pane_title host host_short
            pane = $1
            kind = find_agent($2)
            if (kind == "" && st[pane] == "") next
            if (ag[pane] != "") kind = ag[pane]
            if (kind == "") kind = "agent"
            state = st[pane] != "" ? st[pane] : "idle"
            r = (pane == current) ? 4 : ((state in rank) ? rank[state] : 3)
            title = ($6 == $7 || $6 == $8) ? "" : $6
            if (kind == "omp") title = omp_title(title, $4)
            label = ($5 != "") ? "[" $5 "] " title : title
            path = $4
            if (path == home) path = "~"
            else if (index(path, home "/") == 1) path = "~" substr(path, length(home) + 1)
            k = ++count[r]
            row_pane[r, k] = pane; row_state[r, k] = state; row_kind[r, k] = kind
            row_loc[r, k] = $3; row_label[r, k] = label; row_path[r, k] = path
            if (length(kind) > kw) kw = length(kind)
            if (length($3) > lw) lw = length($3)
            if (length(state) > sw) sw = length(state)
        }
        END {
            for (r = 0; r <= 4; r++) {
                for (k = 1; k <= count[r]; k++) {
                    state = row_state[r, k]
                    out = row_pane[r, k] "\t"
                    # Without tmux-agent-indicator every state is unknown: no column.
                    if (indicator) {
                        c = color[state]
                        s = "\342\227\217 " pad(state, sw)
                        out = out (c != "" ? "\033[" c "m" s "\033[0m" : s) " "
                    }
                    out = out pad(row_kind[r, k], kw) " " pad(row_loc[r, k], lw) " " row_label[r, k]
                    if (row_path[r, k] != "") out = out "  \033[2m" row_path[r, k] "\033[0m"
                    print out
                }
            }
        }
    ' <(ps -A -o pid= -o ppid= -o args=) \
        <(tmux show-environment -g 2>/dev/null || true) \
        <(tmux list-panes -a -F $'#{pane_id}\t#{pane_pid}\t#{session_name}:#{window_index}.#{pane_index}\t#{pane_current_path}\t#{@agent_name}\t#{pane_title}\t#{host}\t#{host_short}')
}

# The pane's screen with trailing blank lines dropped, so the preview's
# `follow` lands on the last output rather than empty rows.
cmd_preview() {
    local pane=${1%%$'\t'*}
    pane=${pane//[[:space:]]/}
    tmux capture-pane -pe -t "$pane" 2>/dev/null | awk '
        { line[NR] = $0; plain = $0; gsub(/\033\[[0-9;:]*[A-Za-z]/, "", plain) }
        plain ~ /[^[:space:]]/ { last = NR }
        END { for (i = 1; i <= last; i++) print line[i] }
    '
}

cmd_jump() {
    local pane=$1 client=${2:-}
    local -a client_args=()
    [ -n "$client" ] && client_args=(-c "$client")
    if [ -n "${TMUX:-}" ]; then
        tmux select-window -t "$pane" \; select-pane -t "$pane" \; switch-client "${client_args[@]}" -t "$pane"
    else
        exec tmux select-window -t "$pane" \; select-pane -t "$pane" \; attach-session -t "$pane"
    fi
}

cmd_pick() {
    local client=${1:-} current=${2:-${TMUX_PANE:-}} list selection q
    list=$(cmd_list "$current")
    if [ -z "$list" ]; then
        if [ -n "${TMUX:-}" ]; then
            tmux display-message 'No agents running'
        else
            echo 'No agents running' >&2
        fi
        return 0
    fi
    q=$(printf '%q' "$self")
    selection=$(
        printf '%s\n' "$list" | fzf --tmux "$(opt @agent-picker-popup-size 80%,70%)" \
            --ansi --delimiter '\t' --with-nth 2.. --tiebreak index --layout reverse \
            --border-label ' agents ' --prompt '❯ ' \
            --header '  ↵ jump ^r reload ^/ preview' \
            --bind 'tab:down,btab:up' \
            --bind "ctrl-r:reload($q list $(printf '%q' "$current"))" \
            --bind 'ctrl-/:toggle-preview' \
            --preview-window "$(opt @agent-picker-preview-window 'down:60%,follow')" \
            --preview "$q preview {1}"
    ) || return 0
    cmd_jump "${selection%%$'\t'*}" "$client"
}

case ${1:-pick} in
pick) cmd_pick "${@:2}" ;;
list) cmd_list "${@:2}" ;;
preview)
    [ $# -ge 2 ] || { usage >&2; exit 2; }
    cmd_preview "$2"
    ;;
jump)
    [ $# -ge 2 ] || { usage >&2; exit 2; }
    cmd_jump "${@:2}"
    ;;
-h | --help) usage ;;
*)
    usage >&2
    exit 2
    ;;
esac
