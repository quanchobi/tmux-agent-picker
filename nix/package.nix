{
  lib,
  stdenv,
  tmuxPlugins,
  makeWrapper,
  bash,
  fzf,
  gawk,
  procps,
  tmux,
  version ? "unstable",
}:
tmuxPlugins.mkTmuxPlugin {
  pluginName = "agent-picker";
  rtpFilePath = "agent-picker.tmux";
  inherit version;

  # Runtime files only, so editing docs or tests doesn't rebuild the plugin.
  src = lib.fileset.toSource {
    root = ../.;
    fileset = lib.fileset.unions [
      ../agent-picker.tmux
      ../scripts
    ];
  };

  nativeBuildInputs = [ makeWrapper ];
  # Shebangs are patched to this bash (associative arrays need bash 4, which
  # macOS's /bin/bash isn't).
  buildInputs = [ bash ];

  # run-shell inherits the tmux server's PATH, which needn't hold fzf. `tmux`
  # must match the running server: override it with the configured package.
  postInstall = ''
    wrapProgram $target/scripts/agent-picker.sh --prefix PATH : ${
      lib.makeBinPath (
        [
          fzf
          gawk
          tmux
        ]
        ++ lib.optional stdenv.hostPlatform.isLinux procps
      )
    }
  '';

  meta = {
    description = "tmux popup to fuzzy-find coding agents running in panes and jump to them";
    homepage = "https://github.com/quanchobi/tmux-agent-picker";
    platforms = lib.platforms.unix;
  };
}
