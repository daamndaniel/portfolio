/* ===========================================================================
   Mobile menu toggle — appended to the design-tool export by
   tools/apply-responsive-fixes.sh. Paired with the sticky-bar CSS in
   tools/responsive-fixes.css; neither works without the other.

   WHAT IT DOES
     Appends one <button data-menu-toggle> to the header and toggles
     data-menu="open" on that header. All layout is CSS (see the STICKY BAR +
     HAMBURGER section of the CSS); this file only owns state and a11y.

   WHY IT APPENDS AND NEVER REPARENTS
     The header is React-rendered by support.js. Moving existing nodes risks them
     being reconciled back on the next render. Appending a new node is safe —
     verified the appended button survives both a prefs-dropdown open and a
     language switch. So the panel is built with CSS `order`, not DOM moves.

   WHY IT WAITS FOR #dc-root — DO NOT REMOVE THIS GATE
     <nav> exists TWICE. Once as markup inside the <x-dc> template, which is in the
     DOM at parse time, and once in the output support.js renders from it. Querying
     document for 'nav' finds the TEMPLATE copy, and appending there is worse than
     useless: support.js reads dc.innerHTML before replacing <x-dc>, so the button
     gets serialised into the template and React re-creates a *copy* of it — a copy
     with no event listeners. You get a hamburger that renders and does nothing.
     (That failure was observed, not theorised.) support.js replaces <x-dc> with
     <div id="dc-root">, so the presence of #dc-root is the signal that the real
     tree exists; scope every query to it.

   Vanilla, no dependencies, nothing at build time.
   =========================================================================== */
(function () {
  'use strict';

  var PHONE = '(max-width: 640px)';
  var state = { header: null, btn: null };

  function setOpen(open) {
    if (!state.header || !state.btn) return;
    if (open) state.header.setAttribute('data-menu', 'open');
    else state.header.removeAttribute('data-menu');
    state.btn.setAttribute('aria-expanded', open ? 'true' : 'false');
  }

  function isOpen() {
    return !!state.header && state.header.getAttribute('data-menu') === 'open';
  }

  /* Publish the CLOSED bar height and pay for the flow space the fixed header no
     longer occupies.

     Measured CLOSED on purpose: both the chapter-rail offset and the parent's
     padding should track the bar, not the expanded panel — otherwise opening the
     menu would shove the whole page down.

     Two consumers, both CSS:
       --hdr-h           the chapter rail offsets below the bar; the header's
                         parent uses it as padding-top to replace the flow space
                         the fixed header gave up
       [data-hdr-parent] marks WHICH element that parent is

     The marker attribute exists because CSS cannot identify that element on its
     own: on the case studies two different wrappers carry a byte-identical style
     attribute, so any [style*="…"] selector would pad the wrong one too. JS knows
     which is the real parent, so it tags it and lets CSS own the media scoping.

     Doing the padding in CSS rather than as an inline style write is deliberate:
     an inline write has to be actively CLEARED above the phone tier, and if the
     clearing resize event is missed the desktop layout keeps a stale 94px gap —
     observed. A media-query rule simply stops applying, so it cannot go stale.

     Re-applied on every ResizeObserver tick so it self-heals if a React render
     ever drops the attribute. */
  function publishHeight() {
    if (!state.header) return;
    var wasOpen = isOpen();
    if (wasOpen) state.header.removeAttribute('data-menu');

    var h = Math.round(state.header.getBoundingClientRect().height);
    if (h > 0) document.documentElement.style.setProperty('--hdr-h', h + 'px');
    var parent = state.header.parentElement;
    if (parent && !parent.hasAttribute('data-hdr-parent')) {
      parent.setAttribute('data-hdr-parent', '');
    }

    if (wasOpen) state.header.setAttribute('data-menu', 'open');
  }

  function init() {
    // Gate on the rendered root, never on document — see the header comment.
    var root = document.getElementById('dc-root');
    if (!root) return false;

    var nav = root.querySelector('nav');
    if (!nav || !nav.parentElement) return false;

    var header = nav.parentElement;
    if (header.querySelector('[data-menu-toggle]')) return true; // already wired

    var btn = document.createElement('button');
    btn.type = 'button';
    btn.setAttribute('data-menu-toggle', '');
    btn.setAttribute('aria-expanded', 'false');
    btn.setAttribute('aria-label', 'Menu');
    btn.appendChild(document.createElement('span'));
    btn.appendChild(document.createElement('span'));
    btn.appendChild(document.createElement('span'));
    header.appendChild(btn);

    state.header = header;
    state.btn = btn;

    btn.addEventListener('click', function (e) {
      e.stopPropagation();
      setOpen(!isOpen());
    });

    // Escape closes and returns focus to the toggle.
    document.addEventListener('keydown', function (e) {
      if (e.key === 'Escape' && isOpen()) { setOpen(false); btn.focus(); }
    });

    // A tap outside the header closes it.
    document.addEventListener('click', function (e) {
      if (isOpen() && !header.contains(e.target)) setOpen(false);
    });

    // Choosing a page link closes the panel. The mailto CTA lives in the bar and
    // the prefs pill must stay open to be usable, so neither closes it.
    nav.addEventListener('click', function (e) {
      var a = e.target && e.target.closest ? e.target.closest('a') : null;
      if (!a || !nav.contains(a)) return;
      if ((a.getAttribute('href') || '').indexOf('mailto:') === 0) return;
      setOpen(false);
    });

    // Leaving the phone tier must not leave a stale open state behind.
    var mq = window.matchMedia(PHONE);
    var onChange = function () { if (!mq.matches) setOpen(false); publishHeight(); };
    if (mq.addEventListener) mq.addEventListener('change', onChange);
    else if (mq.addListener) mq.addListener(onChange);

    window.addEventListener('resize', publishHeight);

    /* The header can still be 0px tall at this point — support.js renders
       asynchronously, and publishHeight() deliberately refuses to publish a zero.
       A ResizeObserver catches the real height whenever it settles (first paint,
       font swap, language switch changing label widths), so --hdr-h is always
       correct rather than only correct on load. */
    if (typeof ResizeObserver === 'function') {
      new ResizeObserver(publishHeight).observe(header);
    } else {
      var n = 0, poll = setInterval(function () {
        publishHeight();
        if (++n > 20) clearInterval(poll);
      }, 150);
    }
    publishHeight();
    return true;
  }

  var tries = 0;
  (function wait() {
    try { if (init()) return; } catch (err) { return; }   // never break the page
    if (++tries > 60) return;                              // ~6s then give up
    setTimeout(wait, 100);
  })();
})();
