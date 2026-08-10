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
| `tools/i18n-title.js` | Keeps `<title>` and `<html lang>` in step with the language toggle. |
| `tools/a11y-controls.js` | Keyboard support + ARIA state for the slider and the four toggles. |
| `tools/drop-sections.py` | Re-applies owner-removed sections. Called by the script below. |
| `tools/png-min-alpha.py` | Reports a PNG's minimum alpha, so real transparency is preserved. |
| `tools/optimize-assets.sh` | Right-sizes and re-encodes `assets/`. Run BEFORE the next one. |
| `tools/apply-responsive-fixes.sh` | Injects all four, plus byte-level contrast and asset-path fixes. |

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

It is idempotent, asserts 52 invariants about its own result, and takes `--check` to verify
without writing. Nothing runs at deploy time — it is a one-shot script you run by hand, so
it does not make this a build pipeline.

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
5.75:1 light / 7.63:1 dark, accent link 6.96:1, all `clamp()` font minimums ≥16px, nothing
sets `outline: none`, and spacing is ~92% on a 4pt grid — coherent, left alone.

### Three traps, learned the hard way

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

## Known gaps

- **Nothing outstanding on assets or the runtime.** Both former gaps are closed: the
  runtime is vendored in `vendor/` (no third-party origin), and `assets/` is 4.7MB, down
  from 22MB.
- **The XGrab discipline cards are deliberately removed.** The Moguls / Aerials /
  Water-ramps section was cut at the owner's request; its three stills are deleted too.
  `tools/drop-sections.py` re-applies the removal after a re-export, since the design
  tool will regenerate the page complete with it. Three now-orphaned entries remain in
  that page's translation dictionary ("Moguls", "Aerials", "Water ramps") — inert, since
  they can no longer match any text node, and left alone rather than risk a syntax error
  editing the JS object literal.
- **`assets/` no longer contains any PNG.** All 25 files are JPEG. Three were previously
  held back as PNG on the belief they used transparency — they did not: their minimum
  alpha was 254, a 0.4% deviation invisible to the eye and an artefact of the export.
  Converting them saved a further 4.2MB. `tools/png-min-alpha.py` now performs that check
  by alpha VALUE, so a genuinely transparent asset in a future export is still protected.
- **The old capitalised `/Portfolio/` URL is permanently dead.** GitHub creates no Pages
  redirect for a renamed repo, and Pages has no rewrite config. Only a custom domain would
  let you reclaim it.
- **Spacing has a few near-miss pairs** (`56`/`60`px, `92`/`96`px) doing the same job.
  Cosmetic; consolidating them risks more than it fixes.
