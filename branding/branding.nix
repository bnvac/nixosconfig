# MooreOS's look at boot and login: the boot menu, the splash while it
# starts, and the login screen. Change these, or the art next to them
# (see README.md), then rebuild. Nothing else needs touching.
{
  name = "MooreOS";                         # the system's name (window titles, the welcome window)
  tagline = "Moore Performance Industries"; # under the logo at boot and on the login screen
  colors = {
    background = "#060908";       # the whole screen: near-black with a hint of green
    text = "#c8f7dc";             # the password prompt, selected boot entry
    dim = "#2f6b4c";              # small print (countdown, tagline)
    accent = "#33ff99";           # phosphor green: dots, highlights, outlines
  };
}
