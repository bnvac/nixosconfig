# Draws the default wallpaper: a snowy night — starry gradient sky, two ranges
# of blue hills, pines, snowdrifts, a few big still flakes. xsnow adds the live
# falling snow on top at runtime. Usage: snow-wallpaper.sh OUT.png [W H]
out=$1; W=${2:-3840}; H=${3:-2160}
sx() { echo $(( $1 * W / 3840 )); }    # design coordinates are 3840x2160
sy() { echo $(( $1 * H / 2160 )); }

pine() {   # pine X Y SCALE% COLOUR  — three stacked triangles
  local x=$1 y=$2 s=$3 c=$4 t
  for t in "260 70 120" "200 95 50" "130 120 -20"; do
    # shellcheck disable=SC2086  # splitting the triple into $1 $2 $3 is the point
    set -- $t
    args+=(-fill "$c" -draw "polygon $(sx "$x"),$(sy $((y - $1 * s / 100))) $(sx $((x - $2 * s / 100))),$(sy $((y - $3 * s / 100))) $(sx $((x + $2 * s / 100))),$(sy $((y - $3 * s / 100)))")
  done
}
specks() { # specks SEED THRESHOLD% DILATE BLUR STRENGTH — sparse soft white dots
  args+=( '(' -size "${W}x${H}" xc:black -seed "$1" +noise Random -channel G -separate +channel
          -threshold "$2%" -morphology Dilate "Disk:$3" -blur "0x$4" -evaluate multiply "$5" ')'
          -compose screen -composite -compose over )
}

args=(-size "${W}x${H}" gradient:'#060d1a-#2a4566')
specks 7 99.93 1 0.6 0.55                                   # stars
args+=(-fill '#33507a' -draw "polygon 0,$(sy 1500) $(sx 520),$(sy 1180) $(sx 900),$(sy 1360) $(sx 1350),$(sy 1120) $(sx 1900),$(sy 1420) $(sx 2400),$(sy 1150) $(sx 2950),$(sy 1380) $(sx 3400),$(sy 1190) $W,$(sy 1420) $W,$H 0,$H")
args+=(-fill '#4a6890' -draw "polygon 0,$(sy 1640) $(sx 700),$(sy 1420) $(sx 1300),$(sy 1600) $(sx 2000),$(sy 1440) $(sx 2700),$(sy 1620) $(sx 3300),$(sy 1460) $W,$(sy 1600) $W,$H 0,$H")
pine 420 1660 70 '#20344d'; pine 610 1690 55 '#20344d'
pine 3080 1650 75 '#20344d'; pine 3290 1680 60 '#20344d'; pine 3460 1700 50 '#20344d'
args+=( '(' -size "${W}x${H}" xc:none
        -fill '#cfdcea' -draw "ellipse $(sx 900),$(sy 2250) $(sx 1700),$(sy 520) 180,360"
        -draw "ellipse $(sx 3100),$(sy 2300) $(sx 1900),$(sy 560) 180,360"
        -fill '#e9f1f8' -draw "ellipse $(sx 2000),$(sy 2420) $(sx 2600),$(sy 560) 180,360"
        -blur 0x3 ')' -composite )                           # snowdrifts
pine 250 1900 120 '#111e2e'; pine 3600 1880 130 '#111e2e'; pine 3420 1930 95 '#111e2e'
specks 11 99.97 2 1.2 0.7                                   # big still flakes
magick "${args[@]}" -depth 8 -define png:color-type=2 "$out"
