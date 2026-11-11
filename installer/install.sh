# nix2-install — put nix² on this computer, from the installer USB.
#
# Asks which disk to use (and erases it — it says so twice), whether to
# encrypt it, and a few questions about you; then installs. Needs internet
# (the packages download) and a computer booted in UEFI mode.

repo_url=${NIX2_REPO:-https://github.com/bnvac/nixosconfig}
src=${NIX2_SRC:-/etc/nix2-src}   # the copy of nix² on this USB (used offline)
mnt=${NIX2_MNT:-/mnt}              # where the new system is assembled

say() { printf '\n\033[1m%s\033[0m\n' "$*"; }
die() { printf '\n\033[31m%s\033[0m\n' "$*" >&2; exit 1; }
ask() { local a; read -r -p "$1 " a </dev/tty || a=""; printf '%s' "$a"; }

[ "$(id -u)" -eq 0 ] || exec sudo "$0" "$@"

say "nix² installer"
echo "This puts nix² on a disk of this computer. You'll pick the disk,"
echo "and everything on it will be erased."

# ── checks ──────────────────────────────────────────────────────────────────
[ -d /sys/firmware/efi ] || die "This computer started in legacy (BIOS) mode. nix² needs UEFI:
turn on UEFI boot in the firmware settings (often F2/Del at power-on), then boot the USB again."

until curl -fsS --max-time 8 -o /dev/null https://cache.nixos.org/nix-cache-info; do
  echo
  echo "No internet yet (the install downloads packages)."
  echo "  Wi-Fi: a menu opens — pick your network, then Quit."
  echo "  Cable: just plug it in."
  a=$(ask "Press Enter to set up Wi-Fi (or type c when a cable is plugged in):")
  [ "$a" = c ] || nmtui connect || true
done
echo "Internet: connected."

# ── disk ────────────────────────────────────────────────────────────────────
usb=""
iso_src=$(findmnt -no SOURCE /iso 2>/dev/null || true)
[ -n "$iso_src" ] && usb=$(lsblk -no PKNAME "$iso_src" 2>/dev/null | head -1)

mapfile -t disks < <(lsblk -dnpo NAME,TYPE | awk '$2 == "disk" {print $1}' \
  | grep -vE '/dev/(loop|zram|sr|ram)' | grep -vx "/dev/${usb:-none}" || true)
# Testing in a VM or on a disk image: NIX2_DISKS="/dev/loop0" offers only those.
[ -n "${NIX2_DISKS:-}" ] && read -ra disks <<<"$NIX2_DISKS"
[ "${#disks[@]}" -gt 0 ] || die "No disk found to install on."

say "Which disk should nix² go on?"
for i in "${!disks[@]}"; do
  d=${disks[$i]}
  printf '  %d  %-14s %s\n' "$((i + 1))" "$d" "$(lsblk -dno SIZE,MODEL "$d" | xargs)"
  lsblk -no NAME,SIZE,FSTYPE,LABEL "$d" | tail -n +2 | sed 's/^/        /'
done
n=$(ask "Number:")
[[ "$n" =~ ^[0-9]+$ ]] && [ "$n" -ge 1 ] && [ "$n" -le "${#disks[@]}" ] || die "Not one of those — nothing was changed."
disk=${disks[$((n - 1))]}

about=$(lsblk -dno SIZE,MODEL "$disk" | xargs)
say "EVERYTHING on $disk ($about) will be erased."
a=$(ask "Type the disk's name ($(basename "$disk")) to erase it, anything else to stop:")
[ "$a" = "$(basename "$disk")" ] || die "Stopped — nothing was changed."

a=$(ask "Encrypt the disk? Your files stay private if the computer is lost; you type a password at every start. [Y/n]")
case "$a" in n | N | no) encrypt=false ;; *) encrypt=true ;; esac

# ── partition, format, mount ────────────────────────────────────────────────
say "Partitioning $disk …"
umount -R "$mnt" 2>/dev/null || true
wipefs -af "$disk" >/dev/null
parted -s "$disk" -- mklabel gpt \
  mkpart ESP fat32 1MiB 1GiB set 1 esp on \
  mkpart nix2 1GiB 100%
udevadm settle 2>/dev/null || sleep 2
mapfile -t parts < <(lsblk -lnpo NAME,TYPE "$disk" | awk '$2 == "part" {print $1}')
esp=${parts[0]:?no EFI partition}; root=${parts[1]:?no root partition}

mkfs.fat -F 32 -n ESP "$esp" >/dev/null
if $encrypt; then
  say "Choose the disk password (asked at every start — don't lose it):"
  until cryptsetup luksFormat --type luks2 -q "$root" </dev/tty; do echo "Try again."; done
  echo "Type it once more to unlock:"
  until cryptsetup open "$root" nix2 </dev/tty; do echo "Try again."; done
  rootdev=/dev/mapper/nix2
else
  rootdev=$root
fi
mkfs.ext4 -q -F -L nix2 "$rootdev"
mount "$rootdev" "$mnt"
mkdir -p "$mnt/boot"
mount -o umask=077 "$esp" "$mnt/boot"

# ── the config ──────────────────────────────────────────────────────────────
say "Setting up nix²'s config …"
nixos-generate-config --root "$mnt" >/dev/null
hw=$(mktemp); cp "$mnt/etc/nixos/hardware-configuration.nix" "$hw"
rm -rf "$mnt/etc/nixos"
if git clone -q "$repo_url" "$mnt/etc/nixos" 2>/dev/null; then
  echo "Got the newest nix² from $repo_url"
else
  echo "Couldn't reach $repo_url — using the copy on this USB."
  cp -r "$src" "$mnt/etc/nixos"; chmod -R u+w "$mnt/etc/nixos"
  git -C "$mnt/etc/nixos" init -q && git -C "$mnt/etc/nixos" remote add origin "$repo_url"
  git -C "$mnt/etc/nixos" add -A && git -C "$mnt/etc/nixos" -c user.name=nix2 -c user.email=nix2@localhost commit -qm "nix² (from the installer)"
fi
cp "$hw" "$mnt/etc/nixos/hardware-configuration.nix"

say "About you and this computer"
bash "$mnt/etc/nixos/pkgs/scripts/setup.sh" --root "$mnt"
user=$(bash "$mnt/etc/nixos/pkgs/scripts/setup.sh" --root "$mnt" get username)

# ── install ─────────────────────────────────────────────────────────────────
say "Installing — this downloads a few GB and takes a while. Go get a snack."
nixos-install --root "$mnt" --no-root-passwd || die "The install failed (see above). Fix it and run nix2-install again."

say "Choose the password for $user (to log in and for sudo):"
until nixos-enter --root "$mnt" -c "passwd $user" </dev/tty; do echo "Try again."; done

say "Done! Take out the USB stick and restart: reboot"
echo "After logging in: Super+Alt+Space opens the menu, Super+Alt+F1 lists the keys,"
echo "and \`mod list\` shows the modules you can switch on."
