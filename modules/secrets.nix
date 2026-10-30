# Secrets — keep passwords and keys OUT of this git repo, with sops-nix.
#
# This module is OFF by default (no mods/secrets marker) because it needs a
# one-time key setup before it does anything — enabling it with nothing set up
# is harmless but pointless. Turn it on with `mod on secrets` once you've done
# the steps below.
#
# How it works: secrets live encrypted in secrets/secrets.yaml (safe to commit).
# At activation sops-nix decrypts them to /run/secrets/<name>, readable only by
# the owner you name. The decryption key is an age key generated on this machine
# at /var/lib/sops-nix/key.txt — it never leaves the box and is not in git.
#
# Setup, once per machine:
#   1. `mod on secrets` and rebuild — this generates /var/lib/sops-nix/key.txt.
#   2. Get that key's PUBLIC half:
#        sudo age-keygen -y /var/lib/sops-nix/key.txt      # prints age1...
#   3. Put it in secrets/.sops.yaml as a recipient (see secrets/README.md), then
#        nix-shell -p sops --run 'sops secrets/secrets.yaml'
#      and add e.g.  restic-password: "your-passphrase"
#   4. Uncomment the matching line under `sops.secrets` below, and rebuild.
# Add a second machine by adding its public key as another recipient and
# re-encrypting (`sops updatekeys secrets/secrets.yaml`).
{ pkgs, lib, ... }:
let
  s = import ../settings.nix;
  sops-nix = builtins.fetchTarball {
    url = "https://github.com/Mic92/sops-nix/archive/60182817ee048ac94b4c68ea76d5ef2e8aac730d.tar.gz";
    sha256 = "sha256-Y/JIHTnMlOabDfyaSBubWGLDIVGihLEUuoMhFvQKaDo=";
  };
  sopsFile = ../secrets/secrets.yaml;
  haveSecrets = builtins.pathExists sopsFile;
in
{
  imports = [ "${sops-nix}/modules/sops" ];

  my.packages = with pkgs; [ sops age ];

  sops = lib.mkMerge [
    # Generate and use a machine-local age key (no SSH host key to derive from,
    # since openssh is off here).
    { age.keyFile = "/var/lib/sops-nix/key.txt"; age.generateKey = true; }
    (lib.mkIf haveSecrets {
      defaultSopsFile = sopsFile;
      # Uncomment each secret once it exists in secrets/secrets.yaml:
      # secrets.restic-password = { owner = s.username; mode = "0400"; };
      secrets = { };
    })
  ];
}
