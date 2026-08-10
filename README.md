# Portfolio

Daniel Pazmiño's portfolio site — live at **[daamndaniel.github.io/portfolio](https://daamndaniel.github.io/portfolio/)**.

## What this is

A static site, no build step and no framework. Plain HTML files plus one runtime script
(`support.js`) that compiles the inline JSX templates in-browser (via Babel + React, loaded
from `vendor/`, not a CDN), images in `assets/`, and the CV in `uploads/`.

Published from the `main` branch, root, via GitHub Pages.

## Pages

| URL | File |
|---|---|
| `/` | `index.html` |
| `/about` | `about.html` |
| `/sales-landing-cro` | `sales-landing-cro.html` |
| `/stack-builders-website` | `stack-builders-website.html` |
| `/judged-sports-platform` | `judged-sports-platform.html` |

GitHub Pages serves each page extensionless via its implicit single-`.html` append —
there are no subdirectories, so every page and `support.js`/`assets/` reference stays at
the same depth. `404.html` rescues trailing-slash URLs and the old `*.dc.html` paths
(kept as redirect stubs) so existing links keep working.

## Hand-written fixes — read this before re-exporting

The design-tool export ships **zero `@media` queries** (fluid `clamp()` typography was the
only responsive mechanism, so every fixed-column grid stayed fixed on a phone), and it has
a handful of accessibility gaps. All of that is fixed by hand, and all of it lives in
`tools/`:

| File | Role |
|---|---|
| `tools/responsive-fixes.css` | Responsive **and** accessibility CSS. **Single source of truth.** |
| `tools/mobile-menu.js` | Sticky header + hamburger nav (mobile only). |
| `tools/i18n-title.js` | Keeps `<title>`, `<html lang>` and image `alt` text in step with the language toggle. |
| `tools/a11y-controls.js` | Keyboard support + ARIA state for the slider and the four toggles. |
| `tools/seo-tags.py` | Per-page `<head>` metadata, plus `sitemap.xml` and `robots.txt`. |
| `tools/drop-sections.py` | Re-applies owner-removed sections. Called by the script below. |
| `tools/png-min-alpha.py` | Reports a PNG's minimum alpha, so real transparency is preserved. |
| `tools/optimize-assets.sh` | Right-sizes and re-encodes `assets/`. Run BEFORE the next one. |
| `tools/apply-responsive-fixes.sh` | Injects all of the above, plus byte-level contrast and asset-path fixes. |

**Re-exporting from the design tool regenerates the five HTML files and deletes every one
of these changes.** Put them back with:

```bash
bash tools/optimize-assets.sh        # assets: 22MB -> 4.7MB
bash tools/apply-responsive-fixes.sh   # CSS/JS + point the HTML at the .jpg files
```

The asset-path rewrite is conditional on the `.jpg` existing, so running only the
second script after a re-export leaves references on `.png` — heavy, but not broken.

The apply script also carries two **content** edits, because a re-export regenerates the
pages without them: the XGrab discipline section stays removed, and "Claude" stays in the
About page's tool chips. Both are idempotent.

It is idempotent, asserts 98 invariants about its own result, and takes `--check` to verify
without writing. Nothing runs at deploy time — it is a one-shot script you run by hand, so
it does not make this a build pipeline.

**It re-injects on every run rather than skipping pages it has already patched.** That
matters: it used to `continue` as soon as it found its own marker, so editing
`tools/responsive-fixes.css` or any `tools/*.js` had no effect on a page patched earlier —
the "single source of truth" above was only true of a freshly exported file. The bug
surfaced when an alt-text translation was added, the script reported success, and the
browser went on serving the previous copy of the script from inside the HTML. Each payload
is delimited (the CSS by its banner through the following `</style>`, each script by its
`data-*` attribute), so the script now strips its own prior output before writing.

### What the accessibility work covers

A measured audit (contrast ratios computed from composited colours in **both** themes, not
eyeballed) fixed five contrast failures — the worst was a card arrow icon at exactly 1.00:1,
i.e. invisible — raised the focus ring to 2px for WCAG 2.2 SC 2.4.11, wired
`prefers-reduced-motion` to the `calm` path the page script already had, and fixed
SC 3.1.1 by making `<html lang>` follow the language toggle.

A second round fixed the hover state (`a:hover { opacity: .72 }` multiplied into
link alpha, dropping ~37 anchors to 3.16:1), made the before/after slider keyboard
operable with `role="slider"` and arrow keys (SC 2.1.1 / 4.1.2), and gave all four
toggle groups real ARIA state plus a cue that is not colour — they previously
signalled selection by hue alone at 1.22:1 separation (SC 1.4.1).

Passing already, recorded so nobody "fixes" them later: ink text 16.44:1, `rgba(ink,.66)`
5.75:1 light / 7.63:1 dark, accent link 6.96:1, all `clamp()` font minimums ≥16px, and
nothing sets `outline: none`.

Spacing is ~92% on a 4pt grid and needs no work. An earlier note here claimed `56`/`60`px
and `92`/`96`px were near-miss duplicates; they are not. `92px` is only ever a `margin-top`
and `96px` only ever a `padding`, so they never do the same job, and `clamp(28px, 5vw, 56px)`
vs `clamp(32px, 5vw, 60px)` differ at *both* ends — two deliberate steps in the ramp, not
one value with a typo.

### What the SEO work covers

The export shipped no metadata at all: no `<meta name="description">`, no Open Graph, no
Twitter card, no structured data, no sitemap, on any of the five pages. Pasted into
LinkedIn or Slack the site unfurled as a bare URL. `tools/seo-tags.py` now emits, per page,
a description written from that page's own copy, Open Graph and Twitter tags, and
schema.org JSON-LD (`Person` + `WebSite`/`ProfilePage` on the two profile pages,
`CreativeWork` on the three case studies), plus a site-level `sitemap.xml`.

It also owns `<title>` and `rel="canonical"`. Those already existed, but only because an
earlier one-off migration added them by hand — nothing re-applied them, so the next
re-export would have silently dropped both.

Two things worth knowing:

- **Crawlability was never the problem, and that was measured rather than assumed.** The raw
  HTML ahead of the `text/x-dc` template already carries the `<h1>` and ~25k characters of
  prose, so search engines index real content without executing any JavaScript. Only the
  metadata was missing. Link unfurlers, by contrast, run no JavaScript whatsoever — which is
  why these tags go in the real `<head>` on disk and not in the in-body `<helmet>`.
- **`robots.txt` is shipped but inert here.** Crawlers fetch robots.txt only from the origin
  root, `daamndaniel.github.io/robots.txt`. This is a project site under `/portfolio/`, so
  the file lands at a path nothing will read, and the origin root belongs to a different
  repo. It costs nothing, states intent, and starts working the moment a custom domain is
  attached — but until then the sitemap has to be submitted to Search Console by hand
  ([#3](https://github.com/daamndaniel/portfolio/issues/3)).

No `hreflang`: the toggle swaps copy in place, so English and Spanish share one URL and an
`hreflang` annotation — which describes alternate *URLs* — would be a lie. The pages declare
`og:locale` with `og:locale:alternate` instead.

`assets/og-share.jpg` is the 1200×630 share card. It could not be derived from
`assets/daniel-portrait.jpg`, which is 600×900 — under the 1200px minimum for a large card
and the wrong shape — so it is cut from the 2688×4033 original in the handoff. The crop
offset is written down in `tools/optimize-assets.sh` because it was read off the image, not
calculated: the first attempt sliced his chin off.

### What the alt-text work covers

**The export's alt text was already good** — all 28 images carried specific, useful
descriptions ("Redesigned sales form grouped into three short steps"), none were empty or
missing, and all 57 decorative SVGs already had `aria-hidden`. No English wording was
changed.

The one real gap was bilingual. The page's own `applyLang()` translates by walking **text
nodes**, and `alt` is an attribute — so it was as unreachable to that walker as `<title>`
had been, and all 28 images kept English alt text under `<html lang="es">`. Invisible to a
sighted visitor; for a screen reader it means English strings read with Spanish
pronunciation rules, the same SC 3.1.1 problem the `lang` fix addressed, in the one place
that fix could not reach. `tools/i18n-title.js` now carries 21 translations and swaps them
with the toggle, stashing each English original in `data-alt-en` so switching back is a
lookup rather than a reverse-translation.

### Four traps, learned the hard way

1. **Selectors must be checked against the rendered DOM, not the source bytes.** The runtime
   re-serialises inline styles through the CSSOM, so `minmax(0,200px)` in the file becomes
   `minmax(0px, 200px)` live. A selector written from the file matches nothing and fails
   *silently*.
2. **No `!important` rule may set `transform` or `opacity`.** The scroll-reveal observer
   writes those inline; a stylesheet `!important` beats it and leaves pages blank.
3. **Scope every JS query to `#dc-root`.** `<nav>` exists twice — once in the `<x-dc>`
   template that is in the DOM at parse time, once in the tree `support.js` renders from it.
   Querying `document` finds the template copy, which is then serialised and re-created by
   React *without event listeners* — you get a control that renders and does nothing.
4. **Judge PNG transparency by alpha VALUE, never by pixel count.** `sips -g hasAlpha`
   reports "yes" for a merely present channel and said yes to all 27 PNGs here, none of
   which needed it. Counting non-opaque pixels is also wrong: three files reported hundreds
   of thousands, so they were kept as PNG and 4.2MB was wasted — every one of those pixels
   had alpha 254, a 0.4% deviation. `tools/png-min-alpha.py` asks the right question.

## Constraints — don't "fix" these

- **Keep the pages and `assets/` flat at the repo root.** All paths are relative; moving
  them into subdirectories breaks `support.js` and image loading. (`tools/` is not served
  content and `uploads/` is only linked assets, so those are fine.)
- **Never create a root-level directory named after a page slug** (`about`, `index`,
  `sales-landing-cro`, …). On GitHub Pages a directory outranks the implicit `.html`
  append, which silently turns that clean URL into a 301 to a 404.
- **No bundler, framework, or build pipeline.** These files run directly in the browser.
- **Do not point `support.js` back at a CDN.** It loads React, ReactDOM and Babel from
  `vendor/`, and the SRI hashes it pins are byte-verified against those files. If you
  replace them, the `integrity` check will BLOCK the script and the site will go blank.
- Filenames in `assets/` and the `.dc.html` legacy stubs matter — don't rename or move them.
- The language/theme toggles are `1fr 1fr` grids with `gap: 2px`. Ten of the eleven
  `1fr 1fr` grids in the site are those toggles, so never write a blanket "collapse all
  two-column grids" rule — it breaks every one of them.

## Open items

Nothing is tracked in this file. Anything still outstanding lives in
[Issues](https://github.com/daamndaniel/portfolio/issues) so it can be closed properly:

- [#1](https://github.com/daamndaniel/portfolio/issues/1) — the old capitalised
  `/Portfolio/` URL is dead and only a custom domain can reclaim it.
- [#2](https://github.com/daamndaniel/portfolio/issues/2) — three orphaned translation
  keys left over from the removed discipline section. Inert; cosmetic.
- [#3](https://github.com/daamndaniel/portfolio/issues/3) — submit `sitemap.xml` to Google
  Search Console. Needs the owner's Google account, and `robots.txt` cannot do it from a
  project-site path.

### Decisions worth knowing

- **The XGrab discipline card section is deliberately removed.** Cut at the owner's
  request, its three stills deleted with it. `tools/drop-sections.py` re-applies the
  removal after a re-export, because the design tool regenerates the page complete
  with it.
- **`assets/og-share.jpg` is not resized by `optimize-assets.sh`.** It is already at its
  exact required 1200×630, and resampling it would defeat the point. Anything named `og-*`
  is skipped explicitly rather than relying on it matching no width rule.
- **`assets/` contains no PNG.** All 25 files are JPEG, 4.7MB total, down from 22MB —
  and every conversion was checked by pixel-diffing against the original rather than
  by eye. See trap #4 for why three of them nearly got left behind.
- **The runtime is vendored, not fetched from a CDN.** See the constraint above before
  changing it.
