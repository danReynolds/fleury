// Active-selection gate (selection-gate).
//
// Default-on text selection wraps every app root in a SelectionArea (see
// DefaultRootSelection). Idle selectables are free — an O(1) registration and
// one inherited lookup, with the reading-order walk running only on a
// selection EVENT, not per frame. The one path that scales with content is a
// LARGE ACTIVE selection being re-painted: each frame a selected Text repaints,
// it stamps the highlight across its selected cells. This gate exercises that
// worst case — a select-all held over a per-frame-repainting grid of Texts —
// and pins it.
//
// GATED AXIS — deterministic, zero drift: the number of cells a select-all
// covers over the grid. It is a pure function of the fixture, so it fails on
// ANY drift. It protects the SELECTABLE-REGISTRATION invariant that default-on
// selection rests on: every rendered Text attaches to the ambient selection
// scope and a select-all reaches all of them. A regression in
// `attachToSelection` / SelectionScope registration that silently drops some
// Texts drops the count and fails here. (The run_app / DefaultRootSelection
// WIRING — that the host actually installs the scope around every app root —
// is covered by the widget tests in default_root_selection_test.dart, which
// pump through the tester's real DefaultRootSelection wrap; this gate drives a
// SelectionScope directly so it can hold a large selection without an input
// stack.)
//
// WARN-ONLY — per-frame cost: the µs/frame a held selection ADDS versus the
// same grid with no selection (min across interleaved rounds to shed noise).
// This is the scaling signal, but it is NOT gated, for the same reason
// paint-gate keeps its µs axis warn-only: it is machine-dependent, and the
// underlying per-frame allocation is JIT-sink-nondeterministic here (the
// selection-paint temporaries do not escape, so a background tier-up can
// collapse the measured churn ~24× mid-run even under --deterministic —
// exactly the instability bin/alloc_gate.dart calls out). Gating it would flap
// CI. It is reported so a gross regression is visible; the deterministic
// coverage axis is what fails the build.
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

/// A steady-state model bumped once per frame, so the grid rebuilds and
/// repaints every frame (the selected Texts included).
class _Model extends ChangeNotifier {
  int v = 0;
  void bump() {
    v++;
    notifyListeners();
  }
}

/// A [SelectionScope] over a per-frame-rebuilding [Column] of static
/// selectable Texts. The gate drives [delegate] directly (select-all / clear),
/// so the selection state is under test control without an input stack. One
/// tick line changes each frame to force the whole column to repaint; the
/// selectable lines are static so their select-all offsets stay valid across
/// rebuilds.
Widget _scenario(_Model m, SelectionContainerDelegate delegate) {
  // Fixed-width body so layout cannot drift as the tick grows.
  final body = 'lorem ipsum dolor sit amet consectetur adipiscing'
      .padRight(_lineWidth)
      .substring(0, _lineWidth);
  return SelectionScope(
    registrar: delegate,
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
    stderr.writeln('selection_gate: --frames/--rounds must be >= 1, --warmup >= 0.');
    exitCode = 64;
    return;
  }

  const renderer = AnsiRenderer();
  const sink = NullAnsiSink();
  final owner = BuildOwner();
  final model = _Model();
  final delegate = SelectionContainerDelegate();
  final root = owner.mountRoot(_scenario(model, delegate));
  var front = CellBuffer(_size);
  var back = CellBuffer(_size);

  void frame() {
    model.bump();
    back.withoutDamageTracking(back.clear);
    back.resetDamageTracking();
    owner.renderFrame(root, back);
    back.takeDamageBounds();
    back.takeDamageRows();
    renderer.renderDiff(front, back, sink);
    final tmp = front;
    front = back;
    back = tmp;
  }

  double timeFrames() {
    final sw = Stopwatch()..start();
    for (var i = 0; i < frames; i++) {
      frame();
    }
    sw.stop();
    return sw.elapsedMicroseconds / frames;
  }

  void selectAll() => delegate.dispatchSelectionEvent(
    const SelectionGranularEvent(granularity: SelectionGranularity.all),
  );

  // Settle layout + register every selectable, and warm both paths (with and
  // without a selection) so neither round owns cold code.
  for (var i = 0; i < warmup; i++) {
    frame();
  }
  selectAll();
  final selectedCells = delegate.getSelectedText().replaceAll('\n', '').length;
  for (var i = 0; i < warmup; i++) {
    frame();
  }
  delegate.clear();
  for (var i = 0; i < warmup; i++) {
    frame();
  }

  // Interleave base / active rounds and keep the MIN of each — the least-noise
  // estimate, cancelling scheduler drift between the two.
  var baseMin = double.infinity;
  var activeMin = double.infinity;
  for (var r = 0; r < rounds; r++) {
    delegate.clear();
    frame(); // settle no-selection
    final b = timeFrames();
    if (b < baseMin) baseMin = b;

    selectAll();
    frame(); // settle selection
    final a = timeFrames();
    if (a < activeMin) activeMin = a;
  }
  final addedPerFrame = activeMin - baseMin;

  if (selectedCells < _rows * 10) {
    stderr.writeln(
      'selection_gate: select-all covered only $selectedCells cells — the grid '
      'did not register as selectable (viewport too small, or a '
      'selection-registration regression).',
    );
    exitCode = 64;
    return;
  }

  if (update) {
    writeBaselineJson(baselinePath, {
      'selectedCells': selectedCells,
      'baseUsPerFrame': baseMin,
      'activeUsPerFrame': activeMin,
      'addedUsPerFrame': addedPerFrame,
      'frames': frames,
      'rounds': rounds,
    });
    stdout.writeln(
      'selection gate: wrote baseline $baselinePath '
      '($selectedCells cells covered; a held selection adds '
      '${addedPerFrame.toStringAsFixed(1)} µs/frame, warn-only).',
    );
    return;
  }

  stdout.writeln('active-selection over a repainting ${_rows}-row grid:');
  stdout.writeln('  select-all covers      $selectedCells cells   (gated)');
  stdout.writeln(
    '  base   (no selection)  ${baseMin.toStringAsFixed(1)} µs/frame',
  );
  stdout.writeln(
    '  active ($selectedCells cells)   ${activeMin.toStringAsFixed(1)} µs/frame',
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
  final baselineCells = (base['selectedCells'] as num).toInt();
  if (selectedCells != baselineCells) {
    stdout.writeln(
      'selection gate: select-all covers $selectedCells cells vs baseline '
      '$baselineCells — FAIL.',
    );
    stderr.writeln(
      'selection gate: the grid no longer registers as fully selectable. A '
      'default-on selection (DefaultRootSelection) or attachToSelection '
      'regression? If the fixture changed intentionally, re-baseline with '
      '--update-baseline.',
    );
    exitCode = 1;
    return;
  }
  final baselineAdded = (base['addedUsPerFrame'] as num).toDouble();
  stdout.writeln(
    'selection gate: coverage $selectedCells cells matches baseline — pass. '
    '(cost ${addedPerFrame.toStringAsFixed(1)} vs '
    '~${baselineAdded.toStringAsFixed(1)} µs/frame, warn-only.)',
  );
}
