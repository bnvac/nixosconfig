# lock — the lock screen: Super+Alt+l, sysact → lock, and automatically on
# suspend or after 10 idle minutes (xss-lock). Just your username and a
# password field on a plain dark screen — start typing to unlock.
# (xsecurelock: checks the password through PAM's `login` service, keeps the
# screen covered even if the auth window crashes, never shows your desktop.)
export XSECURELOCK_SHOW_USERNAME=1
export XSECURELOCK_SHOW_HOSTNAME=0
export XSECURELOCK_SHOW_DATETIME=0
export XSECURELOCK_SHOW_KEYBOARD_LAYOUT=0
export XSECURELOCK_PASSWORD_PROMPT=asterisks
export XSECURELOCK_DISCARD_FIRST_KEYPRESS=0     # the first key you press is part of the password
export XSECURELOCK_FONT="JetBrainsMono Nerd Font:size=16"
export XSECURELOCK_BACKGROUND_COLOR="#0b1a2e"
export XSECURELOCK_AUTH_BACKGROUND_COLOR="#0b1a2e"
export XSECURELOCK_AUTH_FOREGROUND_COLOR="#e8f0f8"
export XSECURELOCK_AUTH_WARNING_COLOR="#ff8a8a"
export XSECURELOCK_AUTH_TIMEOUT=60               # prompt hides after a minute idle; any key brings it back
export XSECURELOCK_BLANK_TIMEOUT=300             # screen off after 5 locked minutes
exec xsecurelock "$@"
