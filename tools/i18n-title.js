/* ===========================================================================
   Language sync for <title> and <html lang> — injected by
   tools/apply-responsive-fixes.sh.

   THE PROBLEM
     The page's own applyLang() translates body copy with
     `document.createTreeWalker(root, NodeFilter.SHOW_TEXT)` where `root` is the
     in-body [data-theme-root]. <title> lives in <head>, so it is structurally
     unreachable — the tab kept saying "About — Daniel Pazmiño" while the whole
     page read Spanish.

     Worse, and the reason this is more than cosmetic: <html lang> stayed "en"
     with Spanish content in it. That is WCAG 2.2 SC 3.1.1 Language of Page at
     LEVEL A — a screen reader keeps using English pronunciation rules for
     Spanish text, which makes it close to unintelligible. Fixing the title
     without fixing lang would have missed the actual accessibility problem.

   HOW IT KNOWS THE LANGUAGE
     The page persists it as localStorage['dp-portfolio-lang'] ('en' | 'es',
     default 'en') and reflects it in a [data-prefs-lang] label. Reading storage
     covers first paint; a MutationObserver on that label covers every later
     change without needing to hook the site's own click handlers, so this stays
     working even if those handlers are refactored.

   WHY IT WAITS FOR #dc-root
     Same reason as tools/mobile-menu.js: support.js renders the real tree from an
     <x-dc> template, and anything queried before that is the template copy.
     Scope to #dc-root, never to document.

   The Spanish strings are the SITE'S OWN wording, lifted from each page's
   translation dictionary ("Optimización de conversión", "Estrategia y rediseño
   web", "deportes de puntuación", "Sobre mí") rather than invented — except
   "Diseñador de Producto", which had no dictionary entry.
   =========================================================================== */
(function () {
  'use strict';

  var ES = {
    'Daniel Pazmiño — Product Designer':        'Daniel Pazmiño — Diseñador de Producto',
    'About — Daniel Pazmiño':                   'Sobre mí — Daniel Pazmiño',
    'Sales Landing CRO — Daniel Pazmiño':       'Optimización de conversión — Daniel Pazmiño',
    'Stack Builders Website — Daniel Pazmiño':  'Estrategia y rediseño web — Daniel Pazmiño',
    'Judged Sports Platform — Daniel Pazmiño':  'Deportes de puntuación — Daniel Pazmiño'
  };

  var EN_TITLE = document.title;   // captured before anything rewrites it

  function currentLang() {
    var el = document.querySelector('#dc-root [data-prefs-lang]');
    if (el) {
      var t = (el.textContent || '').trim().toLowerCase();
      if (t === 'es' || t === 'en') return t;
    }
    try { return localStorage.getItem('dp-portfolio-lang') === 'es' ? 'es' : 'en'; }
    catch (e) { return 'en'; }        // storage can throw in private mode
  }

  function sync() {
    var es = currentLang() === 'es';
    var next = es ? (ES[EN_TITLE] || EN_TITLE) : EN_TITLE;
    if (document.title !== next) document.title = next;
    var lang = es ? 'es' : 'en';
    if (document.documentElement.lang !== lang) document.documentElement.lang = lang;
  }

  function init() {
    var root = document.getElementById('dc-root');
    if (!root) return false;
    sync();
    var label = root.querySelector('[data-prefs-lang]');
    if (label && typeof MutationObserver === 'function') {
      new MutationObserver(sync).observe(label, { childList: true, characterData: true, subtree: true });
    } else {
      // No label to watch: fall back to catching the toggle itself.
      root.addEventListener('click', function (e) {
        if (e.target && e.target.closest && e.target.closest('[data-lang-btn]')) setTimeout(sync, 0);
      });
    }
    return true;
  }

  var tries = 0;
  (function wait() {
    try { if (init()) return; } catch (err) { return; }   // never break the page
    if (++tries > 60) return;                              // ~6s then give up
    setTimeout(wait, 100);
  })();
})();
