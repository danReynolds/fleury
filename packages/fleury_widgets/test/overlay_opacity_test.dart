// Floating overlays are opaque.
//
// A floating overlay composites over whatever is already painted — cells are
// not auto-cleared — so any cell inside its frame that the overlay does not
// write itself shows the app underneath. That is what `Surface` is for, and
// every stock float sits on one.
//
// The leak is invisible until an overlay has an interior cell it doesn't
// write, so each case here is built to HAVE one:
//   - a tooltip whose message wraps (the last line is short),
//   - a select / menu / completion list whose entries differ in length (the
//     short rows have trailing interior cells),
//   - a command palette, whose query row is narrower than the palette.
//
// All of those except Menu were verified to FAIL when their Surface is taken
// away — i.e. they were really leaking. Menu is the exception: `_rowText` pads
// every row to the full width already, so it cannot bleed today and its
// Surface is belt-and-braces. Its case is kept anyway because what's asserted
// is the user-visible invariant (nothing shows through), not the mechanism —
// it stays honest if that padding is ever dropped.
//
// The method: paint a wall of `X` behind the overlay, then require the cells
// between its frame edges to be free of `X`. `_interior` does that per row.

import 'package:fleury/fleury.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:fleury_widgets/fleury_widgets.dart';
import 'package:test/test.dart';

const _cols = 34;
const _rows = 10;
const _size = CellSize(_cols, _rows);

/// A wall of `X` under [overlayOwner], so anything the overlay fails to paint
/// inside its own frame shows up as an `X`.
Widget _wall(Widget overlayOwner) => Stack(
  children: [
    Column(children: [for (var i = 0; i < _rows; i++) Text('X' * _cols)]),
    overlayOwner,
  ],
);

String _screen(FleuryTester tester) =>
    tester.renderToString(size: _size, emptyMark: ' ');

/// The cells strictly between the first `│` and the last `│` on each framed
/// row — i.e. the overlay's interior. Rows without a frame are skipped.
Iterable<String> _interior(String screen) sync* {
  for (final line in screen.split('\n')) {
    final left = line.indexOf('│');
    final right = line.lastIndexOf('│');
    if (left < 0 || right <= left) continue;
    yield line.substring(left + 1, right);
  }
}

void _expectOpaque(FleuryTester tester, {required String showing}) {
  final screen = _screen(tester);
  expect(screen, contains(showing), reason: 'the overlay is actually open');
  final interior = _interior(screen).toList();
  expect(interior, isNotEmpty, reason: 'found the overlay frame');
  for (final row in interior) {
    expect(
      row,
      isNot(contains('X')),
      reason:
          'the wall behind bled through the overlay frame.\n'
          'Interior rows:\n${interior.join('\n')}',
    );
  }
}

void main() {
  testWidgets('a wrapping Tooltip is opaque', (tester) {
    // Long enough to wrap: the short last line leaves interior cells that an
    // unbacked frame would let the wall show through.
    tester.pumpWidget(
      _wall(
        const Tooltip(
          message: 'Save the current file to disk now',
          child: Focus(autofocus: true, child: Text('Save')),
        ),
      ),
    );
    _expectOpaque(tester, showing: 'Save the current file');
  });

  testWidgets('an open Select is opaque', (tester) {
    tester.pumpWidget(
      _wall(
        Select<String>(
          options: const [
            SelectOption(value: 'a', label: 'Alpha'),
            SelectOption(value: 'b', label: 'B'), // short row → interior cells
          ],
          value: 'a',
          onChanged: (_) {},
          autofocus: true,
        ),
      ),
    );
    tester.render(size: _size);
    tester.press(KeySequence.enter); // open the dropdown
    _expectOpaque(tester, showing: 'Alpha');
  });

  testWidgets('an open completion popup is opaque', (tester) {
    tester.pumpWidget(
      _wall(
        CompletionTextInput(
          provider: (request) => const [
            TextCompletionOption(label: 'checkout', detail: 'Switch'),
            TextCompletionOption(label: 'ci'), // short row
          ],
          autofocus: true,
        ),
      ),
    );
    tester.render(size: _size);
    tester.type('c');
    _expectOpaque(tester, showing: 'checkout');
  });

  // Menu pads its rows to full width itself (see `_rowText`), so this passes
  // with or without the Surface today. It guards the invariant, not the
  // mechanism — see the header note.
  testWidgets('an open Menu is opaque', (tester) {
    tester.pumpWidget(
      _wall(
        Menu(
          trigger: const Text('Edit'),
          autofocus: true,
          items: [
            MenuItem(label: 'Duplicate file', onSelect: _noop),
            MenuItem(label: 'Cut', onSelect: _noop), // short row
          ],
        ),
      ),
    );
    tester.render(size: _size);
    tester.press(KeySequence.enter); // open the menu
    _expectOpaque(tester, showing: 'Duplicate file');
  });

  testWidgets('a ColorPicker hex popover is opaque and short', (tester) {
    tester.pumpWidget(
      _wall(
        Navigator(
          home: ColorPicker(
            value: const AnsiColor(1),
            autofocus: true,
            onChanged: (_) {},
          ),
        ),
      ),
    );
    tester.render(size: _size);
    tester.type('#');
    _expectOpaque(tester, showing: 'Hex');
    final interior = _interior(_screen(tester)).toList();
    expect(
      interior.length,
      lessThanOrEqualTo(4),
      reason: 'hex popover must shrink to its contents, not fill the terminal',
    );
  });

  testWidgets('an Autocomplete dropdown is opaque', (tester) {
    tester.pumpWidget(
      _wall(
        const Autocomplete<String>(options: ['Alpha', 'B'], autofocus: true),
      ),
    );
    tester.render(size: _size);
    tester.type('a');
    _expectOpaque(tester, showing: 'Alpha');
  });

  testWidgets('a CommandPalette is opaque', (tester) {
    // The palette used to hand-pad every interior line with full-width blanks
    // to stay opaque; it sits on a Surface now, so the padding is gone and
    // this is what keeps it honest.
    tester.pumpWidget(
      _wall(
        const CommandPalette(
          commands: [Command(label: 'Open File', onInvoke: _noop)],
          width: 24,
          maxVisible: 3,
        ),
      ),
    );
    _expectOpaque(tester, showing: 'Open File');
  });
}

void _noop() {}
