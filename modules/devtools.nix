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
