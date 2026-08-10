/* ===========================================================================
   Language sync for <title>, <html lang> and image alt text — injected by
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

   ALT TEXT, AND WHY IT IS THE SAME BUG
     applyLang() walks TEXT NODES. An alt="" is an ATTRIBUTE, so it is as
     unreachable to that walker as <title> was: all 28 images kept English alt
     text under <html lang="es">. For a sighted visitor that is invisible, but a
     screen reader announcing English strings with Spanish pronunciation rules is
     the same SC 3.1.1 problem the lang fix addressed, just in the one place the
     lang fix could not reach.

     Every image already had a specific, useful alt from the export — no
     "image1.jpg", nothing empty, nothing missing, and all 57 decorative SVGs
     already carry aria-hidden. So this adds a translation layer and changes no
     English wording. "Daniel Pazmiño" is deliberately absent from the map: a
     proper name is the same in both languages.
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

  // Keyed by the export's own English alt text. 21 unique strings across the five
  // pages; the site's established vocabulary is reused where it exists
  // ("deportes de puntuación", "Optimización de conversión").
  var ES_ALT = {
    'Redesigned contact sales landing page':
      'Página de contacto de ventas rediseñada',
    'Redesigned Stack Builders homepage':
      'Página de inicio de Stack Builders rediseñada',
    'XGrab judged sports platform landing page':
      'Página de inicio de XGrab, plataforma de deportes de puntuación',
    'Redesigned sales form grouped into three short steps':
      'Formulario de ventas rediseñado, agrupado en tres pasos breves',
    'What happens after submitting, next to the primary call to action':
      'Lo que ocurre después de enviar, junto a la llamada a la acción principal',
    'Help placed inside the flow as reassurance':
      'Ayuda ubicada dentro del flujo, como tranquilidad',
    'Original contact sales page, before redesign':
      'Página de contacto de ventas original, antes del rediseño',
    'Redesigned sign-up flow':
      'Flujo de registro rediseñado',
    'Stack Builders website redesign':
      'Rediseño del sitio web de Stack Builders',
    'XGrab judged sports platform':
      'XGrab, plataforma de deportes de puntuación',
    'Reworked navigation and a three-step path through the site':
      'Navegación reelaborada y un recorrido de tres pasos por el sitio',
    'Hero and content hierarchy leading with the value':
      'Portada y jerarquía de contenido que empiezan por el valor',
    'Results, testimonial, and certifications making credibility felt':
      'Resultados, testimonio y certificaciones que hacen tangible la credibilidad',
    'Stack Builders homepage as it is live today':
      'Página de inicio de Stack Builders como está publicada hoy',
    'Redesigned homepage, in build':
      'Página de inicio rediseñada, en construcción',
    'Contact sales landing page CRO':
      'Optimización de conversión de la página de contacto de ventas',
    'XGrab brand and product direction':
      'Dirección de marca y producto de XGrab',
    'Brand wireframe: wordmark lock-ups, type scale, and a motion study':
      'Wireframe de marca: composiciones del logotipo, escala tipográfica y un estudio de movimiento',
    'Design-system wireframe: tokens feeding components':
      'Wireframe del sistema de diseño: tokens que alimentan los componentes',
    'Exploration wireframe: four directions, one taken forward':
      'Wireframe de exploración: cuatro direcciones, una elegida',
    'Component spec wireframe: every state drawn once':
      'Wireframe de especificación de componentes: cada estado dibujado una vez'
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

  /* Swap alt text for the current language.

     The English original is stashed in data-alt-en on first sight, so switching
     back is a lookup rather than a reverse-translation, and an image whose alt
     has no entry in the map is simply left alone.

     Writes are conditional on the value actually differing. That is what makes it
     safe to call from a MutationObserver that watches `alt` itself: re-entry
     finds nothing to change and stops, instead of looping. React re-rendering
     from the JSX (a theme flip, a tab change) restores the English attribute,
     and that observer is what puts the Spanish back. */
  function syncAlt(es) {
    var imgs = document.querySelectorAll('#dc-root img');
    for (var i = 0; i < imgs.length; i++) {
      var img = imgs[i];
      var en = img.getAttribute('data-alt-en');
      if (en === null) {
        en = img.getAttribute('alt');
        if (en === null) continue;              // nothing to preserve
        img.setAttribute('data-alt-en', en);
      }
      var want = es ? (ES_ALT[en] || en) : en;
      if (img.getAttribute('alt') !== want) img.setAttribute('alt', want);
    }
  }

  function sync() {
    var es = currentLang() === 'es';
    var next = es ? (ES[EN_TITLE] || EN_TITLE) : EN_TITLE;
    if (document.title !== next) document.title = next;
    var lang = es ? 'es' : 'en';
    if (document.documentElement.lang !== lang) document.documentElement.lang = lang;
    syncAlt(es);
  }

  function init() {
    var root = document.getElementById('dc-root');
    if (!root) return false;
    sync();
    var label = root.querySelector('[data-prefs-lang]');
    if (label && typeof MutationObserver === 'function') {
      new MutationObserver(sync).observe(label, { childList: true, characterData: true, subtree: true });
      // Catch images React re-renders (or mounts late) with the English alt back.
      new MutationObserver(function () { syncAlt(currentLang() === 'es'); })
        .observe(root, { childList: true, subtree: true, attributeFilter: ['alt'] });
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
