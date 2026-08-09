# Portfolio

Daniel Pazmiño's portfolio site — live at **[daamndaniel.github.io/portfolio](https://daamndaniel.github.io/portfolio/)**.

## What this is

A static site, no build step and no framework. Plain HTML files plus one runtime script
(`support.js`) that compiles the inline JSX templates in-browser (via Babel + React, loaded
from unpkg at runtime), images in `assets/`, and the CV in `uploads/`.

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
| `tools/apply-responsive-fixes.sh` | Injects all three, plus byte-level contrast fixes. |

**Re-exporting from the design tool regenerates the five HTML files and deletes every one
of these changes.** Put them back with:

```bash
bash tools/apply-responsive-fixes.sh
```

It is idempotent, asserts 42 invariants about its own result, and takes `--check` to verify
without writing. Nothing runs at deploy time — it is a one-shot script you run by hand, so
it does not make this a build pipeline.

### What the accessibility work covers

A measured audit (contrast ratios computed from composited colours in **both** themes, not
eyeballed) fixed five contrast failures — the worst was a card arrow icon at exactly 1.00:1,
i.e. invisible — raised the focus ring to 2px for WCAG 2.2 SC 2.4.11, wired
`prefers-reduced-motion` to the `calm` path the page script already had, and fixed
SC 3.1.1 by making `<html lang>` follow the language toggle.

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
- `support.js` pulls React from unpkg at runtime, so the site needs internet access on
  first load — that's expected, not a bug.
- Filenames in `assets/` and the `.dc.html` legacy stubs matter — don't rename or move them.
- The language/theme toggles are `1fr 1fr` grids with `gap: 2px`. Ten of the eleven
  `1fr 1fr` grids in the site are those toggles, so never write a blanket "collapse all
  two-column grids" rule — it breaks every one of them.

## Known gaps

- **Runtime CDN dependency.** `support.js` fetches React, ReactDOM and Babel from unpkg on
  every load. If unpkg is slow, blocked by a corporate network, or blocked by an ad
  blocker, the visitor gets a blank cream page rather than degraded content. Vendoring the
  three scripts locally would remove the single point of failure without adding a build step.
- **Asset weight.** `assets/` is ~22MB; `sb-cover.png` alone is 4.5MB, `xg-cover.png` 2.9MB.
  Lossless compression would cut first-load time substantially and is not a build pipeline.
- **The old capitalised `/Portfolio/` URL is permanently dead.** GitHub creates no Pages
  redirect for a renamed repo, and Pages has no rewrite config. Only a custom domain would
  let you reclaim it.
- **Spacing has a few near-miss pairs** (`56`/`60`px, `92`/`96`px) doing the same job.
  Cosmetic; consolidating them risks more than it fixes.
