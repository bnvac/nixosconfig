# secrets/

Encrypted secrets for the `secrets` module (sops-nix). Everything here is safe
to commit — the values are encrypted; only machines holding the matching age
key can read them. The decryption key itself is **never** in git (it lives at
`/var/lib/sops-nix/key.txt` on each machine).

The module is off by default. Full setup is in `modules/secrets.nix`; the short
version:

1. `mod on secrets` and rebuild — generates `/var/lib/sops-nix/key.txt`.
2. `sudo age-keygen -y /var/lib/sops-nix/key.txt` → prints this machine's public
   key (`age1...`).
3. Create `.sops.yaml` here, listing that key as a recipient:

   ```yaml
   keys:
     - &desktop age1xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
     # - &laptop  age1yyyy...        # add the laptop's key the same way
   creation_rules:
     - path_regex: secrets\.yaml$
       key_groups:
         - age:
             - *desktop
             # - *laptop
   ```

4. `nix-shell -p sops --run 'sops secrets/secrets.yaml'` and add entries, e.g.

   ```yaml
   restic-password: "a-long-passphrase-you-keep-a-copy-of"
   ```

5. Uncomment the matching `sops.secrets.*` line in `modules/secrets.nix` and
   rebuild. The secret appears at `/run/secrets/<name>`.

To add the second machine later: add its public key as another recipient above
and run `sops updatekeys secrets/secrets.yaml`.
