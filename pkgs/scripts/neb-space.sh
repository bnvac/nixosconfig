# neb-space — Super+Alt+Shift+n. dwm switches the view to Neb's workspace
# (tag 9) in the same keypress; this opens his terminal there if it isn't
# open already. Inside it, press Enter on an empty line to talk out loud.
if ! xdotool search --classname '^neb$' >/dev/null 2>&1; then
  setsid -f "${TERMINAL:-st}" -n neb -t neb -e neb tui >/dev/null 2>&1
fi
