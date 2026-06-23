---
title: Layout
description: Arrange widgets on the cell grid — rows, columns, flex, spacing, and constraints.
---

Fleury lays out exactly like Flutter — **constraints go down, sizes go up** — with
one difference: everything is measured in whole **terminal cells**, not pixels.
A parent hands each child a `CellConstraints` (a min/max width and height in
cells); the child picks a size within them and reports it back; the parent
positions it. There's no floating-point math, and "no upper bound" is an
explicit `null` max rather than a huge number — so an unbounded height is
genuinely unbounded, not `999999`.

You compose layout from small single-purpose widgets. Here are the ones you'll
reach for, roughly most-used first.

## Rows and columns

`Row` and `Column` are the workhorses — they lay children out along a **main
axis** (horizontal for `Row`, vertical for `Column`) and align them on the
**cross axis**.

```dart
Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    Text('Title'),
    Text('Subtitle'),
  ],
)
```

Three knobs control how children are placed:

- **`mainAxisAlignment`** — distributes children along the main axis:
  `start`, `end`, `center`, `spaceBetween`, `spaceAround`, `spaceEvenly`.
- **`crossAxisAlignment`** — aligns each child across the main axis:
  `start`, `end`, `center`, `stretch` (`stretch` makes children fill the cross
  axis).
- **`mainAxisSize`** — `max` (default — take all the space the parent allows) or
  `min` (shrink to just fit the children). Use `min` when a `Row` inside a wider
  parent should hug its contents instead of spreading across the whole width.

`Row` and `Column` are both thin wrappers over `Flex`; reach for `Flex(direction:
…)` directly only when the axis is computed at runtime.

## Sharing space: Expanded and Flexible

Children take their natural size until you ask one to *grow*. Wrap a child in
`Expanded` and it absorbs the leftover main-axis space; give several an
`Expanded` and they split it by `flex` weight.

```dart
Row(
  children: [
    SizedBox(width: 12, child: Sidebar()),   // fixed 12 cells
    Expanded(child: MainContent()),          // everything left over
  ],
)

Row(
  children: [
    Expanded(flex: 2, child: Left()),   // two-thirds
    Expanded(flex: 1, child: Right()),  // one-third
  ],
)
```

`Expanded` forces the child to fill its share exactly. `Flexible` is the looser
cousin — `Flexible(flex: …, fit: FlexFit.loose, child: …)` lets the child take
*up to* its share but shrink smaller if it wants. (`Expanded` is just `Flexible`
with `fit: FlexFit.tight`.) When the integer space doesn't divide evenly, the
remainder is handed to the leftmost flex children one cell at a time, so layout
stays deterministic.

> For a flexible gap, use `Spacer()` — it expands to push siblings apart, and
> `Spacer(flex: 2)` takes a bigger share than a plain `Spacer()`. For a *fixed*
> gap, use a `SizedBox` with a width or height (below).

## Fixed sizes and gaps: SizedBox

`SizedBox` pins a width and/or height in cells, or inserts a gap between
siblings:

```dart
Column(
  children: [
    Header(),
    SizedBox(height: 1),   // a one-row gap
    Body(),
  ],
)

SizedBox(width: 20, child: ProgressBar(value: 0.4))   // a 20-cell-wide bar
```

A `null` width or height means "as large as the parent allows on that axis," so
`SizedBox(height: 4, child: …)` fixes the height and lets the width flow. The
named constructors cover the common cases: `SizedBox.shrink()` (zero), and
`SizedBox.expand(child: …)` (fill the parent both ways).

## Spacing inside a widget: Padding

`Padding` insets its child. The inset is an `EdgeInsets`, always in whole cells:

```dart
Padding(
  padding: EdgeInsets.all(1),
  child: Text('breathing room on all four sides'),
)

Padding(
  padding: EdgeInsets.symmetric(horizontal: 2, vertical: 1),
  child: Card(),
)
```

`EdgeInsets` has three constructors — `EdgeInsets.all(2)`,
`EdgeInsets.symmetric(horizontal: …, vertical: …)`, and
`EdgeInsets.only(left: …, top: …, right: …, bottom: …)` — plus `EdgeInsets.zero`.
(There's no `fromLTRB`; use `only`.)

## Positioning a single child: Center and Align

`Center` centres its child within the space it's given. `Align` places it at one
of nine well-known positions:

```dart
Center(child: Text('Loading…'))

Align(
  alignment: Alignment.bottomRight,
  child: Text('v0.0.0'),
)
```

`Alignment` is a fixed set of nine values — `topLeft`, `topCenter`, `topRight`,
`centerLeft`, `center`, `centerRight`, `bottomLeft`, `bottomCenter`,
`bottomRight`. (A cell grid doesn't need Flutter's continuous `Alignment(x, y)`,
so it isn't there.) Both widgets expand to fill the space they're offered, then
place the child — so they only do something useful when they have room to spare.

## The all-in-one: Container

`Container` composes the common decorations — size, padding, margin, a
background colour, and a border — into one widget, so you don't nest four:

```dart
Container(
  width: 24,
  padding: EdgeInsets.all(1),
  color: RgbColor(30, 30, 46),
  border: BoxBorder(style: BorderStyle.rounded),
  child: Text('a bordered, padded, filled box'),
)
```

It layers outer-to-inner: size → border → background fill → padding → align →
child. One thing to know: **`width` and `height` are the outer dimensions,
border included** — a `Container(width: 10, border: BoxBorder.all())` gives the
child 8 cells of interior, not 10. Leave `alignment` unset and the child
stretches to fill; set it and the child is placed at that alignment instead.

## Constraints and intrinsic sizing

Most layout falls out of the above. When you need to bound or measure a child
directly:

- **`ConstrainedBox(minWidth: …, maxWidth: …, minHeight: …, maxHeight: …, child:
  …)`** clamps the child's size. If your bounds conflict with the parent's (you
  ask for `minWidth: 50` inside a 20-cell parent), the parent wins — a child can
  never be forced larger than the space it's given.
- **`IntrinsicWidth` / `IntrinsicHeight`** size a child to its *natural* extent —
  the widest (or tallest) it wants to be — instead of the widest the parent
  offers. Handy for making a column of buttons all match the widest label. It
  costs an extra measurement pass per layout, so use it deliberately.
- **`AspectRatio(aspectRatio: …, child: …)`** sizes the child to a width÷height
  ratio. Remember terminal cells are about twice as tall as they are wide, so
  `aspectRatio: 0.5` reads as visually square, not `1.0`.

## Layering and wrapping

- **`Stack`** overlays children at the same origin; later children paint over
  earlier ones. Wrap a child in **`Positioned(left: …, top: …, width: …, height:
  …, child: …)`** to float it at a fixed offset. Non-positioned children set the
  stack's size; positioned ones float on top.
- **`IndexedStack(index: …, children: …)`** shows one child at a time but keeps
  the others mounted — their state survives while they're off-screen (good for
  tab bodies).
- **`Wrap(spacing: …, runSpacing: …, children: …)`** flows children left-to-right
  and wraps to a new row when the next one won't fit — like a `Row` that knows
  when to break.

## When children don't fit

If a `Row` or `Column`'s children need more space than it has, Fleury clips them
and paints a red `▓` marker along the overflowing edge — the terminal version of
Flutter's overflow stripes. It's a signal to add an `Expanded`, drop to a
`SizedBox`, or make the content scroll. It never silently corrupts the layout
around it.

---

Every layout widget here is exported from the main `fleury` import, and each
takes a `child` (or `children`) like any other widget — layout *is* just more
widgets. For the leaf widgets that go inside these — text, inputs, charts,
viewers — see the [widget reference](/widgets/). For how a widget tree turns
into state and rebuilds, see [Widgets & state](/concepts/widgets-and-state/).
