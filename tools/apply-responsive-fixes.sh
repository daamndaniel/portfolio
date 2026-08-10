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
JS="tools/mobile-menu.js"
JS2="tools/i18n-title.js"
JS3="tools/a11y-controls.js"
DROP="tools/drop-sections.py"
PAGES=(index.html about.html sales-landing-cro.html stack-builders-website.html judged-sports-platform.html)
MARKER="RESPONSIVE FIXES"
JS_MARKER="data-mobile-menu"
JS2_MARKER="data-i18n-title"
JS3_MARKER="data-a11y-controls"
CHECK_ONLY=0
[ "${1:-}" = "--check" ] && CHECK_ONLY=1

[ -f "$CSS" ] || { echo "FAIL: $CSS is missing"; exit 1; }
[ -f "$JS"  ] || { echo "FAIL: $JS is missing";  exit 1; }
[ -f "$JS2" ] || { echo "FAIL: $JS2 is missing"; exit 1; }
[ -f "$JS3" ] || { echo "FAIL: $JS3 is missing"; exit 1; }
[ -f "$DROP" ] || { echo "FAIL: $DROP is missing"; exit 1; }

# ---------------------------------------------------------------------------
# TOKEN FIXES — contrast failures that cannot be fixed from the stylesheet.
#
# These are byte substitutions in the exported markup, not CSS overrides, for a
# specific reason: the failing declarations carry a var() (e.g.
# `rgba(var(--pgrgb, 242,241,236),.5)`), and an [style*="…"] selector written
# from the source bytes matches nothing once support.js re-serialises the
# attribute through the CSSOM. Editing the value is the only reliable route, and
# putting it here keeps it re-runnable after a re-export.
#
# Every ratio below was computed twice (independently) from the WCAG relative
# luminance formula, in BOTH themes.
# ---------------------------------------------------------------------------
token_fixes() {
  local f="$1"
  python3 - "$f" <<'PY'
import sys, re as _re
p=sys.argv[1]; s=open(p,encoding='utf-8').read(); n=0

# 1. Eyebrow/index labels inside inverted panels. Both the panel background and
#    this token invert with the theme, so alpha .5 flips from 4.83:1 (light,
#    barely) to 3.40:1 (dark, FAIL at 12px/400). .66 gives 7.58:1 light and
#    5.70:1 dark, and folds a one-off alpha into the .66 step already used by
#    ~310 other labels. All 17 uses are `color:` — verified, none are
#    background or border, so raising it cannot darken a fill.
a='color: rgba(var(--pgrgb, 242,241,236),.5)'
b='color: rgba(var(--pgrgb, 242,241,236),.66)'
n+=s.count(a); s=s.replace(a,b)

# 2. Hardcoded #FFF on the accent. --acc inverts (#1B3BD8 light -> #7E97FF dark)
#    but #FFF does not, so white-on-accent goes 7.88:1 light -> 2.71:1 dark:
#    fails 1.4.3, and fails 1.4.11 too for the 46px slider handle, which is a
#    control affordance needing 3:1. var(--pg) inverts with the accent and gives
#    6.97:1 light / 6.87:1 dark. Matches the trailing ';' so the two
#    `background: #FFFFFF` mockup fills are not touched.
a='color: #FFF;'; b='color: var(--pg, #F2F1EC);'
n+=s.count(a); s=s.replace(a,b)

# 3. Card "open case study" arrow icons at alpha .35 measured 2.23:1 light and
#    2.98:1 dark — both under the 3:1 that 1.4.11 requires of a meaningful icon.
#    .55 gives 3.97:1 / 5.60:1. Two substitutions because four mouseleave
#    handlers write the value back in JS; changing only the markup would restore
#    the failing colour the first time a pointer left a card.
#    Deliberately scoped to `color:` — about.html uses the same .35 value as a
#    decorative BACKGROUND, which has no contrast requirement and is left alone.
a='color: rgba(var(--inkrgb, 20,19,14),.35)'
b='color: rgba(var(--inkrgb, 20,19,14),.55)'
n+=s.count(a); s=s.replace(a,b)
a="arrow.style.color = 'rgba(var(--inkrgb, 20,19,14),.35)'"
b="arrow.style.color = 'rgba(var(--inkrgb, 20,19,14),.55)'"
n+=s.count(a); s=s.replace(a,b)

# 4. Asset references -> the optimised .jpg, but ONLY where that file actually
#    exists on disk. tools/optimize-assets.sh converts the 24 fully-opaque PNGs to
#    JPEG (the 3 that use real alpha stay PNG). Making the rewrite conditional means
#    a fresh export whose assets are still PNG keeps working — heavy, but never
#    broken — instead of pointing at files nobody generated yet.
import os
for stem in sorted(set(_re.findall(r'assets/([A-Za-z0-9._-]+)\.png', s))):
    if os.path.exists(os.path.join('assets', stem + '.jpg')):
        old_ref = 'assets/' + stem + '.png'
        n += s.count(old_ref)
        s = s.replace(old_ref, 'assets/' + stem + '.jpg')

# 5. Add "Claude" to the About page's tool chips. An owner content edit, kept here
#    for the same reason as the dropped section: a re-export regenerates the page
#    without it. The new chip CLONES the Jira chip's attributes byte-for-byte and
#    only changes the label, so it inherits the identical styling and the data-chip
#    hover binding rather than approximating them. Idempotent — skipped if present.
if p.endswith('about.html') and '>Claude</span>' not in s:
    _m = _re.search(r'<span[^>]*>Jira</span>', s)
    if _m:
        _jira = _m.group(0)
        s = s.replace(_jira, _jira + '\n              ' + _jira.replace('>Jira<', '>Claude<'), 1)
        n += 1

open(p,'w',encoding='utf-8').write(s)
print(f'    token fixes applied: {n}')
PY
}

# ---------------------------------------------------------------------------
# VENDOR THE RUNTIME — remove the third-party single point of failure.
#
# support.js loads React, ReactDOM and Babel from unpkg.com at runtime. If unpkg is
# slow, blocked by a corporate network, or blocked by an ad blocker, the visitor gets
# a blank cream page rather than degraded content — the whole site depended on TWO
# origins staying up. vendor/ holds the same three files, so it now depends on one.
#
# This does NOT change page weight: the browser downloads the same ~3.1MB either
# way. It changes the origin, removes a DNS+TLS handshake, and (since cross-site
# HTTP cache partitioning landed) gives up nothing in shared-cache benefit.
#
# The three files are byte-verified against the SRI hashes support.js already pins,
# so the `integrity` attribute keeps validating after the swap. If a future download
# does not match, the browser BLOCKS the script and the site goes blank — hence the
# verification step below rather than blind trust.
#
# Rewritten here rather than edited into support.js by hand, so the file stays
# pristine and a re-export can be re-patched in one command.
# ---------------------------------------------------------------------------
vendor_runtime() {
  [ -f support.js ] || return 0
  local miss=0
  for v in react.production.min.js react-dom.production.min.js babel.min.js; do
    [ -f "vendor/$v" ] || { echo "  vendor/$v missing — leaving support.js on unpkg"; miss=1; }
  done
  [ "$miss" = "1" ] && return 0
  python3 - <<'PYV'
import re
s=open('support.js',encoding='utf-8').read()
subs = {
  'https://unpkg.com/react@18.3.1/umd/react.production.min.js': 'vendor/react.production.min.js',
  'https://unpkg.com/react-dom@18.3.1/umd/react-dom.production.min.js': 'vendor/react-dom.production.min.js',
  'https://unpkg.com/@babel/standalone@7.29.0/babel.min.js': 'vendor/babel.min.js',
}
n=0
for a,b in subs.items():
    n += s.count(a); s = s.replace(a,b)
if n: open('support.js','w',encoding='utf-8').write(s)
print(f'    vendored runtime URLs rewritten: {n}')
PYV
}

vendor_runtime

applied=0; already=0; missing=0
for f in "${PAGES[@]}"; do
  if [ ! -f "$f" ]; then echo "  MISSING  $f"; missing=$((missing+1)); continue; fi
  if grep -q "$MARKER" "$f"; then echo "  ok       $f (already patched)"; already=$((already+1)); continue; fi
  if [ $CHECK_ONLY -eq 1 ]; then echo "  NEEDS    $f"; continue; fi
  python3 "$DROP" "$f"
  token_fixes "$f"
  python3 - "$f" "$CSS" "$JS" "$JS2" "$JS3" <<'PY'
import sys
page, cssfile, jsfile, js2file, js3file = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5]
html = open(page, encoding='utf-8').read()
css  = open(cssfile, encoding='utf-8').read()
js   = open(jsfile,  encoding='utf-8').read()
js2  = open(js2file, encoding='utf-8').read()
js3  = open(js3file, encoding='utf-8').read()

# 1. CSS -> immediately before the closing </style> of the FIRST <style> block
#    inside <helmet>. support.js preserves <style> there and hoists it to <head>.
h = html.find('<helmet>')
if h < 0: sys.exit(f'FAIL: no <helmet> in {page}')
s = html.find('<style>', h)
if s < 0: sys.exit(f'FAIL: no <style> inside <helmet> in {page}')
e = html.find('</style>', s)
if e < 0: sys.exit(f'FAIL: unterminated <style> in {page}')
html = html[:e] + '\n' + css + html[e:]

# 2. JS -> a plain <script> just before </body>, i.e. AFTER the page's own
#    text/x-dc template script. It polls for <nav> because the runtime renders
#    asynchronously, so load order is not load-bearing.
b = html.rfind('</body>')
if b < 0: sys.exit(f'FAIL: no </body> in {page}')
html = html[:b] + '<script data-mobile-menu>\n' + js + '</script>\n' \
            + '<script data-i18n-title>\n' + js2 + '</script>\n' \
            + '<script data-a11y-controls>\n' + js3 + '</script>\n' + html[b:]

open(page, 'w', encoding='utf-8').write(html)
PY
  echo "  patched  $f (css + js)"
  applied=$((applied+1))
done

echo
echo "ASSERTIONS"
fail=0
assert() { if [ "$2" = "$3" ]; then echo "  ok   $1: $2"; else echo "  FAIL $1: got $2 expected $3"; fail=1; fi; }

# both payloads must appear exactly once per page
for f in "${PAGES[@]}"; do
  [ -f "$f" ] || continue
  assert "css in $f" "$(grep -c "$MARKER" "$f" | tr -d ' ')" 1
  assert "js  in $f" "$(grep -c "$JS_MARKER" "$f" | tr -d ' ')" 1
  assert "i18n in $f" "$(grep -c "$JS2_MARKER" "$f" | tr -d ' ')" 1
  assert "a11y in $f" "$(grep -c "$JS3_MARKER" "$f" | tr -d ' ')" 1
done
# the CTA must stay in the sticky bar, never in the collapsed panel
assert "CTA excluded from panel" \
  "$(grep -c 'nav > a:not(\[href\^="mailto:"\])' "$CSS" | tr -d ' ')" 2
# the toggle must be hidden above the phone tier
assert "toggle hidden on desktop" \
  "$(grep -c '\[data-menu-toggle\] { display: none; }' "$CSS" | tr -d ' ')" 1
# a11y: the three measured contrast failures must stay fixed in the markup
for f in "${PAGES[@]}"; do
  [ -f "$f" ] || continue
  assert "no .5 pg-text in $f"  "$(grep -c 'color: rgba(var(--pgrgb, 242,241,236),.5)' "$f" | tr -d ' ')" 0
  assert "no bare #FFF in $f"   "$(grep -c 'color: #FFF;' "$f" | tr -d ' ')" 0
  assert "no .35 icon in $f"    "$(grep -c 'color: rgba(var(--inkrgb, 20,19,14),.35)' "$f" | tr -d ' ')" 0
done
assert "runtime is vendored, not unpkg" \
  "$(grep -c 'unpkg.com' support.js | tr -d ' ')" 0
assert "vendored files present" \
  "$(ls vendor/*.js 2>/dev/null | wc -l | tr -d ' ')" 3
# owner-removed content must stay removed after a re-export
assert "discipline section removed" \
  "$(grep -c 'data-disc' judged-sports-platform.html | tr -d ' ')" 0
# a11y: focus indicator and reduced-motion support must survive future edits
# matches the GLOBAL 2px ring by its own declaration, so adding another
# :focus-visible rule (e.g. the 3px one on the compare slider) cannot fail this
assert "focus-visible indicator present" \
  "$(grep -cF 'outline: 2px solid var(--acc, #1B3BD8) !important;' "$CSS" | tr -d ' ')" 1
assert "slider focus ring present" \
  "$(grep -cF '[data-compare]:focus-visible {' "$CSS" | tr -d ' ')" 1
assert "colour-independent selection cues" \
  "$(grep -cE '\[(data-tab-btn|data-chapter-link)\]\[aria-(pressed|current)' "$CSS" | tr -d ' ')" 2
assert "prefers-reduced-motion block present" \
  "$(grep -cF '@media (prefers-reduced-motion: reduce)' "$CSS" | tr -d ' ')" 1
# the mockup URL labels must stay theme-BLIND: a var()-based colour measured 1.15:1
assert "mockup label colour stays literal" \
  "$(grep -A2 -F '[style*="rgba(20, 19, 14, 0.07)"]' "$CSS" | grep -c 'var(--inkrgb' | tr -d ' ')" 0
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
