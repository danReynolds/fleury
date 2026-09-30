# Changelog

## 0.1.0

Initial public release.

- Runtime error banners mount above already-open panels only while an error
  is visible; healthy and dismissed states leave root repaint caches idle.

- Numeric sliders expose their current value and bounds to browser
  accessibility, including custom resize handles.

- Unawaited async handlers and command failures reach the browser error overlay.
  Each local host guards its runtime callbacks and owns a default error reporter
  when none is supplied; setup failures still reject the mount operation.

- The semantic DOM updates in place: a structural change moves, inserts or
  removes only the nodes it changed, and text keeps its node. A screen
  reader no longer re-announces a live region (a log, a status) whenever a
  node is added or removed anywhere; an appended log line is one insertion.
  A patch that changes only content skips the full-tree semantic diff.

- Pixel images respect later popup paint and preserve the underlying cell
  background through transparent and letterboxed areas. Outer-edge corner
  glyphs U+1FB7C–U+1FB7F render as connected cell-edge rectangles.

- Dim text, block elements and box-drawing glyphs without fading cell
  backgrounds, keeping selected-row highlights continuous in the browser.
  Overlapping glyph layers retain uniform intensity at their intersections.

- Pointer cancellation, surface exit, and focus loss reach core gesture
  handlers. Captured input retains outside-surface coordinates, and browser
  cursors honor `MouseRegion.cursor` through capture and geometry changes.

- **Declared roles in the accessibility mirror.** A role outside the core
  vocabulary projects into ARIA through its core role; the element keeps the
  specific name in `data-fleury-semantic-role` and adds
  `data-fleury-semantic-core-role`.
