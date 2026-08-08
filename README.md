# Portfolio

Daniel Pazmiño's portfolio site — live at **[daamndaniel.github.io/portfolio](https://daamndaniel.github.io/portfolio/)**.

## What this is

A static site, no build step and no framework. Plain HTML files plus one runtime script
(`support.js`) that compiles the inline JSX templates in-browser (via Babel + React, loaded
from unpkg at runtime) and images in `assets/`.

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

## Responsive fixes — read this before re-exporting

The design-tool export ships **zero `@media` queries**: fluid `clamp()` typography was the
only responsive mechanism, so every fixed-column grid stayed fixed on a phone. The media
queries that make the site work on mobile are hand-written and live in:

| File | Role |
|---|---|
| `tools/responsive-fixes.css` | The CSS. **Single source of truth — edit here.** |
| `tools/apply-responsive-fixes.sh` | Copies it into each page's `<helmet>` `<style>`. |

**Re-exporting from the design tool regenerates the five HTML files and deletes this CSS.**
Put it back with:

```bash
bash tools/apply-responsive-fixes.sh
```

The script is idempotent, asserts its own results, and takes `--check` to verify without
writing. Nothing runs at deploy time — it's a one-shot script you run by hand, so it does
not make this a build pipeline.

Two traps are documented at the top of the CSS file and worth knowing before you touch it:
selectors must be checked against the **rendered DOM** (the runtime re-serialises inline
styles, so `minmax(0,200px)` in the file becomes `minmax(0px, 200px)` live, and a selector
written from the source silently matches nothing); and no `!important` rule may set
`transform` or `opacity`, because the scroll-reveal observer writes those inline and a
stylesheet `!important` would beat it and leave pages blank.

## Constraints — don't "fix" these

- **Keep everything flat at the repo root**, with `assets/` beside it. All paths are
  relative; moving files into subdirectories breaks `support.js` and image loading.
- **No bundler, framework, or build pipeline.** These files run directly in the browser.
- `support.js` pulls React from unpkg at runtime, so the site needs internet access on
  first load — that's expected, not a bug.
- Filenames in `assets/` and the `.dc.html` legacy files matter — don't rename or move them.
- The language/theme toggles are `1fr 1fr` grids with `gap: 2px`. Ten of the eleven
  `1fr 1fr` grids in the site are those toggles, so never write a blanket "collapse all
  two-column grids" rule — it breaks every one of them.

## Known gaps

- The CV download link in `about.html` (`uploads/CV DAPC 2025.pdf`) has no matching file
  in the repo. Drop the PDF at `uploads/CV DAPC 2025.pdf` to fix it.
- The language toggle translates page body text but not the `<title>` tag.
