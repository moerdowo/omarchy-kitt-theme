#!/bin/bash
# Rebuild the procedural KITT backgrounds (2-5 and omarchy.png) with ImageMagick.
# 1-kitt-jump.png is composed from a source photo and is not regenerated here.
set -euo pipefail

W=${W:-2880}; H=${H:-1800}
OUT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/backgrounds"
BG='#0a0a0c'; RED='#ff2a1c'; DIMRED='#4a0d07'; AMBER='#ffb347'
mkdir -p "$OUT"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT

# --- helpers ---------------------------------------------------------------
# 1-D gaussian profiles; the full-size mask is their outer product, which is
# far cheaper than evaluating -fx over 5.2M pixels.
hgauss() { magick -size ${W}x1 xc:black -fx "exp(-pow((i/w-$1)/$2,2))" "$T/$3"; }
vgauss() { magick -size 1x${H} xc:black -fx "exp(-pow((j/h-$1)/$2,2))" "$T/$3"; }
mask()   { magick \( "$T/$1" -resize ${W}x${H}\! \) \( "$T/$2" -resize ${W}x${H}\! \) \
             -compose multiply -composite -colorspace Gray "$T/$3"; }
layer()  { magick -size ${W}x${H} xc:"$2" \( "$T/$1" -evaluate multiply "$3" \) \
             -alpha off -compose copy_opacity -composite "$T/$4"; }
save()   { magick "$1" -depth 8 -define png:compression-level=9 "$2"; echo "  $(basename "$2")"; }

magick -size 1x3 xc:none -fill '#00000059' -draw 'point 0,0' "$T/sl.png"
magick -size ${W}x${H} tile:"$T/sl.png" "$T/scanlines.png"
magick -size ${W}x${H} radial-gradient:white-black -sigmoidal-contrast 4,55% "$T/vig.png"

# --- 2. Scanner ------------------------------------------------------------
hgauss 0.5 0.34   h_wide.png
hgauss 0.5 0.20   h_mid.png
hgauss 0.5 0.09   h_core.png
vgauss 0.5 0.075  v_bloom.png
vgauss 0.5 0.0135 v_bar.png
vgauss 0.5 0.0045 v_hot.png
mask h_wide.png v_bloom.png m_bloom.png
mask h_mid.png  v_bar.png   m_bar.png
mask h_core.png v_hot.png   m_hot.png
layer m_bloom.png "$RED"    0.42 l_bloom.png
layer m_bar.png   "$RED"    1.0  l_bar.png
layer m_hot.png   '#fff0ea' 0.95 l_hot.png
magick -size ${W}x${H} xc:"$BG" \
  "$T/l_bloom.png"   -compose screen   -composite \
  "$T/l_bar.png"     -compose screen   -composite \
  "$T/l_hot.png"     -compose screen   -composite \
  "$T/scanlines.png" -compose over     -composite \
  "$T/vig.png"       -compose multiply -composite "$T/o1.png"
save "$T/o1.png" "$OUT/2-scanner.png"

# --- 3. Voice modulator ----------------------------------------------------
BARS=17; BW=52; GAP=44
TOTAL=$(( BARS*BW + (BARS-1)*GAP )); X0=$(( (W-TOTAL)/2 )); CY=$(( H/2 ))
HEIGHTS=(0.18 0.31 0.52 0.44 0.70 0.86 0.62 0.95 0.74 0.95 0.58 0.83 0.66 0.41 0.49 0.28 0.16)
d=""
for i in $(seq 0 $((BARS-1))); do
  x=$(( X0 + i*(BW+GAP) ))
  hh=$(awk -v f="${HEIGHTS[$i]}" 'BEGIN{printf "%d", f*520}')
  d+=" roundrectangle $x,$((CY-hh)) $((x+BW)),$((CY+hh)) 8,8"
done
magick -size ${W}x${H} xc:black -fill white -draw "$d" "$T/bars.png"
magick "$T/bars.png" -blur 0x44 -evaluate multiply 0.9 "$T/bars_glow.png"
magick "$T/bars.png" -blur 0x3 "$T/bars_soft.png"
layer bars_glow.png "$RED" 0.85 l_glow.png
magick -size ${W}x${H} xc:"$RED" "$T/bars.png" -alpha off -compose copy_opacity -composite "$T/l_bars.png"
hgauss 0.5 0.34  h_wash.png
vgauss 0.5 0.016 v_wash.png
mask h_wash.png v_wash.png m_wash.png
# the amber midline must be masked BY the bars, not replace their mask
magick "$T/m_wash.png" "$T/bars_soft.png" -compose multiply -composite -colorspace Gray "$T/m_tips.png"
layer m_tips.png "$AMBER" 0.75 l_wash.png
magick -size ${W}x${H} xc:"$BG" \
  "$T/l_glow.png"    -compose screen   -composite \
  "$T/l_bars.png"    -compose over     -composite \
  "$T/l_wash.png"    -compose screen   -composite \
  "$T/scanlines.png" -compose over     -composite \
  "$T/vig.png"       -compose multiply -composite "$T/o2.png"
save "$T/o2.png" "$OUT/3-voice-modulator.png"

# --- 4. Night highway ------------------------------------------------------
HZ=$(( H * 46 / 100 )); VX=$(( W / 2 ))
grid=""
for k in $(seq -22 22); do grid+=" line $VX,$HZ $(( VX + k*190 )),$H"; done
for n in $(seq 1 26); do
  y=$(awk -v hz="$HZ" -v hh="$H" -v n="$n" 'BEGIN{printf "%d", hz + (hh-hz)*(1-exp(-n/5.2))}')
  [ "$y" -ge "$H" ] && continue
  grid+=" line 0,$y $W,$y"
done
magick -size ${W}x${H} xc:black -stroke "$RED" -strokewidth 3 -fill none -draw "$grid" "$T/grid.png"
magick -size 1x${H} xc:black \
  -fx "j/h<${HZ}.0/${H}.0 ? 0 : min(1,(j/h-${HZ}.0/${H}.0)*3.4)" "$T/gridfade.png"
magick "$T/grid.png" \( "$T/gridfade.png" -resize ${W}x${H}\! \) \
  -compose multiply -composite -evaluate multiply 0.55 "$T/grid_faded.png"
hgauss 0.5 0.55 h_hz.png
magick -size 1x${H} xc:black -fx "exp(-pow((j/h-${HZ}.0/${H}.0)/0.055,2))" "$T/v_hz.png"
magick -size 1x${H} xc:black -fx "exp(-pow((j/h-${HZ}.0/${H}.0)/0.006,2))" "$T/v_hzhot.png"
mask h_hz.png   v_hz.png    m_hz.png
mask h_core.png v_hzhot.png m_hzhot.png
layer m_hz.png    "$RED"    0.85 l_hz.png
layer m_hzhot.png '#ffe8e0' 0.9  l_hzhot.png
magick -size ${W}x${H} xc:"$BG" \
  "$T/grid_faded.png" -compose screen   -composite \
  "$T/l_hz.png"       -compose screen   -composite \
  "$T/l_hzhot.png"    -compose screen   -composite \
  "$T/scanlines.png"  -compose over     -composite \
  "$T/vig.png"        -compose multiply -composite "$T/o3.png"
save "$T/o3.png" "$OUT/4-night-highway.png"

# --- 5. Black on black -----------------------------------------------------
# noise is generated small and stretched; at full size it is punishingly slow
magick -size 720x450 xc:gray50 -attenuate 1.0 +noise Gaussian -colorspace Gray \
  -motion-blur 0x14+22 -auto-level -resize ${W}x${H}\! -evaluate multiply 0.11 "$T/sheen.png"
magick -size ${W}x${H} xc:"$BG" "$T/sheen.png" -compose screen -composite "$T/brushed.png"
hgauss 0.5   0.28   h_lo.png
vgauss 0.735 0.0065 v_lo.png
vgauss 0.735 0.045  v_lobloom.png
mask h_lo.png   v_lo.png      m_lo.png
mask h_wide.png v_lobloom.png m_lobloom.png
layer m_lobloom.png "$DIMRED" 0.9 l_lobloom.png
layer m_lo.png      "$RED"    1.0 l_lo.png
magick "$T/brushed.png" \
  "$T/l_lobloom.png" -compose screen   -composite \
  "$T/l_lo.png"      -compose screen   -composite \
  "$T/vig.png"       -compose multiply -composite "$T/o4.png"
save "$T/o4.png" "$OUT/5-black-on-black.png"

# --- omarchy logo plate ----------------------------------------------------
PLATE=/usr/share/omarchy/themes/retro-82/backgrounds/omarchy.png
if [[ -f $PLATE ]]; then
  magick "$PLATE" -fuzz 8% -fill "$BG" -opaque '#05182E' \
                  -fuzz 8% -fill "$RED" -opaque '#FAA968' -depth 8 "$OUT/omarchy.png"
  echo "  omarchy.png"
fi
