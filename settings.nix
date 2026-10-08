# The few values you'd actually change. Imported by the modules.
{
  username = "samadams";
  fullName = "Sam Adams";
  hostName = "live";
  timeZone = "America/New_York";

  stAlpha = "0.72";          # terminal transparency (1.0 = opaque)

  # Boot. espMountPoint must match hardware-configuration.nix (checked at build).
  espMountPoint = "/boot/efi";
  useGrub = true;            # GRUB = themeable; false = systemd-boot
}
