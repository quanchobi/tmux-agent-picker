# tmux-agent-picker

A tmux popup that lists the coding agents (Claude Code, Codex, omp, aider,
…) running in your panes, fuzzy-searches them with fzf, previews the selected
agent's screen, and jumps to it. Opened with `prefix` + `a`.

Each row shows the agent, its `session:window.pane`, the pane title (Claude
Code and omp put the conversation title there), the pane's `@agent_name`
label if set, and its directory. For omp, the title is shown without omp's
`π`, spinner and status marks, and is left blank until the session has a
title. The pane you opened the picker from is listed last.

With [tmux-agent-indicator] loaded, each row also shows the agent's state, and
agents are ordered by urgency: `needs-input`, `done`, `running`, `idle`.
Without it, the picker works the same but has no state column.

Agents are found from each pane's process tree: a process whose name is in
the agent list, or an interpreter (`node`, `bun`, `python`, a shell, …)
running a script of that name. The outermost agent in a pane wins. Panes that
tmux-agent-indicator reports state for are listed even if their process isn't
recognized.

## Keys

| Key       | Action                   |
| --------- | ------------------------ |
| `Enter`   | jump to the agent's pane |
| `Tab`     | down (`Shift-Tab` up)    |
| `Ctrl-r`  | reload the list          |
| `Ctrl-/`  | toggle the preview       |
| `Esc`     | close                    |

## Requirements

tmux 3.3+, bash 4+, fzf 0.53+ (for `--tmux`), awk, `ps`.

## Install

### TPM

```tmux
set -g @plugin 'quanchobi/tmux-agent-picker'
```

### Home Manager (flake)

```nix
inputs.tmux-agent-picker = {
  url = "github:quanchobi/tmux-agent-picker";
  inputs.nixpkgs.follows = "nixpkgs";
};

# in your Home Manager modules
imports = [ inputs.tmux-agent-picker.homeModules.default ];
programs.tmux.agentPicker = {
  enable = true;
  # key = "a";
  # settings.preview-window = "right:55%,follow";
};
```

The package bundles fzf, awk and `ps` and uses `programs.tmux.package` for
`tmux`, so it doesn't depend on the tmux server's `PATH`. It is also available
as `packages.<system>.default` for `programs.tmux.plugins`.

### Manually

```tmux
run-shell /path/to/tmux-agent-picker/agent-picker.tmux
```

## Options

| Option                         | Default                                                                   |
| ------------------------------ | ------------------------------------------------------------------------- |
| `@agent-picker-key`            | `a`                                                                       |
| `@agent-picker-processes`      | `claude,codex,omp,aider,cursor-agent,opencode,gemini,crush,amp,goose`     |
| `@agent-picker-popup-size`     | `80%,70%` (fzf `--tmux`: `[center\|top\|…,]WIDTH[,HEIGHT]`)               |
| `@agent-picker-preview-window` | `down:60%,follow` (fzf `--preview-window`)                                |
| `@agent-picker-<state>-color`  | `needs-input` yellow, `done` red, `running` green, `idle` default         |

Agents in tmux-agent-indicator's `@agent-indicator-processes` are recognized
too. Colours take tmux names: `red`, `brightred`, `colour208`, `#ff8800`.

Set options before the plugin loads. `scripts/agent-picker.sh` also runs
outside tmux (attaching to the chosen pane), e.g. as a shell alias.

## Tests

```sh
tests/test-list.sh
```

[tmux-agent-indicator]: https://github.com/quanchobi/tmux-agent-indicator
