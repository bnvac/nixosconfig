# Claude and AI coding agents. (Neb, the voice assistant, is the `assistant`
# module.)
#
#   Claude (app)  Anthropic's desktop app for Linux (beta): Chat, Cowork and
#              Claude Code in a window. App menu → Claude, or the parajynx menu →
#              Code & engineering. Packaged from Anthropic's own .deb
#              (pkgs/default.nix `claude-desktop`); update-mine moves it to
#              each new version. Claude Code inside it needs a paid plan.
#              Cowork runs tasks in a small VM: it uses /dev/kvm (you're in
#              the kvm group) and QEMU, both provided.
#
# The two terminal agents below install themselves the first time you run
# them and then keep themselves up to date — no `nixup` needed for a new
# version, and nothing is downloaded until you use one.
#
#   claude     Claude Code. The first run installs Anthropic's own build into
#              ~/.local (the same as their installer); it updates itself in the
#              background, and `claude update` / `claude doctor` work. (The
#              copy in nixpkgs can't update itself and lags behind.)
#   freebuff   Freebuff, the free version of the Codebuff agent (it shows ads;
#              no account or API key). The first run does
#              `npm install -g freebuff` into ~/.npm-global; it fetches and
#              updates its own program after that.
#
# Both are prebuilt programs: nix-ld (core.nix) lets them run on NixOS, and
# ~/.local/bin and ~/.npm-global/bin come first on PATH (core.nix), so the
# self-updated copy is always the one that runs.
#
# Menu: Code & engineering → Claude Code / Freebuff asks which project to
# open it in.
{ pkgs, ... }:
let
  s = import ../settings.nix;
  claude = pkgs.writeShellScriptBin "claude" ''
    native="$HOME/.local/bin/claude"
    if [ -x "$native" ]; then exec "$native" "$@"; fi
    echo "claude: first run — installing Claude Code (Anthropic's own build, which keeps itself up to date) into ~/.local …" >&2
    # The official installer: downloads the build for this machine, checks its
    # checksum, sets up ~/.local/bin/claude. Not as root: it installs for you.
    if ${pkgs.curl}/bin/curl -fsSL https://claude.ai/install.sh \
       | PATH="${pkgs.lib.makeBinPath (with pkgs; [ curl coreutils gnused gnugrep jq zstd ])}:$PATH" ${pkgs.bash}/bin/bash \
       && [ -x "$native" ]; then
      echo >&2
      exec "$native" "$@"
    fi
    echo "claude: couldn't install it (offline?). Try again later, or by hand:" >&2
    echo "  curl -fsSL https://claude.ai/install.sh | bash" >&2
    exit 1
  '';

  freebuff = pkgs.writeShellScriptBin "freebuff" ''
    prefix="''${NPM_CONFIG_PREFIX:-$HOME/.npm-global}"
    bin="$prefix/bin/freebuff"
    if [ ! -x "$bin" ]; then
      echo "freebuff: first run — installing Freebuff (npm install -g freebuff, into $prefix) …" >&2
      if ! NPM_CONFIG_PREFIX="$prefix" NPM_CONFIG_UPDATE_NOTIFIER=false PATH="${pkgs.nodejs}/bin:$PATH" \
           ${pkgs.nodejs}/bin/npm install -g --no-fund --no-audit --loglevel=error freebuff >&2 \
         || [ ! -x "$bin" ]; then
        echo "freebuff: couldn't install it (offline?). Try again later, or: npm install -g freebuff" >&2
        exit 1
      fi
    fi
    # Its launcher is a node script (#!/usr/bin/env node).
    PATH="$PATH:${pkgs.nodejs}/bin" exec "$bin" "$@"
  '';

  # Pick a project, open the agent there in a terminal.
  agentHere = pkgs.writeShellApplication {
    name = "agent-here";
    runtimeInputs = with pkgs; [ coreutils findutils larbs-dmenu ];
    text = ''
      agent=''${1:?usage: agent-here claude|freebuff}
      base="$HOME/projects"
      dirs=$( { [ -d "$base" ] && find "$base" -mindepth 1 -maxdepth 1 -type d ! -name '.*' -printf '%f\n' | sort; } || true)
      pick=$(printf '%s\n' "$dirs" "~ (home folder)" | sed '/^$/d' | dmenu -i -l 15 -p "$agent in which project?") || exit 0
      case "$pick" in
        "~ (home folder)") dir="$HOME" ;;
        *) dir="$base/$pick" ;;
      esac
      [ -d "$dir" ] || dir="$HOME"
      cd "$dir"
      # When you quit the agent you're left in a shell in that project.
      # shellcheck disable=SC2016  # expanded by the inner sh, on purpose
      exec st -e sh -c '"$1"; exec "''${SHELL:-sh}"' sh "$agent"
    '';
  };
in
{
  my.packages = [ pkgs.claude-desktop claude freebuff agentHere pkgs.nodejs ];
  users.users.${s.username}.extraGroups = [ "kvm" ];    # Cowork's VM

  my.menu."Code & engineering" = [
    { label = "Claude (desktop app: Chat, Cowork, Code)"; run = "claude-desktop"; }
    { label = "Claude Code in a terminal (pick a project)"; run = "agent-here claude"; }
    { label = "Freebuff — free coding agent (pick a project)"; run = "agent-here freebuff"; }
  ];
}
