// Active-selection gate (selection-gate).
//
// Default-on text selection wraps every app root in a SelectionArea (see
// DefaultRootSelection). Idle selectables are free — an O(1) registration and
// one inherited lookup, with the reading-order walk running only on a
// selection EVENT, not per frame. The paths that scale with content are a
// LARGE ACTIVE selection being re-painted (each frame a selected Text
// repaints, it stamps the highlight across its selected cells) and the
// per-event work a drag does. This gate exercises both over a
// per-frame-repainting grid of Texts and pins them.
//
// IT DRIVES A REAL `SelectionArea`, not a bare scope + delegate. The
// difference is the whole point of this gate's existence: an area owns the
// gesture detector, the multi-click/anchor state machine, the key bindings
// and the clipboard write, and NONE of that is reachable by calling a
// delegate directly — which is why the previous version of this gate could
// stay green through every behavioural selection defect the launch audit
// found (its §05, and the D3 finding that named this file). The script here
// is the user's: press, drag, release; Ctrl+A; Ctrl+C; Esc — routed through
// a real `InputDispatcher` and `PointerRouter` against real painted geometry.
//
// GATED AXES — deterministic, zero drift. Pure functions of the fixture, so
// ANY drift fails:
//
//   dragSelectedChars   what a real press-drag-release selects and Ctrl+C
//                       copies. Covers the gesture path end to end: hit
//                       test -> tap-down anchor -> drag edge updates ->
//                       release -> copy. A regression that leaves the anchor
//                       unset (text under a tap-handling widget), drops the
//                       drag target, or breaks the clipboard write moves it.
//   selectAllChars      what Ctrl+A then Ctrl+C yields. The old coverage
//                       axis — every rendered Text registers as selectable
//                       and select-all reaches all of them — now taken
//                       through the area's own binding and copy rather than
//                       a hand-driven delegate.
//   highlightCells      inverse cells PAINTED while the select-all is held.
//                       The registration count says a Selectable answered;
//                       this says the highlight actually reached the buffer,
//                       over the same repaint-boundary blit path production
//                       takes.
//
// Structural invariants, enforced on EVERY run (including
// --update-baseline, so a broken shape cannot be baselined away):
// a drag selects something; select-all covers the whole grid; a held
// selection paints highlight; Esc clears it back to zero.
//
// WARN-ONLY — per-frame cost: the µs/frame a held selection ADDS versus the
// same grid with no selection (min across interleaved rounds to shed noise).
// This is the scaling signal, but it is NOT gated, for the same reason
// paint-gate keeps its µs axis warn-only: it is machine-dependent, and the
// underlying per-frame allocation is JIT-sink-nondeterministic here (the
// selection-paint temporaries do not escape, so a background tier-up can
// collapse the measured churn ~24× mid-run even under --deterministic —
// exactly the instability bin/alloc_gate.dart calls out). Gating it would
// flap CI. It is reported so a gross regression is visible; the
// deterministic axes are what fail the build.
//
//   dart run bin/selection_gate.dart [--gate] [--update-baseline]
//       [--frames=N] [--rounds=N] [--warmup=N]
//
// Exit codes: 0 pass, 1 regression, 64 usage/setup error.

import 'dart:io';

import 'package:fleury/fleury.dart';

import 'gate_support.dart';

const _defaultFrames = 200;
const _defaultRounds = 10;
const _defaultWarmup = 200;

// A large selectable grid: _rows Texts of ~_lineWidth cells each, all covered
// by the select-all. Big enough that the warn-only per-frame cost is visible.
const _rows = 40;
const _lineWidth = 60;

// The viewport fits every row so all selectables paint (and thus register), so
// the select-all genuinely covers the whole grid — an off-screen Text would
// not register and would silently shrink the coverage count.
const _size = CellSize(80, _rows + 4);

// The drag script, in cell coordinates. Row 0 is the per-frame tick line
// (deliberately excluded: its content changes, so a selection over it would
// not be a fixed number of characters). Rows 1.. are the static body lines.
const _dragFrom = CellOffset(0, 1);
const _dragTo = CellOffset(10, 3);

/// A steady-state model bumped once per frame, so the grid rebuilds and
/// repaints every frame (the selected Texts included).
class _Model extends ChangeNotifier {
  int v = 0;
  void bump() {
    v++;
    notifyListeners();
  }
}

/// A real [SelectionArea] over a per-frame-rebuilding [Column] of static
/// selectable Texts — the shape `DefaultRootSelection` gives every app,
/// with `selectAllShortcut` on so the gate can drive select-all the way a
/// user does. One tick line changes each frame to force the whole column to
/// repaint; the selectable lines are static so a selection's offsets stay
/// valid across rebuilds.
Widget _scenario(_Model m) {
  // Fixed-width body so layout cannot drift as the tick grows.
  final body = 'lorem ipsum dolor sit amet consectetur adipiscing'
      .padRight(_lineWidth)
      .substring(0, _lineWidth);
  return SelectionArea(
    child: ListenableBuilder(
      listenable: m,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('tick ${(m.v % 1000).toString().padLeft(3, '0')}'),
          for (var i = 0; i < _rows; i++)
            Text('${i.toString().padLeft(2, '0')} $body'),
        ],
      ),
    ),
  );
}

MouseEvent _mouse(MouseEventKind kind, CellOffset at) => MouseEvent(
      kind: kind,
      button: MouseButton.left,
      col: at.col,
      row: at.row,
    );

/// Counts cells painted with the selection highlight.
int _highlightCells(CellBuffer buffer) {
  var count = 0;
  for (var row = 0; row < buffer.size.rows; row++) {
    for (var col = 0; col < buffer.size.cols; col++) {
      if (buffer.atColRow(col, row).style.inverse) count++;
    }
  }
  return count;
}

Future<void> main(List<String> args) async {
  var frames = _defaultFrames;
  var rounds = _defaultRounds;
  var warmup = _defaultWarmup;
  var gate = false;
  var update = false;
  var baselinePath = 'selection_gate_baseline.json';
  for (final arg in args) {
    if (arg == '--gate') {
      gate = true;
    } else if (arg == '--update-baseline') {
      update = true;
    } else if (parseIntFlag(arg, 'frames') case final v?) {
      frames = v;
    } else if (parseIntFlag(arg, 'rounds') case final v?) {
      rounds = v;
    } else if (parseIntFlag(arg, 'warmup') case final v?) {
      warmup = v;
    } else if (arg.startsWith('--baseline=')) {
      baselinePath = arg.substring('--baseline='.length);
    } else {
      stderr.writeln('unknown argument: $arg');
      exitCode = 64;
      return;
    }
  }
  if (frames < 1 || rounds < 1 || warmup < 0) {
    stderr.writeln(
        'selection_gate: --frames/--rounds must be >= 1, --warmup >= 0.');
    exitCode = 64;
    return;
  }

  const renderer = AnsiRenderer();
  const sink = NullAnsiSink();
  final model = _Model();
  final clipboard = InProcessClipboard();
  // The production runtime object, so pointer/focus frame bookkeeping (the
  // begin/endFrame pair a hit test depends on) is the real one and cannot
  // drift from what hosts do.
  final runtime = TuiRuntime();
  final dispatcher = InputDispatcher(
    focusManager: runtime.focusManager,
    pointerRouter: runtime.pointerRouter,
  );
  runtime.mountRoot(
    wrapWithAmbientScopes(
      scene: _scenario(model),
      binding: runtime.binding,
      focusManager: runtime.focusManager,
      pointerRouter: runtime.pointerRouter,
      size: _size,
      clipboard: clipboard,
    ),
  );
  // Drive the REAL loop rather than re-implementing it, so this gate cannot
  // drift off the production path when the loop changes.
  final loop = TuiFrameLoop(renderDamage: runtime.renderDamageTracker);
  CellBuffer? lastPresented;

  void frame() {
    model.bump();
    final rendered = loop.render(
      size: _size,
      paint: runtime.renderFrame,
    )!;
    // Mirrors AnsiFramePresenter's switch, so the gate keeps measuring the
    // path production actually takes.
    final damage = rendered.damage;
    renderer.renderDiff(
      rendered.previous,
      rendered.next,
      sink,
      dirtyBounds: damage.diffBounds,
      scrollUpRows: switch (damage) {
        FrameScrolled(:final scrollUpRows) => scrollUpRows,
        FrameFullRepaint() || FrameUnchanged() || FrameChanged() => null,
      },
      hasChanges: damage is! FrameUnchanged,
    );
    lastPresented = rendered.next;
    loop.commit(rendered);
  }

  double timeFrames() {
    final sw = Stopwatch()..start();
    for (var i = 0; i < frames; i++) {
      frame();
    }
    sw.stop();
    return sw.elapsedMicroseconds / frames;
  }

  /// The user's chords, through the real dispatcher and the area's own
  /// KeyBindings — never the delegate.
  void press(KeyEvent event) => dispatcher.dispatch(event);

  void selectAll() => press(
        const KeyEvent(KeyCode.char('a'), modifiers: {KeyModifier.ctrl}),
      );
  void clearSelection() => press(const KeyEvent(KeyCode.escape));
  // Ctrl+C on an explicit SelectionArea copies WITHOUT clearing
  // (copyClearsSelection is the default wrap's behaviour, not this one's), so
  // the selection under measurement survives the read.
  String? copy() {
    press(const KeyEvent(KeyCode.char('c'), modifiers: {KeyModifier.ctrl}));
    return clipboard.lastWritten;
  }

  // Settle layout so every selectable has painted (and thus registered) and
  // the pointer router holds this frame's hit regions.
  for (var i = 0; i < warmup; i++) {
    frame();
  }

  // --- 1. A real press-drag-release, then a real copy. -------------------
  dispatcher.dispatch(_mouse(MouseEventKind.down, _dragFrom));
  dispatcher.dispatch(_mouse(MouseEventKind.drag, _dragTo));
  dispatcher.dispatch(_mouse(MouseEventKind.up, _dragTo));
  frame();
  final dragSelectedChars = (copy() ?? '').replaceAll('\n', '').length;
  final dragHighlightCells = _highlightCells(lastPresented!);

  // --- 2. Ctrl+A over the whole grid, then a real copy. ------------------
  clearSelection();
  selectAll();
  frame();
  final selectAllChars = (copy() ?? '').replaceAll('\n', '').length;
  final highlightCells = _highlightCells(lastPresented!);

  // --- 3. Esc clears the highlight back off the surface. -----------------
  clearSelection();
  frame();
  final clearedHighlightCells = _highlightCells(lastPresented!);

  // Warm both paths (with and without a selection) so neither round owns
  // cold code.
  selectAll();
  for (var i = 0; i < warmup; i++) {
    frame();
  }
  clearSelection();
  for (var i = 0; i < warmup; i++) {
    frame();
  }

  // Interleave base / active rounds and keep the MIN of each — the least-noise
  // estimate, cancelling scheduler drift between the two.
  var baseMin = double.infinity;
  var activeMin = double.infinity;
  for (var r = 0; r < rounds; r++) {
    clearSelection();
    frame(); // settle no-selection
    final b = timeFrames();
    if (b < baseMin) baseMin = b;

    selectAll();
    frame(); // settle selection
    final a = timeFrames();
    if (a < activeMin) activeMin = a;
  }
  final addedPerFrame = activeMin - baseMin;

  // ---- Structural invariants (enforced even under --update-baseline) ----
  String? broken;
  if (dragSelectedChars <= 0) {
    broken =
        'a real press-drag-release selected nothing — the SelectionArea\'s '
        'gesture path (hit test -> tap-down anchor -> drag edge -> copy) is '
        'broken. A delegate-only gate cannot see this.';
  } else if (selectAllChars < _rows * 10) {
    broken =
        'Ctrl+A copied only $selectAllChars chars — the grid did not register '
        'as selectable (viewport too small, a selection-registration '
        'regression, or the area stopped binding Ctrl+A).';
  } else if (highlightCells <= 0) {
    broken =
        'a held select-all painted no highlighted cells — the selection is '
        'registered but never reaches the buffer.';
  } else if (clearedHighlightCells != 0) {
    broken =
        'Esc left $clearedHighlightCells highlighted cells painted — clearing '
        'the selection does not clear the surface.';
  }
  if (broken != null) {
    stderr.writeln('selection_gate: $broken');
    exitCode = 64;
    return;
  }

  if (update) {
    writeBaselineJson(baselinePath, {
      'dragSelectedChars': dragSelectedChars,
      'dragHighlightCells': dragHighlightCells,
      'selectAllChars': selectAllChars,
      'highlightCells': highlightCells,
      'baseUsPerFrame': baseMin,
      'activeUsPerFrame': activeMin,
      'addedUsPerFrame': addedPerFrame,
      'frames': frames,
      'rounds': rounds,
    });
    stdout.writeln(
      'selection gate: wrote baseline $baselinePath '
      '(drag $dragSelectedChars chars / $dragHighlightCells cells; select-all '
      '$selectAllChars chars / $highlightCells cells; a held selection adds '
      '${addedPerFrame.toStringAsFixed(1)} µs/frame, warn-only).',
    );
    return;
  }

  stdout.writeln('real SelectionArea over a repainting ${_rows}-row grid:');
  stdout.writeln(
    '  drag+copy covers       $dragSelectedChars chars, '
    '$dragHighlightCells cells   (gated)',
  );
  stdout.writeln(
    '  Ctrl+A+Ctrl+C covers   $selectAllChars chars, '
    '$highlightCells cells   (gated)',
  );
  stdout.writeln('  Esc clears to          $clearedHighlightCells cells');
  stdout.writeln(
    '  base   (no selection)  ${baseMin.toStringAsFixed(1)} µs/frame',
  );
  stdout.writeln(
    '  active (select-all)    ${activeMin.toStringAsFixed(1)} µs/frame',
  );
  stdout.writeln(
    '  selection adds         ${addedPerFrame.toStringAsFixed(1)} µs/frame  '
    '(warn-only; machine-dependent)',
  );

  if (!gate) return;

  final base = readBaselineOrNull(baselinePath, gateName: 'selection gate');
  if (base == null) {
    exitCode = 64;
    return;
  }
  final counters = <String, int>{
    'dragSelectedChars': dragSelectedChars,
    'dragHighlightCells': dragHighlightCells,
    'selectAllChars': selectAllChars,
    'highlightCells': highlightCells,
  };
  var failed = false;
  for (final entry in counters.entries) {
    final expected = (base[entry.key] as num?)?.toInt();
    if (expected == null) {
      stdout.writeln(
        'selection gate: baseline has no "${entry.key}" — re-baseline with '
        '--update-baseline.',
      );
      failed = true;
      continue;
    }
    if (entry.value != expected) {
      stdout.writeln(
        'selection gate: ${entry.key} is ${entry.value} vs baseline '
        '$expected — FAIL.',
      );
      failed = true;
    }
  }
  if (failed) {
    stderr.writeln(
      'selection gate: the fixture no longer selects, copies or highlights '
      'what it did. A SelectionArea gesture / registration / copy / highlight '
      'regression? If the fixture changed intentionally, re-baseline with '
      '--update-baseline.',
    );
    exitCode = 1;
    return;
  }
  final baselineAdded = (base['addedUsPerFrame'] as num).toDouble();
  stdout.writeln(
    'selection gate: drag, select-all, copy and highlight all match baseline '
    '— pass. (cost ${addedPerFrame.toStringAsFixed(1)} vs '
    '~${baselineAdded.toStringAsFixed(1)} µs/frame, warn-only.)',
  );
}
