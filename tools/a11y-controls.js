/* ===========================================================================
   Control accessibility — injected by tools/apply-responsive-fixes.sh.
   Paired with the SC 1.4.1 cues in tools/responsive-fixes.css.

   FIXES TWO LEVEL-A GAPS THE EXPORT SHIPS

   1. SC 2.1.1 Keyboard + 4.1.2 Name/Role/Value — the before/after comparison
      slider was a bare <div data-compare> with five pointer listeners and zero
      keydown, no tabindex, no role and no accessible name. A keyboard or switch
      user could not move it at all. (Tapping already worked, so SC 2.5.7 Dragging
      Movements was never the problem.)

   2. SC 1.4.1 Use of Color + 4.1.2 — all four toggle groups (language, theme,
      approach tabs, chapter rail) signalled the selected item by colour alone,
      with only 1.22:1 luminance separation between selected and unselected in
      light theme and 1.10:1 in dark. Nothing exposed state to assistive tech:
      a census found zero aria-pressed / aria-current / aria-selected on the site.

   HOW IT STAYS OUT OF THE WAY
      It never replaces the site's own handlers. State is MIRRORED from what the
      page already does — localStorage for language/theme, the inline styles that
      show()/upd() write for tabs and the chapter rail — and observed with
      MutationObserver. So a refactor of those handlers cannot desynchronise this,
      and this cannot fight them for control.

      For the slider it reuses the page's exact geometry: pct clamped to 12..88,
      `after.style.clipPath = inset(0 <100-pct>% 0 0)`, `handle.style.left = pct%`.
      Read out of bindCompare() rather than guessed, so keyboard and pointer end up
      in identical states.

   Gated on #dc-root — see trap #3 in the README.
   =========================================================================== */
(function () {
  'use strict';

  var MIN = 12, MAX = 88;                 // the clamp bounds bindCompare() uses

  function pctOf(handle) {
    var l = parseFloat(handle.style.left);
    return isNaN(l) ? 50 : l;
  }

  /* ---- 1. the comparison slider ---------------------------------------- */
  function enhanceCompare(root) {
    root.querySelectorAll('[data-compare]').forEach(function (box) {
      if (box.getAttribute('data-a11y')) return;
      var after  = box.querySelector('[data-compare-after]');
      var handle = box.querySelector('[data-compare-handle]');
      var hint   = (box.parentElement || box).querySelector('[data-compare-hint]');
      if (!after || !handle) return;
      box.setAttribute('data-a11y', '1');

      box.setAttribute('tabindex', '0');
      box.setAttribute('role', 'slider');
      box.setAttribute('aria-orientation', 'horizontal');
      box.setAttribute('aria-valuemin', String(MIN));
      box.setAttribute('aria-valuemax', String(MAX));
      /* The name carries the key instruction rather than editing the visible
         "Drag the handle" hint, which is translated copy — changing its text would
         break the i18n dictionary lookup, which matches on exact strings. */
      if (!box.getAttribute('aria-label')) {
        box.setAttribute('aria-label', 'Before and after comparison. Use the arrow keys to reveal the redesigned version.');
      }
      handle.setAttribute('aria-hidden', 'true');   // the decorative arrows glyph

      function publish(pct) {
        box.setAttribute('aria-valuenow', String(Math.round(pct)));
        box.setAttribute('aria-valuetext', Math.round(pct) + '% of the redesigned version shown');
      }
      function apply(pct) {
        pct = Math.min(MAX, Math.max(MIN, pct));
        after.style.clipPath = 'inset(0 ' + (100 - pct).toFixed(2) + '% 0 0)';
        handle.style.left = pct.toFixed(2) + '%';
        if (hint) hint.style.opacity = '0';
        publish(pct);
      }

      publish(pctOf(handle));   // announce a value before any interaction

      box.addEventListener('keydown', function (e) {
        var p = pctOf(handle), used = true;
        switch (e.key) {
          case 'ArrowLeft':  case 'ArrowDown': p -= 4;  break;
          case 'ArrowRight': case 'ArrowUp':   p += 4;  break;
          case 'PageDown':                     p -= 12; break;
          case 'PageUp':                       p += 12; break;
          case 'Home':                         p = MIN; break;
          case 'End':                          p = MAX; break;
          default: used = false;
        }
        if (!used) return;
        e.preventDefault();          // stop the page scrolling instead
        apply(p);
      });

      // Pointer drags go through the page's own set(); mirror the result.
      if (typeof MutationObserver === 'function') {
        new MutationObserver(function () {
          var p = Math.round(pctOf(handle));
          if (String(p) !== box.getAttribute('aria-valuenow')) publish(p);
        }).observe(handle, { attributes: true, attributeFilter: ['style'] });
      }
    });
  }

  /* ---- 2. language + theme: state from the same place the page reads it -- */
  function readStored(key, fallback) {
    try { return localStorage.getItem(key) || fallback; } catch (e) { return fallback; }
  }
  function syncPrefs(root) {
    var label = root.querySelector('[data-prefs-lang]');
    var lang = label && /^(en|es)$/i.test((label.textContent || '').trim())
      ? (label.textContent || '').trim().toLowerCase()
      : readStored('dp-portfolio-lang', 'en');
    root.querySelectorAll('[data-lang-btn]').forEach(function (b) {
      b.setAttribute('aria-pressed', b.getAttribute('data-lang-btn') === lang ? 'true' : 'false');
    });
    var theme = readStored('dp-portfolio-theme', 'light');
    root.querySelectorAll('[data-theme-btn]').forEach(function (b) {
      b.setAttribute('aria-pressed', b.getAttribute('data-theme-btn') === theme ? 'true' : 'false');
    });
  }

  /* ---- 3. approach tabs -------------------------------------------------
     Uses aria-pressed, NOT role="tab"/aria-selected, on purpose: declaring a
     tablist takes on the full WAI-ARIA keyboard contract (arrow-key roving
     focus, Home/End). These are plain buttons that each show a panel, and a
     half-implemented tab widget is worse for a screen-reader user than a clearly
     labelled toggle button. show() marks the active one with an --accrgb tinted
     background, so that is the signal we mirror. */
  function syncTabs(root) {
    root.querySelectorAll('[data-tab-btn]').forEach(function (b) {
      var on = /accrgb/.test(b.style.background || '');
      b.setAttribute('aria-pressed', on ? 'true' : 'false');
    });
  }

  /* ---- 4. chapter rail: aria-current from the colour upd() writes -------- */
  function syncChapters(root) {
    root.querySelectorAll('[data-chapter-link]').forEach(function (a) {
      if (/--acc/.test(a.style.color || '')) a.setAttribute('aria-current', 'true');
      else a.removeAttribute('aria-current');
    });
  }

  function init() {
    var root = document.getElementById('dc-root');
    if (!root) return false;

    enhanceCompare(root);
    syncPrefs(root);
    syncTabs(root);
    syncChapters(root);

    if (typeof MutationObserver === 'function') {
      /* One observer for the inline-style writes that drive tabs and the rail.
         attributeFilter keeps it cheap: only style changes, and the handlers only
         ever write style. */
      new MutationObserver(function () {
        syncTabs(root); syncChapters(root); syncPrefs(root);
      }).observe(root, { attributes: true, attributeFilter: ['style'], subtree: true });
    }
    /* Clicks in the prefs popover change localStorage, which no observer sees. */
    root.addEventListener('click', function (e) {
      if (e.target && e.target.closest && e.target.closest('[data-lang-btn],[data-theme-btn]')) {
        setTimeout(function () { syncPrefs(root); }, 0);
      }
    });

    /* The runtime re-binds its own handlers on an interval for ~12s, and the
       reveal observer keeps mounting content, so re-run briefly to catch controls
       that appear after first paint. */
    var n = 0, iv = setInterval(function () {
      enhanceCompare(root); syncTabs(root); syncChapters(root);
      if (++n > 20) clearInterval(iv);
    }, 600);
    return true;
  }

  var tries = 0;
  (function wait() {
    try { if (init()) return; } catch (err) { return; }   // never break the page
    if (++tries > 60) return;
    setTimeout(wait, 100);
  })();
})();
