#!/usr/bin/env python3
"""
Remove sections the owner deleted, so a design-tool re-export cannot bring them back.

    python3 tools/drop-sections.py <page.html>

WHY THIS EXISTS
    Re-exporting regenerates the pages complete with everything, so deleting a
    section once is not enough. tools/apply-responsive-fixes.sh calls this for each
    page; it is a no-op for pages with nothing to drop, and idempotent.

WHY A SEPARATE FILE
    It used to live inline in the shell script as a heredoc. Nesting a Python
    heredoc inside a function that the script also uses for other heredocs broke
    bash parsing. A real file is simpler and testable on its own.

SAFETY
    Every removal asserts the shape of what it is about to cut and exits non-zero
    rather than guessing. Better to fail loudly than to silently delete the wrong
    3KB of someone's portfolio.
"""
import re
import sys


def drop_discipline_cards(html):
    """The Moguls / Aerials / Water-ramps cards on the XGrab case study.

    Removed at the owner's request — the section did not earn its space. Its three
    stills were also the only assets left on the site below 2x retina density
    (560px source for a 416px box), which re-encoding could never fix; they arrived
    that size in the handoff.

    Matched structurally: the [data-reveal] wrapper enclosing the three [data-disc]
    cards. Anchoring on structure rather than byte offsets means unrelated edits
    above it do not shift the target.
    """
    first = html.find('data-disc')
    if first == -1:
        return html, 0                      # already gone

    wrap = html.rfind('<div data-reveal', 0, first)
    if wrap == -1:
        sys.exit('FAIL: found data-disc with no enclosing <div data-reveal> wrapper')

    depth = 0
    end = None
    for m in re.finditer(r'<(/?)div\b[^>]*>', html[wrap:]):
        depth += 1 if m.group(1) == '' else -1
        if depth == 0:
            end = wrap + m.end()
            break
    if end is None:
        sys.exit('FAIL: unbalanced <div> nesting around the discipline section')

    seg = html[wrap:end]

    # Refuse to cut anything that is not exactly what we expect.
    n_cards = len(re.findall('data-disc', seg))
    if n_cards != 3:
        sys.exit(f'FAIL: expected 3 data-disc cards in the wrapper, found {n_cards}')
    if 'id="' in seg:
        sys.exit('FAIL: wrapper contains an id — a chapter link may target it')
    stray = set(re.findall(r'assets/([A-Za-z0-9._-]+)', seg)) - {
        'xg-moguls.jpg', 'xg-aerials.jpg', 'xg-water-ramps.jpg',
        'xg-moguls.png', 'xg-aerials.png', 'xg-water-ramps.png'}
    if stray:
        sys.exit(f'FAIL: wrapper references unexpected assets: {sorted(stray)}')

    return html[:wrap] + html[end:], len(seg)


# page filename -> the removals that apply to it
DROPS = {
    'judged-sports-platform.html': [('discipline cards', drop_discipline_cards)],
}


def main():
    if len(sys.argv) != 2:
        sys.exit('usage: drop-sections.py <page.html>')
    path = sys.argv[1]
    name = path.split('/')[-1]
    jobs = DROPS.get(name, [])
    if not jobs:
        return

    html = open(path, encoding='utf-8').read()
    removed = []
    for label, fn in jobs:
        html, n = fn(html)
        if n:
            removed.append(f'{label} ({n} bytes)')

    if removed:
        open(path, 'w', encoding='utf-8').write(html)
        print('    dropped: ' + ', '.join(removed))
    else:
        print('    dropped: nothing (already absent)')


if __name__ == '__main__':
    main()
