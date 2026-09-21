// Client-side behavior for the Daily Report plus-sign template picker (#18835).
// The dropdown open/close is handled by Redmine core's `drdn` component. This
// adds:
//   1. a filter that narrows the visible options as the user types,
//   2. combobox-style selection: one "active" option, highlighted by mouse hover
//      or ArrowUp/ArrowDown while focus stays in the filter box, opened with
//      Enter. Typing auto-highlights the first match, so "grant" + Enter works.
//      Core's drdn keydown handler moves real focus between links and ignores
//      the filter (it lands on hidden options), so we handle these keys first
//      in the capture phase and stop them reaching it, and
//   3. viewport positioning: the menu is position:fixed (see the stylesheet) so
//      it escapes #content's overflow and the report table, which otherwise clip
//      it at the bottom of the table. We place it at the trigger here, flipping
//      it above the trigger when there isn't room below.
(function () {
  'use strict';

  var GAP = 2; // px between trigger and menu

  function filterItems(input) {
    var drdn = input.closest('.drdn.account-request-templates');
    if (!drdn) return;
    var query = input.value.trim().toLowerCase();
    var options = drdn.querySelectorAll('.drdn-items > a.template-option');
    options.forEach(function (opt) {
      // The visible text already includes the label + subject template, so a
      // single haystack covers both.
      var haystack = opt.textContent.toLowerCase();
      opt.style.display = (query === '' || haystack.indexOf(query) !== -1) ? '' : 'none';
    });
    // With a query, highlight the best (first) match so Enter picks it; with an
    // empty box nothing is implied.
    setActive(drdn, query === '' ? null : visibleOptions(drdn)[0], true);
  }

  function visibleOptions(drdn) {
    return Array.prototype.filter.call(
      drdn.querySelectorAll('.drdn-items > a.template-option'),
      function (opt) { return opt.style.display !== 'none'; }
    );
  }

  function activeOption(drdn) {
    return drdn.querySelector('.drdn-items > a.template-option.active');
  }

  // `scroll` brings the option into view; only keyboard/filter moves want that.
  // Hover must not scroll: at the list's edge the hovered option is partly
  // clipped, scrolling it in slides the next one under the pointer, and the list
  // creeps along on its own.
  function setActive(drdn, opt, scroll) {
    var current = activeOption(drdn);
    if (current === opt) return;
    if (current) current.classList.remove('active');
    if (opt) {
      opt.classList.add('active');
      if (scroll) opt.scrollIntoView({ block: 'nearest' });
    }
  }

  // Move the highlight by `step` (+1/-1) through the visible options, stopping
  // at either end. Stepping up from the first option clears the highlight.
  function moveActive(drdn, step) {
    var options = visibleOptions(drdn);
    if (options.length === 0) return;
    var index = options.indexOf(activeOption(drdn));
    var next = index === -1 ? (step > 0 ? 0 : -1) : index + step;
    if (next >= options.length) next = options.length - 1;
    setActive(drdn, next < 0 ? null : options[next], true);
  }

  function closeMenu(drdn) {
    drdn.classList.remove('expanded');
    setActive(drdn, null);
  }

  // Position an open (expanded) menu at its trigger, in viewport coordinates.
  function positionMenu(drdn) {
    var trigger = drdn.querySelector('.drdn-trigger');
    var content = drdn.querySelector('.drdn-content');
    if (!trigger || !content) return;

    var rect = trigger.getBoundingClientRect();
    var vh = window.innerHeight;
    var vw = window.innerWidth;
    var cw = content.offsetWidth;
    var ch = content.offsetHeight;

    // Align the menu's right edge with the trigger's right edge, clamped to the
    // viewport.
    var left = Math.min(Math.max(4, rect.right - cw), vw - cw - 4);

    // Open downward by default; flip up when the menu wouldn't fit below but
    // fits (better) above.
    var spaceBelow = vh - rect.bottom;
    var openUp = spaceBelow < ch + GAP && rect.top > spaceBelow;
    var top = openUp ? Math.max(4, rect.top - ch - GAP) : rect.bottom + GAP;

    content.style.left = left + 'px';
    content.style.top = top + 'px';
  }

  function repositionOpenMenus() {
    document.querySelectorAll('.drdn.account-request-templates.expanded')
      .forEach(positionMenu);
  }

  document.addEventListener('input', function (e) {
    var input = e.target;
    if (input.matches && input.matches('.account-request-templates .autocomplete')) {
      filterItems(input);
    }
  });

  // Capture phase so we run before core's drdn keydown handler (bound on
  // .drdn-content) and can keep it from also moving focus.
  document.addEventListener('keydown', function (e) {
    var content = e.target.closest && e.target.closest('.account-request-templates .drdn-content');
    if (!content) return;
    var drdn = content.closest('.drdn.account-request-templates');
    var input = drdn.querySelector('.autocomplete');

    switch (e.key) {
    case 'ArrowDown':
    case 'ArrowUp':
      moveActive(drdn, e.key === 'ArrowDown' ? 1 : -1);
      if (input && document.activeElement !== input) input.focus();
      break;
    case 'Enter':
      var opt = activeOption(drdn);
      if (!opt) return; // e.g. Enter on a Tab-focused link: let it open natively
      opt.click(); // trusted keypress, so target=_blank opens a tab
      closeMenu(drdn);
      break;
    case 'Escape':
      closeMenu(drdn);
      var trigger = drdn.querySelector('.drdn-trigger');
      if (trigger) trigger.focus();
      break;
    default:
      return;
    }
    e.preventDefault();
    e.stopPropagation();
  }, true);

  // Mouse hover drives the same highlight as the keyboard. mousemove (not
  // mouseover) so keyboard scrolling under a resting pointer doesn't steal it.
  document.addEventListener('mousemove', function (e) {
    var opt = e.target.closest && e.target.closest('.account-request-templates .drdn-items > a.template-option');
    if (!opt) return;
    setActive(opt.closest('.drdn.account-request-templates'), opt);
  });

  // After core toggles the menu open, position it (rAF so its size is known).
  document.addEventListener('click', function (e) {
    var trigger = e.target.closest && e.target.closest('.account-request-templates .drdn-trigger');
    if (!trigger) return;
    var drdn = trigger.closest('.drdn.account-request-templates');
    if (!drdn) return;
    requestAnimationFrame(function () {
      if (!drdn.classList.contains('expanded')) return;
      var input = drdn.querySelector('.autocomplete');
      // Start each open at the top of the list. The panel is only hidden while
      // closed, so the browser keeps its scroll offset across close/open (and
      // Firefox even restores it across a page reload).
      var items = drdn.querySelector('.drdn-items');
      if (items) items.scrollTop = 0;
      setActive(drdn, null);
      if (input) filterItems(input); // re-highlight the first match if a query remains
      positionMenu(drdn);
    });
  });

  // Keep an open menu glued to its trigger as the page or a scroll container
  // moves (fixed elements don't scroll with content). Capture phase catches
  // scrolls inside #content too.
  window.addEventListener('scroll', repositionOpenMenus, true);
  window.addEventListener('resize', repositionOpenMenus);
})();
