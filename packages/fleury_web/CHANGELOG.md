# Changelog

## 0.1.0

Initial public release.

- Pointer cancellation, surface exit, and focus loss reach core gesture
  handlers. Captured input retains outside-surface coordinates, and browser
  cursors honor `MouseRegion.cursor` through capture and geometry changes.

- **Declared roles in the accessibility mirror.** A role outside the core
  vocabulary projects into ARIA through its core role; the element keeps the
  specific name in `data-fleury-semantic-role` and adds
  `data-fleury-semantic-core-role`.
