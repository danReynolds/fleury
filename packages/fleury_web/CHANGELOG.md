# Changelog

## 0.1.1

Requires exactly `fleury 0.1.1`.

- Adds a browser example under `example/` and stops shipping the leftover
  spike page, screenshot, and generator.
- The wire negotiation error no longer names an internal frame type, which
  optimized builds minify.

## 0.1.0

Initial public release, October 5, 2026. Requires Dart 3.10.4 or later and
exactly `fleury 0.1.0` for the matching first-party wire protocol.

- Mount a browser-safe Fleury widget tree with `mountApp`, or display a native
  process through the remote host. A retained DOM cell grid paints dirty rows,
  keeps text selectable, translates browser input, and uses the clipboard.
- Project the semantic tree into browser accessibility with stable DOM nodes,
  declared roles, live regions, focus, and numeric slider values and bounds.
  Structural updates preserve unaffected nodes and avoid re-announcing live
  regions when unrelated UI changes.
- `MountedApp.reassemble()` applies Fleury's reload lifecycle after a development
  tool replaces code, then presents the updated frame and accessibility tree.
  Dispose the returned handle when removing an embedded app.
- Render images with popup occlusion, transparency, and letterboxing; draw
  connected cell-edge corners and consistent dimmed text and box glyphs without
  fading cell backgrounds.
- Forward pointer cancellation, surface exit, and focus loss. Captured input
  retains outside-surface coordinates and honors `MouseRegion.cursor`.
- Surface unawaited callback and command failures in an error overlay above open
  panels. Healthy and dismissed states leave root repaint caches idle.
- Use `fleury_core.dart` for browser entry points. `fleury serve` remains a
  development preview rather than a hardened public hosting layer.
