# parajynx's look at boot (the boot menu and the splash while it starts).
# Change these, or drop your own pictures in this folder (see README.md);
# then rebuild. Nothing else needs touching.
{
  name = "parajynx";              # shown under the logo while it boots
  colors = {
    background = "#0e1013";       # the whole screen
    text = "#d7dae0";             # the name, the password prompt
    dim = "#6b7280";              # small print (boot menu countdown)
    accent = "#8aa4c8";           # the loading dots, the selected boot entry
  };
}
