# slowtyper — types text into whatever window has focus at a human pace
# (bnvac/slowtyper, its command-line half): uneven key timing, bursts,
# pauses after sentences, the odd typo fixed with backspace.
#
# From the menu (Super+Alt+Space → Apps & files), or in a terminal:
#   slowtyper -f essay.txt --minutes 20
#   xclip -selection clipboard -o | slowtyper -y
# A countdown gives you time to click where the text should go. While it
# types: F8 pauses/resumes, F9 stops, or move the mouse to the top-left
# corner. Off by default: `mod on slowtyper`.
{ pkgs, lib, ... }:
let
  clip = "${pkgs.xclip}/bin/xclip -selection clipboard -o";
in
{
  my.packages = [ pkgs.slowtyper ];
  my.menu."Apps & files" = lib.mkAfter [
    { label = "SlowTyper: type what's on the clipboard"; mode = "term";
      run = "${clip} | slowtyper -y -d 8"; }
    { label = "SlowTyper: type what's on the clipboard, in N minutes"; mode = "term";
      run = ''printf 'Finish in how many minutes? '; read -r m; ${clip} | slowtyper -y -d 8 --minutes "$m"''; }
    { label = "SlowTyper: paste text, then type it"; run = "slowtyper -d 8"; mode = "term"; }
  ];
}
