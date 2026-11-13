# slowtyper — types text into whatever window has focus at a human pace
# (bnvac/slowtyper, its command-line half): uneven key timing, bursts,
# pauses after sentences, the odd typo fixed with backspace.
#
# From the menu (Super+Alt+Space → Apps & files): it asks how long the typing
# should take (a list, or type 7 / 1h30 / 60wpm), then counts down 8 s so you
# can click where the text should go (pkgs/scripts/slowtype.sh). In a terminal:
#   slowtyper -f essay.txt --minutes 20
#   xclip -selection clipboard -o | slowtyper -y --wpm 60
# While it types: F8 pauses/resumes, F9 stops, or move the mouse to the
# top-left corner. Off by default: `mod on slowtyper`.
{ pkgs, lib, ... }:
let
  slowtype = pkgs.writeShellApplication {
    name = "slowtype";
    runtimeInputs = with pkgs; [ slowtyper xclip larbs-dmenu libnotify gawk gnugrep coreutils ];
    text = builtins.readFile ../pkgs/scripts/slowtype.sh;
  };
in
{
  my.packages = [ pkgs.slowtyper slowtype ];
  my.menu."Apps & files" = lib.mkAfter [
    { label = "SlowTyper: type the clipboard (choose how long)"; run = "slowtype"; }
    { label = "SlowTyper: paste text, then type it (choose how long)"; run = "slowtype paste"; }
  ];
}
