// Client-side behavior for the Daily Report plus-sign template picker (#18835).
// The dropdown open/close, focus, and keyboard nav are handled by Redmine core's
// `drdn` component. This adds:
//   1. a filter that narrows the visible options as the user types, and
//   2. viewport positioning: the menu is position:fixed (see the stylesheet) so
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

  // After core toggles the menu open, position it (rAF so its size is known).
  document.addEventListener('click', function (e) {
    var trigger = e.target.closest && e.target.closest('.account-request-templates .drdn-trigger');
    if (!trigger) return;
    var drdn = trigger.closest('.drdn.account-request-templates');
    if (!drdn) return;
    requestAnimationFrame(function () {
      if (drdn.classList.contains('expanded')) positionMenu(drdn);
    });
  });

  // Keep an open menu glued to its trigger as the page or a scroll container
  // moves (fixed elements don't scroll with content). Capture phase catches
  // scrolls inside #content too.
  window.addEventListener('scroll', repositionOpenMenus, true);
  window.addEventListener('resize', repositionOpenMenus);
})();
