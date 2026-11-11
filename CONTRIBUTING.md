# Contributing to Hearth

Thanks for helping! Bug reports, ideas and pull requests are all welcome.

## Trying a change

On a Hearth machine, `/etc/nixos` *is* your clone: edit, then `rebuild`. If it
goes wrong, `hearth rollback` (or pick an older entry at boot) brings the last
working system back.

Without installing anything, check the config still fits together, the same
way CI does (needs Nix):

```sh
cp ci/hardware-configuration.nix hardware-configuration.nix
echo '{ device = "laptop"; gpu = "intel"; }' > settings.local.nix
nix-instantiate '<nixpkgs/nixos>' -A system -I nixos-config=./configuration.nix
```

Both files are ignored by git. For hearth (Rust): `cd pkgs/hearth && cargo test`.
Scripts: `shellcheck -s bash pkgs/scripts/*.sh installer/install.sh`.

## How things fit

- **A feature is a module**: `modules/<name>.nix`. Add `mods/<name>` (an empty
  file) to have it on by default. Modules add apps through `my.packages` (so
  `removePackages` can drop any of them) and menu entries through
  `my.menu."Category"` — never edit the menu by hand.
- **Settings** go in `settings.nix` with a default and a comment saying what
  they do, and are read as `s.name or <default>` so older settings files keep
  working.
- **Small tools** are shell scripts in `pkgs/scripts/`, packaged in
  `pkgs/default.nix` with `sh` (which runs shellcheck at build time). Anything
  that runs often or needs to be quick belongs in `pkgs/hearth` (Rust, one
  binary, one file per subcommand).
- **Words matter**: messages, menu labels and comments are for people who may
  be new to Linux. Say what happened and what to do next, plainly.

## Pull requests

Keep one change per pull request, describe what it does and how you tried it,
and make sure CI is green. By contributing you agree your work is released
under the MIT license.
