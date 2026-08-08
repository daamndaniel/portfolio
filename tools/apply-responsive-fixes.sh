#!/usr/bin/env bash
#
# Re-apply the responsive fixes to the five exported pages.
#
# WHY THIS EXISTS
#   The site is a design-tool export. Re-exporting regenerates the five HTML
#   files from scratch, which deletes the hand-written media queries that make
#   the site work on a phone. Run this afterwards to put them back.
#
# USAGE
#   bash tools/apply-responsive-fixes.sh          # apply (idempotent)
#   bash tools/apply-responsive-fixes.sh --check   # verify only, change nothing
#
# The CSS lives in tools/responsive-fixes.css — edit it there, not in the HTML.
# Nothing runs at deploy time; this is a one-shot script you run by hand, so it
# does not turn the project into a build pipeline.
#
set -euo pipefail
cd "$(dirname "$0")/.."

CSS="tools/responsive-fixes.css"
PAGES=(index.html about.html sales-landing-cro.html stack-builders-website.html judged-sports-platform.html)
MARKER="RESPONSIVE FIXES"
CHECK_ONLY=0
[ "${1:-}" = "--check" ] && CHECK_ONLY=1

[ -f "$CSS" ] || { echo "FAIL: $CSS is missing"; exit 1; }

applied=0; already=0; missing=0
for f in "${PAGES[@]}"; do
  if [ ! -f "$f" ]; then echo "  MISSING  $f"; missing=$((missing+1)); continue; fi
  if grep -q "$MARKER" "$f"; then echo "  ok       $f (already patched)"; already=$((already+1)); continue; fi
  if [ $CHECK_ONLY -eq 1 ]; then echo "  NEEDS    $f"; continue; fi
  python3 - "$f" "$CSS" <<'PY'
import sys
page, cssfile = sys.argv[1], sys.argv[2]
html = open(page, encoding='utf-8').read()
css  = open(cssfile, encoding='utf-8').read()
# Insert immediately before the closing </style> of the FIRST <style> block that
# lives inside <helmet>. support.js preserves <style> there and hoists it to head.
h = html.find('<helmet>')
if h < 0: sys.exit(f'FAIL: no <helmet> in {page}')
s = html.find('<style>', h)
if s < 0: sys.exit(f'FAIL: no <style> inside <helmet> in {page}')
e = html.find('</style>', s)
if e < 0: sys.exit(f'FAIL: unterminated <style> in {page}')
open(page, 'w', encoding='utf-8').write(html[:e] + '\n' + css + html[e:])
PY
  echo "  patched  $f"
  applied=$((applied+1))
done

echo
echo "ASSERTIONS"
fail=0
assert() { if [ "$2" = "$3" ]; then echo "  ok   $1: $2"; else echo "  FAIL $1: got $2 expected $3"; fail=1; fi; }

# the block must appear exactly once per page
for f in "${PAGES[@]}"; do
  [ -f "$f" ] || continue
  assert "marker in $f" "$(grep -c "$MARKER" "$f" | tr -d ' ')" 1
done
# the toggle guard must never be collapsed: the collapse rule targets gap:1px only
assert "collapse rule targets gap:1px only" \
  "$(grep -c 'grid-template-columns: 1fr 1fr; gap: 2px !important' index.html | tr -d ' ')" 0
# trap #2: no transform/opacity in an !important rule (would break the reveal observer)
assert "no transform/opacity !important" \
  "$(grep -E '!important' "$CSS" | grep -cE '\b(transform|opacity)\s*:' | tr -d ' ')" 0

[ $fail -eq 0 ] && echo "ALL ASSERTIONS PASSED" || { echo "FAILED — inspect before committing"; exit 1; }
echo
echo "applied=$applied already=$already missing=$missing"
echo "Now verify in a browser at 375px and 1425px — see the checklist in $CSS."
