#!/usr/bin/env bash
#
# Shrink assets/ without changing how anything looks at its displayed size.
#
#   bash tools/optimize-assets.sh          # optimise in place (idempotent)
#   bash tools/optimize-assets.sh --dry    # report what it would do
#
# WHY
#   The export shipped ~22MB of assets, most of it two kinds of waste:
#     1. images stored far larger than they are ever displayed
#        (daniel-portrait.jpg was 2688x4033 for a 393px box — 6.8x oversampled)
#     2. photographic content stored as PNG
#        (sb-before.png was 1.94MB; the same pixels as JPEG q88 are 0.48MB)
#
# HOW THE TARGET WIDTHS WERE CHOSEN
#   Every width below is 2x the LARGEST rendered box that asset occupies, measured
#   in a browser at a 1600px viewport with all tab panels forced visible. 2x is the
#   retina factor, so nothing softens on a high-DPI screen. The site's content
#   column caps at 1280px, so 2560 is the widest any full-bleed image needs.
#     covers, before/after   1280 CSS -> 2560
#     approach shots          884 CSS -> 1800
#     work cards              826 CSS -> 1700
#     portrait                393 CSS ->  900
#     minis                   148 CSS ->  400
#   Panels (1000px) and the discipline stills (560px) are already at or below their
#   2x target, so they are only re-encoded, never resized.
#
# WHICH FILES STAY PNG — AND A MISTAKE THIS ENCODES
#   A PNG keeps its format only if it has REAL transparency, decided by
#   tools/png-min-alpha.py: minimum alpha below ALPHA_FLOOR (250) means keep.
#
#   Two wrong tests were tried first, and the second cost real bytes:
#     `sips -g hasAlpha`   — useless. Reports "yes" for a merely PRESENT channel,
#                            and said yes to all 27 PNGs, none of which needed it.
#     counting non-opaque  — plausible but still wrong. It found 828,677 non-opaque
#       pixels             pixels in sb-cover.png, so three files were left as PNG
#                            and ~4.2MB was left behind. Every one of those pixels
#                            had alpha 254: a 0.4% deviation, invisible, an export
#                            artefact. Counting answers "how many differ", not "by
#                            how much", and only the second question matters.
#   Minimum alpha across every PNG here is 254, so in practice all 27 convert. The
#   check stays in place so a genuinely transparent asset in a future export is
#   protected automatically instead of relying on this comment.
#
# SAFETY
#   Destructive to assets/, but the untouched originals live in the handoff at
#   ~/Downloads/design_handoff_portfolio_site/site/assets (verified byte-identical
#   before the first run). Recover with:
#     cp ~/Downloads/design_handoff_portfolio_site/site/assets/* assets/
#   Uses only `sips`, which ships with macOS — no new dependency, no build step.
#
# ORDER
#   Run this BEFORE tools/apply-responsive-fixes.sh. That script rewrites the
#   HTML's assets/*.png references to .jpg, but ONLY for files that actually exist
#   as .jpg — so if you re-export and forget to run this, references stay .png and
#   the site still works, just heavy.
#
set -euo pipefail
cd "$(dirname "$0")/.."
[ -d assets ] || { echo "FAIL: no assets/ directory"; exit 1; }
command -v sips >/dev/null || { echo "FAIL: sips not found (macOS only)"; exit 1; }

DRY=0; [ "${1:-}" = "--dry" ] && DRY=1
QUALITY=88          # visually clean on UI screenshots; 82 showed ringing on text
ALPHA_FLOOR=250     # min alpha below this = real transparency, keep PNG
ALPHA_TOOL="tools/png-min-alpha.py"
[ -f "$ALPHA_TOOL" ] || { echo "FAIL: $ALPHA_TOOL is missing"; exit 1; }

target_width() {
  case "$1" in
    *-cover.png|*-cover.jpg|*-before.png|*-before.jpg) echo 2560 ;;
    *-approach-*)                                      echo 1800 ;;
    *-card.png|*-card.jpg)                             echo 1700 ;;
    *-mini.png|*-mini.jpg)                             echo  400 ;;
    daniel-portrait.jpg)                               echo  900 ;;
    *)                                                 echo    0 ;;
  esac
}

# ---------------------------------------------------------------------------
# OPEN GRAPH SHARE CARD
#   assets/og-share.jpg is the 1200x630 image LinkedIn, Slack and iMessage show
#   when the site is pasted as a link. It is committed to the repo, so this only
#   rebuilds it if it has gone missing.
#
#   It cannot be derived from assets/daniel-portrait.jpg: that file is 600x900,
#   below the 1200px minimum for a large card AND the wrong shape (0.67:1 against
#   the 1.91:1 unfurlers crop to). Left alone, LinkedIn would centre-crop a
#   low-resolution portrait — which lands on the chest, not the face. So the card
#   is cut from the 2688x4033 ORIGINAL in the handoff instead.
#
#   The crop: a 1.91:1 band is 1411px tall at the original's full 2688px width,
#   and the head occupies y=747..1730, so the band has to start at 620 to hold the
#   whole face with headroom above and the sweater below. Offset 300 was tried
#   first and sliced the chin off. Nothing about this is derivable — it was read
#   off the image — hence the numbers being written down here.
# ---------------------------------------------------------------------------
OG_SHARE="assets/og-share.jpg"
OG_SRC="$HOME/Downloads/design_handoff_portfolio_site/site/assets/daniel-portrait.jpg"
if [ ! -f "$OG_SHARE" ]; then
  if [ -f "$OG_SRC" ] && [ "$DRY" = "0" ]; then
    tmp=$(mktemp -t ogshare).jpg
    sips -c 1411 2688 --cropOffset 620 0 "$OG_SRC" --out "$tmp" >/dev/null
    sips -z 630 1200 -s format jpeg -s formatOptions "$QUALITY" "$tmp" --out "$OG_SHARE" >/dev/null
    rm -f "$tmp"
    echo "  built $OG_SHARE (1200x630 from the 2688x4033 original)"
  else
    echo "  WARN $OG_SHARE missing and the handoff original is not at:"
    echo "       $OG_SRC"
    echo "       Restore the file from git rather than regenerating it from assets/."
  fi
fi

before=$(du -sk assets | cut -f1)
changed=0; skipped=0

for path in assets/*; do
  f=$(basename "$path")
  [ -f "$path" ] || continue
  case "$f" in *.png|*.jpg|*.jpeg) ;; *) continue ;; esac
  # og-share.jpg is already at its exact required size; target_width() would match
  # it on no rule and skip it anyway, but say so explicitly so a future pattern
  # (e.g. one matching *-share.jpg) cannot start resampling the share card.
  case "$f" in og-*) skipped=$((skipped+1)); continue ;; esac

  t=$(target_width "$f")
  w=$(sips -g pixelWidth "$path" 2>/dev/null | awk '/pixelWidth/{print $2}')
  [ -n "$w" ] || { echo "  skip (unreadable): $f"; skipped=$((skipped+1)); continue; }

  keep=0
  if [ "${f##*.}" = "png" ]; then
    a=$(python3 "$ALPHA_TOOL" "$path")
    [ "$a" -lt "$ALPHA_FLOOR" ] && keep=1
  fi
  ext="${f##*.}"
  to_jpeg=0
  [ "$ext" = "png" ] && [ "$keep" = "0" ] && to_jpeg=1

  do_resize=0
  [ "$t" != "0" ] && [ "$w" -gt "$t" ] && do_resize=1

  if [ "$to_jpeg" = "0" ] && [ "$do_resize" = "0" ]; then
    skipped=$((skipped+1)); continue
  fi

  if [ "$DRY" = "1" ]; then
    msg="$f  ${w}px"
    [ "$do_resize" = "1" ] && msg="$msg -> ${t}px"
    [ "$to_jpeg" = "1" ]   && msg="$msg  png->jpg"
    echo "  would: $msg"
    changed=$((changed+1)); continue
  fi

  if [ "$to_jpeg" = "1" ]; then
    out="assets/${f%.png}.jpg"
    if [ "$do_resize" = "1" ]; then
      sips -Z "$t" -s format jpeg -s formatOptions "$QUALITY" "$path" --out "$out" >/dev/null
    else
      sips -s format jpeg -s formatOptions "$QUALITY" "$path" --out "$out" >/dev/null
    fi
    rm -f "$path"
  else
    sips -Z "$t" "$path" --out "$path" >/dev/null
  fi
  changed=$((changed+1))
done

after=$(du -sk assets | cut -f1)
echo
if [ "$DRY" = "1" ]; then
  echo "dry run: $changed file(s) would change, $skipped already fine"
else
  echo "changed=$changed  unchanged=$skipped"
  printf "assets/: %d KB -> %d KB  (%.0f%% smaller)\n" "$before" "$after" \
    "$(echo "scale=4;(1-$after/$before)*100" | bc)"
  echo
  echo "Next: bash tools/apply-responsive-fixes.sh   # points the HTML at the .jpg files"
fi
