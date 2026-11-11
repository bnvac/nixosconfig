# Coding & engineering toolkit — small, fast, free/open-source tools for
# writing code, reading code and working on FOSS projects. Each project's own
# compilers come from its shell.nix (start one with `hearth new`), so the
# system stays lean and two projects never fight over versions.
#
# Bigger apps (VSCodium, Ghidra, Octave, OBS…) only with settings.nix →
# devExtras = true. Circuit/CAD/3D-printing tools are in the `ee` module.
{ pkgs, lib, ... }:
let
  s = import ../settings.nix;
in
{
  # ── Faster builds, in every project, with no setup ────────────────────────
  # sccache / ccache remember each compiled file, so building the same code
  # again (a clean build, another branch, a second project with the same
  # dependencies) takes seconds. mold links 5–10× faster than the default
  # linker, which is most of the wait after a small edit. Caches live in
  # ~/.cache/{sccache,ccache} (`debloat` can clear them).
  # (Only your own builds; Nix's sandboxed system builds are unaffected.)
  environment.sessionVariables = {
    RUSTC_WRAPPER = "sccache";
    CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_RUSTFLAGS = "-C link-arg=-fuse-ld=mold";
    CMAKE_C_COMPILER_LAUNCHER = "ccache";
    CMAKE_CXX_COMPILER_LAUNCHER = "ccache";
    SCCACHE_CACHE_SIZE = "20G";
  };

  # A notification when a terminal command that took 30 s or more finishes —
  # start a build, go do something else, hear when it's done (and whether it
  # worked). Not for programs you sit in (editors, ssh, lazygit…).
  # HEARTH_NOTIFY_AFTER=60 changes the threshold.
  programs.zsh.interactiveShellInit = lib.mkBefore ''
    zmodload zsh/datetime
    typeset -g __hearth_cmd="" __hearth_t0=0
    __hearth_preexec() { __hearth_cmd=$1; __hearth_t0=$EPOCHSECONDS; }
    __hearth_precmd() {
      local st=$? cmd=$__hearth_cmd secs t
      __hearth_cmd=""
      [[ -n $cmd && -n $DISPLAY ]] || return 0
      secs=$(( EPOCHSECONDS - __hearth_t0 ))
      (( secs >= ''${HEARTH_NOTIFY_AFTER:-30} )) || return 0
      case ''${''${cmd## }%% *} in
        nvim|vim|vi|v|less|more|man|ssh|htop|btop|top|lazygit|tmux|lf|watch|mpv|nix-shell|python|python3|node|zsh|bash) return 0 ;;
      esac
      if (( secs >= 60 )); then t="$(( secs / 60 ))m $(( secs % 60 ))s"; else t="''${secs}s"; fi
      if (( st == 0 )); then notify-send -a Terminal "✅ Done in $t" "$cmd"
      else notify-send -a Terminal -u critical "❌ Failed (exit $st) after $t" "$cmd"; fi
    }
    autoload -Uz add-zsh-hook
    add-zsh-hook preexec __hearth_preexec
    add-zsh-hook precmd __hearth_precmd
  '';

  # direnv: cd into a project and its tools (shell.nix) load by themselves,
  # cached so it's instant after the first time (nix-direnv).
  programs.direnv = { enable = true; silent = true; };

  # Nicer git, system-wide (your ~/.gitconfig still wins): side-by-side,
  # syntax-highlighted diffs (delta), clearer merge conflicts, `git absorb`.
  programs.git = {
    enable = true;
    config = {
      core.pager = "delta";
      interactive.diffFilter = "delta --color-only";
      delta = { navigate = true; line-numbers = true; };
      merge.conflictStyle = "zdiff3";
      diff.algorithm = "histogram";
      init.defaultBranch = "main";
      pull.rebase = true;
      rebase.autoStash = true;
      push.autoSetupRemote = true;
      rerere.enabled = true;
    };
  };

  my.packages = with pkgs; [
    # git & forges
    lazygit            # git in a friendly full-screen UI
    gh glab tea        # GitHub / GitLab / Codeberg (Gitea, Forgejo) from the terminal
    delta difftastic   # readable diffs; difftastic understands the code's structure
    git-absorb         # `git absorb`: fold fixes into the right earlier commits
    pre-commit reuse   # commit hooks; REUSE licence checks for FOSS projects
    # everyday helpers
    just               # a simple command runner (a friendlier Makefile)
    watchexec bacon    # re-run on save (any language / Rust)
    hyperfine          # benchmark commands properly
    tokei              # count lines of code by language
    xh                 # HTTP requests, like curl but readable
    yq-go              # jq for YAML/TOML/XML
    tlrc               # `tldr tar`: short practical examples for a command
    asciinema          # record a terminal session to share
    shellcheck nil     # shell-script checker; Nix language server
    # C / C++ (works with the gcc in core; projects can pin their own)
    cmake ninja meson clang-tools gdb valgrind
    # build speed: compile caches + a fast linker (see the top of this file)
    sccache ccache mold
    # desktop apps
    meld               # compare / merge files and folders side by side
    zeal               # offline docs for 200+ languages and libraries
    qalculate-gtk      # an engineer's calculator: units, bases, equations
    sqlitebrowser      # open and edit SQLite databases
  ] ++ lib.optionals (s.devExtras or false) [
    vscodium           # VS Code without the telemetry
    helix              # modal editor with language servers built in
    ghidra             # reverse engineering (NSA's open-source suite)
    octave gnuplot     # MATLAB-compatible maths; plotting
    obs-studio         # screen recording / streaming for demos
  ];

  my.menu."Code & engineering" = lib.mkBefore [
    { label = "New project (Rust, Python, C++, Go, Node…)"; run = "hearth new"; mode = "term"; }
    { label = "Projects folder"; run = "thunar ~/projects"; needs = "thunar"; }
    { label = "Git (lazygit, in ~/projects)"; run = "cd ~/projects && lazygit"; mode = "tty"; }
    { label = "Offline docs (Zeal)"; run = "zeal"; }
    { label = "Calculator (Qalculate)"; run = "qalculate-gtk"; }
    { label = "Compare files or folders (Meld)"; run = "meld"; }
    { label = "SQLite database browser"; run = "sqlitebrowser"; }
    { label = "VSCodium"; run = "codium"; needs = "codium"; }
    { label = "Ghidra"; run = "ghidra"; needs = "ghidra"; }
  ];
}
