# Image composition closeout — 2026-09-16

Flark's image editor exposed two composition defects: a later popup left the
image visible above its text, and image letterboxing discarded the surrounding
background after a theme change. These belong in Fleury's shared rendering
contract, across standalone web, remote web, terminal and cached composition.

`CellBuffer.imagePlacements` continues to expose recorded placements. The new
`visibleImagePlacements` supplies presenter slices after opaque cell paint,
preserving each image's fit box and source offsets. Holes are frozen before a
later image paint can replace the cell roles. Overlay cells carry the underlying
background through scratch/cache copies, DOM spans and ANSI background changes.
Pixel presenters consume the visible list; ordinary overlapping images retain
paint order. Empty/image-free frames retain their fast path.

Review found another retained-frame case: image A, an opaque cover, then image B
can have the same final cell grid and recorded placements as A followed by B.
If B contains transparent pixels, A's retained hole changes the visible result.
The new regression failed with an unchanged diff before the correction. Frame
comparison now uses visible slices, including both directions of that change
and an identical-frame control.

The browser glyph renderer also recognizes the standard outer-edge corner
glyphs U+1FB7C–U+1FB7F. Each occupies one cell and paints two edge rectangles;
this lets aligned table frames use the existing block-element surface.

The work was applied to current main `d6701677` without copying the old generated
client over upstream fixes. The embedded remote client was rebuilt from the
combined sources. The unrelated fixed-pane layout optimization is excluded.

Validation is local, with CI intentionally skipped at the owner's request.
The six image regressions cover popup holes, clipped composition, repainting,
parent-background changes and invisible cell-grid differences. Browser
dogfooding of Flark checks table edit/undo, image popover/edit dialog occlusion,
light/dark backgrounds and scrolling. This does not qualify physical IME or
every terminal graphics protocol; protocol encoder tests and PTY checks are
distinct from a real terminal graphics-device run.
