# Home Manager module: programs.tmux.agentPicker.
# Exposed by the flake as homeModules.default; `version` comes from the flake.
{ version }:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib)
    concatStringsSep
    literalExpression
    mapAttrsToList
    mkEnableOption
    mkIf
    mkOption
    types
    ;

  cfg = config.programs.tmux.agentPicker;

  tmuxValue = value: "'${lib.replaceStrings [ "'" ] [ "'\\''" ] (toString value)}'";
in
{
  options.programs.tmux.agentPicker = {
    enable = mkEnableOption "tmux-agent-picker, a popup to fuzzy-find coding agents in tmux panes";

    package = mkOption {
      type = types.package;
      default = pkgs.callPackage ./package.nix {
        inherit version;
        tmux = config.programs.tmux.package;
      };
      defaultText = literalExpression "tmux-agent-picker from its flake, using programs.tmux.package";
      description = "The tmux-agent-picker plugin package.";
    };

    key = mkOption {
      type = types.str;
      default = "a";
      description = "Key that opens the picker after the prefix.";
    };

    settings = mkOption {
      type =
        with types;
        attrsOf (oneOf [
          int
          str
        ]);
      default = { };
      example = literalExpression ''
        {
          processes = "claude,codex,omp";
          popup-size = "90%,80%";
          preview-window = "right:55%,follow";
          needs-input-color = "colour3";
        }
      '';
      description = "`@agent-picker-*` tmux options, without the prefix.";
    };
  };

  config = mkIf cfg.enable {
    programs.tmux.plugins = [
      {
        plugin = cfg.package;
        extraConfig = concatStringsSep "\n" (
          mapAttrsToList (name: value: "set -g @agent-picker-${name} ${tmuxValue value}") (
            cfg.settings // { inherit (cfg) key; }
          )
        );
      }
    ];
  };
}
