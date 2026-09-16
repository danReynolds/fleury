# Changelog

## 0.1.0

Initial public release.

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
