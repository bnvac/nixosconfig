# nix2-pull — bring /etc/nixos up to date without losing your own edits.
# `nixup` and the weekly auto-update run it before rebuilding.
#
#   1. Anything you changed (edited files, new files) is committed locally
#      first, as "My changes on <host>, <date>". Nothing is pushed anywhere;
#      it just means your edits are saved in git and can't get lost.
#      (settings.local.nix and hardware-configuration.nix aren't in git at
#      all, so they're never touched.)
#   2. The update is fetched and your commits are replayed on top of it.
#   3. If an update changed the same lines you did, everything is put back
#      exactly as it was (your edits, the old version) and it tells you
#      which files clashed. Nothing half-merged is ever left behind.
#
#   nix2-pull           do it
#   nix2-pull --quiet   less talk (for the timer); a clash still says why
#   nix2-pull --mine    just list your local commits
dir=${NIXOS_DIR:-/etc/nixos}
quiet=0
case "${1:-}" in
  "" | --mine) ;;
  --quiet) quiet=1 ;;
  *) echo "usage: nix2-pull [--quiet|--mine]"; exit 2 ;;
esac
say() { [ "$quiet" = 1 ] || echo "$@"; }

[ -d "$dir/.git" ] || { echo "nix2-pull: $dir isn't a git clone"; exit 1; }
if [ "$(id -u)" -ne 0 ]; then                  # /etc/nixos belongs to root
  exec /run/wrappers/bin/sudo env "PATH=$PATH" "$0" "$@"
fi
cd "$dir" || exit 1
host=$(uname -n)
g() { git -c user.name="nix2 on $host" -c user.email="nix2@localhost" "$@"; }
if [ "${1:-}" = --mine ]; then
  git log --format='  %h  %ad  %s' --date=short '@{upstream}..HEAD'
  exit 0
fi

# Half-finished git work from before: don't pile on top of it.
gd=$(git rev-parse --git-dir)
if [ -d "$gd/rebase-merge" ] || [ -d "$gd/rebase-apply" ] || [ -f "$gd/MERGE_HEAD" ]; then
  echo "nix2-pull: $dir is in the middle of a merge or rebase."
  echo "  Finish it (git status says how) or undo it: sudo git -C $dir rebase --abort  (or merge --abort)"
  exit 1
fi
up=$(git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null) || {
  echo "nix2-pull: the branch in $dir doesn't follow a remote branch, so there's nothing to pull."
  echo "  Fix: sudo git -C $dir branch --set-upstream-to=origin/<branch>"
  exit 1
}

# 1. Save your edits as a local commit.
if [ -n "$(git status --porcelain)" ]; then
  say ":: saving your local changes:"
  [ "$quiet" = 1 ] || git status --short | sed 's/^/     /'
  g add -A
  g commit -q -m "My changes on $host, $(date '+%Y-%m-%d %H:%M')" \
    -m "Saved automatically by nix2-pull before updating."
fi

# 2. Fetch and put your commits on top.
say ":: fetching $up …"
git fetch -q || { echo "nix2-pull: couldn't reach the remote (offline?). Nothing changed."; exit 1; }
before=$(git rev-parse HEAD)
if g rebase -q "$up" >/dev/null 2>&1; then
  mine=$(git rev-list --count "$up..HEAD")
  if [ "$(git rev-parse HEAD)" = "$before" ]; then
    say ":: already up to date"
  else
    say ":: updated"
  fi
  [ "$mine" -gt 0 ] && say ":: your own changes on top: $mine commit(s) (nix2-pull --mine lists them)"
  exit 0
fi

# 3. A clash: undo the attempt, leave everything as it was.
clash=$(git diff --name-only --diff-filter=U 2>/dev/null)
g rebase --abort 2>/dev/null || true
git reset -q --hard "$before"
echo "nix2-pull: the update changes the same lines as your own edits, so it wasn't applied."
echo "  Your changes are safe: every file is just as it was. The files that clash:"
printf '%s\n' "${clash:-(git listed none)}" | sed 's/^/    /'
echo "  To merge them by hand:  cd $dir && sudo git rebase $up"
echo "  (fix each file git names, then: sudo git add <file> && sudo git rebase --continue;"
echo "   changed your mind: sudo git rebase --abort). Then run nixup again."
exit 1
