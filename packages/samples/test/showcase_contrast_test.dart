// Every showcase keeps its text visible against what it is painted on.
//
// A selection fill, a focus color, and a theme's text color are separate
// style roles. Where a widget layers one over another, a theme can paint text
// in its own background color: the system monitor's selected process row once
// read as a solid green bar, and the coding agent highlighted the block it was
// still streaming. These tests drive each showcase through its focus stops (the
// theme studio through every bundled theme) and fail on any text cell whose
// contrast is too low to read at all.

import 'dart:math' as math;

import 'package:fleury/fleury.dart';
import 'package:fleury/themes.dart';
import 'package:fleury_samples/samples.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:test/test.dart';

/// Below this, text is effectively the color of its background (WCAG's
/// readable minimum is 4.5; this only catches text that is not there at all).
const double _invisible = 1.5;

// A cell with no foreground or background shows the host's own, which the
// sample theme matches.
final RgbColor _hostForeground = fleurySampleTheme.colorScheme.foreground!
    .toRgb();
final RgbColor _hostBackground = fleurySampleTheme.colorScheme.background!
    .toRgb();

// Glyphs whose paint is the shape itself, not text on a background: blocks,
// shades, braille and sextant dots, and box drawing.
final RegExp _shapeGlyph = RegExp(
  r'^[─-▟⠀-⣿\u{1FB00}-\u{1FBFF}]$',
  unicode: true,
);

double _luminance(RgbColor c) {
  double channel(int value) {
    final s = value / 255;
    return s <= 0.03928
        ? s / 12.92
        : math.pow((s + 0.055) / 1.055, 2.4).toDouble();
  }

  return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
}

double _contrast(RgbColor a, RgbColor b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// Each run of unreadable text in the current frame, as `row: "text"`.
List<String> _unreadable(FleuryTester tester, CellSize size) {
  final buffer = tester.render(size: size);
  final found = <String>[];
  for (var row = 0; row < size.rows; row++) {
    final run = StringBuffer();
    void flush() {
      final text = run.toString().trim();
      if (text.isNotEmpty) found.add('row $row: "$text"');
      run.clear();
    }

    for (var col = 0; col < size.cols; col++) {
      final cell = buffer.atColRow(col, row);
      final glyph = cell.grapheme;
      if (cell.role != CellRole.leading || glyph == null || glyph == ' ') {
        if (run.isNotEmpty && glyph == ' ') {
          run.write(' ');
        } else {
          flush();
        }
        continue;
      }
      final style = cell.style;
      var foreground = style.foreground?.toRgb() ?? _hostForeground;
      var background = style.background?.toRgb() ?? _hostBackground;
      if (style.inverse) {
        (foreground, background) = (background, foreground);
      }
      if (style.dim) foreground = foreground.mix(background, 0.5);
      if (!_shapeGlyph.hasMatch(glyph) &&
          _contrast(foreground, background) < _invisible) {
        run.write(glyph);
      } else {
        flush();
      }
    }
    flush();
  }
  return found;
}

typedef _Step = (String, void Function(FleuryTester));

_Step _key(KeyCode code) => ('$code', (t) => t.sendKey(KeyEvent(code)));

_Step _wait(int ms) =>
    ('wait ${ms}ms', (t) => t.pump(Duration(milliseconds: ms)));

// More than any showcase has, so Tab wraps and every control gets a turn.
const _tabStops = 24;

// Escape closes any popup the arrows opened, which would otherwise hold focus.
const _moves = <KeyCode>[
  KeyCode.arrowDown,
  KeyCode.arrowDown,
  KeyCode.arrowRight,
  KeyCode.arrowUp,
  KeyCode.escape,
];

/// Drives [app] and fails on any frame with unreadable text: after [setup],
/// through the [script] steps, then across [_tabStops] focus stops (pressing
/// [_moves] at each), and finally after live content has run for a while.
/// Moves skip a focused control labelled [holdStill] (the theme studio's
/// picker, which would switch away from the theme under test). When given,
/// [stillShows] must remain on screen at the end, proving the run stayed in
/// the state it set up.
void _expectReadable(
  String name,
  Widget Function() app,
  CellSize size, {
  List<_Step> setup = const <_Step>[],
  List<_Step> script = const <_Step>[],
  String? holdStill,
  String? stillShows,
}) {
  testWidgets('$name keeps its text readable', (tester) {
    tester.viewportSize = size;
    // The docs embed every showcase in a traversal group, so Tab moves focus.
    tester.pumpWidget(FocusTraversalGroup(child: app()));
    // Let intro animations settle (the arcade title fades in).
    tester.pump(const Duration(milliseconds: 1500));
    for (final (_, act) in setup) {
      act(tester);
      tester.pump(const Duration(milliseconds: 16));
    }
    final failures = <String>[];
    void check(String when) {
      for (final finding in _unreadable(tester, size)) {
        failures.add('$when, $finding');
      }
    }

    void run(_Step step) {
      step.$2(tester);
      tester.pump(const Duration(milliseconds: 16));
      check('after ${step.$1}');
    }

    check('initially');
    script.forEach(run);
    for (var stop = 0; stop < _tabStops; stop++) {
      final held = tester
          .semantics()
          .where(focused: true)
          .any((node) => node.label == holdStill);
      if (!held) _moves.map(_key).forEach(run);
      run(_key(KeyCode.tab));
    }
    run(_wait(8000));
    expect(failures, isEmpty, reason: 'text painted in its background color');
    if (stillShows != null) {
      expect(tester.renderToString(size: size), contains(stillShows));
    }
  });
}

void main() {
  // Sizes match the docs-site embeds.
  _expectReadable('system monitor', DashboardApp.new, const CellSize(108, 38));
  _expectReadable('file manager', FileManagerApp.new, const CellSize(104, 26));
  _expectReadable(
    'coding agent',
    AgentApp.new,
    const CellSize(92, 34),
    script: <_Step>[
      for (var i = 0; i < 12; i++) _wait(420),
      _key(KeyCode.enter),
      for (var i = 0; i < 8; i++) _wait(420),
    ],
  );
  _expectReadable('text editor', EditorApp.new, const CellSize(80, 24));
  _expectReadable(
    'command editor',
    CommandWorkbenchApp.new,
    const CellSize(82, 28),
  );
  _expectReadable('personal finance', FinanceApp.new, const CellSize(108, 46));
  _expectReadable(
    'service deployment',
    FormsShowcaseApp.new,
    const CellSize(84, 30),
  );
  _expectReadable(
    'state management',
    StateManagementShowcaseApp.new,
    const CellSize(80, 28),
  );
  // The picker lists every bundled theme, then Custom.
  for (var index = 0; index <= fleuryThemes.length; index++) {
    final custom = index == fleuryThemes.length;
    final name = custom ? 'Custom' : fleuryThemes[index].name;
    _expectReadable(
      'theme studio ($name)',
      ThemingShowcaseApp.new,
      const CellSize(108, 34),
      // The first Down opens the picker on Nord; each later one moves on.
      setup: <_Step>[
        for (var i = 0; i <= index; i++) _key(KeyCode.arrowDown),
        _key(KeyCode.enter),
      ],
      holdStill: 'Theme',
      stillShows: custom ? 'CUSTOM THEME' : 'rendered by $name.',
    );
  }
  _expectReadable(
    'neon asteroids',
    NeonAsteroidsApp.new,
    const CellSize(100, 32),
  );
  _expectReadable(
    'ANSI sprite studio',
    AnsiSpriteStudioApp.new,
    const CellSize(108, 40),
  );
  _expectReadable(
    'interactive CLI commands',
    InlineSetupPreview.new,
    const CellSize(84, 29),
  );
}
