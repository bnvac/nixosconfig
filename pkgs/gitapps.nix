# Build recipes for settings.gitApps: any git repo, built by type.
#   rust    cargo, with the repo's own Cargo.lock
#   go      Go modules (update-mine works out vendorHash)
#   node    npm, with the repo's package-lock.json (update-mine works out npmDepsHash)
#   python  a pyproject app; list PyPI deps by nixpkgs name in pythonDeps
#   make    `make install PREFIX=…` (C/C++ and friends); add buildInputs by name
#   script  installs the repo's executable files (or `files = [ … ]`) as commands
#   docker  nothing to build — the platform module runs its compose file
# Only apps that already have a pinned commit are built; a brand-new one gets
# its first pin from update-mine (which `rebuild` runs before building).
{ final, prev, tracked, fetchPinned }:
let
  inherit (prev) lib;
  s = import ../settings.nix;
  apps = s.gitApps or { };

  build = n: a: t:
    let
      src = fetchPinned t t.pin;
      version = "0-git-${builtins.substring 0 7 t.pin.rev}";
      bin = a.bin or n;
      meta = { mainProgram = bin; description = "${n} (${t.url})"; };
      byName = map (x: lib.getAttrFromPath (lib.splitString "." x) final);
      common = {
        pname = n;
        inherit version src meta;
        nativeBuildInputs = byName (a.nativeBuildInputs or [ ]);
        buildInputs = byName (a.buildInputs or [ ]);
      };
      recipes = {
        rust = prev.rustPlatform.buildRustPackage (common // {
          cargoLock.lockFile = "${src}/Cargo.lock";
          doCheck = false;
        });
        go = prev.buildGoModule (common // {
          inherit (t.pin) vendorHash;
          doCheck = false;
        } // lib.optionalAttrs (a ? subPackages) { inherit (a) subPackages; });
        node = prev.buildNpmPackage (common // {
          inherit (t.pin) npmDepsHash;
          dontNpmBuild = !(a.npmBuild or true);
        });
        python = final.python3Packages.buildPythonApplication (common // {
          pyproject = true;
          build-system = with final.python3Packages; [ setuptools hatchling poetry-core flit-core ];
          dependencies = map (d: final.python3Packages.${d}) (a.pythonDeps or [ ]);
          doCheck = false;
        });
        make = prev.stdenv.mkDerivation (common // {
          makeFlags = [ "PREFIX=$(out)" ] ++ (a.makeFlags or [ ]);
        });
        script = prev.runCommand "${n}-${version}" { inherit meta; } ''
          mkdir -p $out/bin
          cd ${src}
          ${if a ? files
            then lib.concatMapStrings (f: ''
              install -Dm755 ${lib.escapeShellArg f} "$out/bin/$(basename ${lib.escapeShellArg f})"
            '') a.files
            else ''
              for f in bin/* *; do
                if [ -f "$f" ] && [ -x "$f" ]; then install -Dm755 "$f" "$out/bin/$(basename "$f")"; fi
              done
            ''}
          patchShebangs $out/bin
        '';
        docker = src;
      };
      type = a.type or "script";
    in
    recipes.${type} or (throw "gitApps.${n}: unknown type \"${type}\" (rust, go, node, python, make, script, docker)");

  buildable = lib.filterAttrs
    (n: _: tracked ? ${n} && !tracked.${n}.builtin && tracked.${n}.pin != null)
    apps;
in
lib.mapAttrs (n: a: build n a tracked.${n}) buildable
