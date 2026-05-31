// FleuryTester: the WidgetTester analog for fleury. Bundles the
// per-test framework setup (binding, scheduler, focus manager,
// input dispatcher, build owner) behind a small surface focused on
// the operations every test actually wants:
//
//   - pumpWidget(w)          mount or replace the user widget
//   - pump([duration])       advance scheduler + flush builds
//   - pumpAndSettle(...)     pump until no active tickers
//   - find(finder)           apply a Finder to the tree
//   - findOne(finder)        single-element variant with helpful errors
//   - sendKey(KeyEvent)      dispatch a key event
//   - type(text)             dispatch a TextInputEvent
//   - render(...)            produce a CellBuffer for inspection
//   - renderToString(...)    convenience: render then stringify
//
// Tests use it via the testWidgets() wrapper:
//
//     testWidgets('autofocus claims focus', (tester) {
//       tester.pumpWidget(TextInput(autofocus: true));
//       expect(tester.find(byType(TextInput)), hasLength(1));
//     });
//
// The tester is FakeClock-driven; SchedulerScheduler is the test
// variant. Real wallclock is never read by the tester itself —
// pump(duration) advances time in fixed deltas under the caller's
// control. Mirrors the discipline already established in the
// animation suite.

import 'dart:async';

// ignore_for_file: depend_on_referenced_packages
// The `test` package will become a first-party dep once we split
// into a dedicated fleury_test package; today it's reachable
// transitively from the dev_dependencies block.

import 'package:meta/meta.dart';
import 'package:test/test.dart' as pkg_test;

import '../animation/animation_policy.dart';
import '../animation/clock.dart';
import '../animation/ticker_scheduler.dart';
import '../foundation/geometry.dart';
import '../rendering/cell.dart';
import '../rendering/cell_buffer.dart';
import '../rendering/render_flex.dart' show RenderFlex;
import '../runtime/input_dispatcher.dart';
import '../terminal/events.dart';
import '../widgets/basic.dart';
import '../widgets/focus.dart';
import '../widgets/framework.dart';
import '../widgets/media_query.dart';
import '../widgets/overlay.dart';
import '../widgets/pointer.dart';
import '../widgets/tui_binding.dart';
import 'finders.dart';

/// Drives a widget tree under test. One tester corresponds to one
/// `testWidgets` invocation.
class FleuryTester {
  /// Constructs a tester with fresh, isolated framework pieces.
  /// Tests typically don't call this directly — use [testWidgets].
  FleuryTester({
    AnimationPolicy animationPolicy = AnimationPolicy.enabled,
    this.viewportSize = const CellSize(80, 24),
  }) : _clock = FakeClock(),
       _focusManager = FocusManager() {
    _scheduler = FakeTickerScheduler(clock: _clock);
    _binding = TuiBinding(
      tickerScheduler: _scheduler,
      animationPolicy: animationPolicy,
    );
    _dispatcher = InputDispatcher(
      focusManager: _focusManager,
      pointerRouter: _pointerRouter,
    );
    _owner = BuildOwner();
    // Match the runtime: render an error panel for a thrown build()
    // rather than letting the exception escape the test harness.
    Element.errorBuilder ??= (error, stack) =>
        ErrorWidget.builder(error, stack);
    // Off by default in tests so it doesn't perturb golden output; an
    // overflow-specific test opts back in.
    RenderFlex.debugShowOverflow = false;
  }

  /// Default size used by [render] / [renderToString] when no
  /// explicit size is given. Mutable so tests can grow / shrink the
  /// viewport mid-test:
  ///
  ///     tester.viewportSize = const CellSize(40, 10);
  CellSize viewportSize;
  final FakeClock _clock;
  late final FakeTickerScheduler _scheduler;
  late final TuiBinding _binding;
  final FocusManager _focusManager;
  final PointerRouter _pointerRouter = PointerRouter();
  late final InputDispatcher _dispatcher;
  late final BuildOwner _owner;
  Element? _root;
  Widget _currentUserWidget = const EmptyBox();
  late final OverlayEntry _userEntry = OverlayEntry(
    builder: (_) => _currentUserWidget,
  );
  bool _disposed = false;

  /// The binding installed above the test tree. Exposed so tests can
  /// override animation policy mid-flight or read out scheduler
  /// state.
  TuiBinding get binding => _binding;

  /// FakeClock-backed scheduler driving every Ticker / FrameTicker
  /// in the test tree.
  FakeTickerScheduler get scheduler => _scheduler;

  /// Monotonic clock shared by [scheduler] and any other timing
  /// primitive that reads from a [Clock]. Advanced implicitly by
  /// [pump]; tests can also advance directly for fine-grained
  /// control.
  FakeClock get clock => _clock;

  /// The focus manager wired into [pumpWidget]'s wrapping
  /// [FocusManagerScope]. Tests that need to assert focused-node
  /// identity reach in via this getter.
  FocusManager get focusManager => _focusManager;

  /// Input dispatcher driven by [sendKey] / [type]. Tests sending
  /// non-key events (e.g. ResizeEvent) can dispatch directly via
  /// this object.
  InputDispatcher get dispatcher => _dispatcher;

  /// The [BuildOwner] managing the test tree. Exposed for advanced
  /// scenarios (e.g. asserting dirty-element queue length).
  BuildOwner get owner => _owner;

  /// The mounted root element, or null before the first [pumpWidget].
  Element? get root => _root;

  /// The [OverlayState] of the tester's wrapping Overlay. Useful for
  /// assertions on overlay entry count when a test exercises
  /// `OverlayEntry.insert` directly. Throws when called before the first
  /// [pumpWidget].
  OverlayState get overlay {
    final root = _root;
    if (root == null) {
      throw StateError(
        'FleuryTester.overlay accessed before pumpWidget; the tree is empty.',
      );
    }
    OverlayState? found;
    void visit(Element e) {
      if (found != null) return;
      if (e is StatefulElement && e.state is OverlayState) {
        found = e.state as OverlayState;
        return;
      }
      e.visitChildren(visit);
    }

    visit(root);
    if (found == null) {
      throw StateError(
        'FleuryTester.overlay could not locate an OverlayState in the '
        'tree — the wrapper should have installed one.',
      );
    }
    return found!;
  }

  /// Mounts [widget] as the root of the test tree (wrapped in the
  /// canonical [TuiBindingScope] + [FocusManagerScope] + [Overlay]
  /// chrome). On subsequent calls, swaps the user widget in place
  /// while preserving the binding / focus manager / overlay state —
  /// this matches `WidgetTester.pumpWidget` semantics, where state
  /// keyed by the wrappers (e.g. focused node identity) survives
  /// across re-pumps.
  void pumpWidget(Widget widget) {
    _assertNotDisposed('pumpWidget');
    _currentUserWidget = widget;
    if (_root == null) {
      _root = _owner.mountRoot(_wrap());
    } else {
      // Stable wrappers + a stable OverlayEntry whose builder reads
      // _currentUserWidget on each rebuild. markNeedsBuild reaches
      // exactly the entry's subtree without disturbing the binding
      // / focus / overlay state above.
      _userEntry.markNeedsBuild();
      _owner.flushBuild();
    }
  }

  /// Advances time and flushes any pending rebuilds. When [duration]
  /// is null, just flushes — useful after dispatching an event that
  /// only mutates state.
  ///
  /// Time is moved by stepping the scheduler at every
  /// `scheduler.frameInterval` boundary across [duration], firing
  /// each registered Ticker / FrameTicker at each step (the same
  /// cadence a real-world `Timer.periodic` would). A `pump(300 ms)`
  /// at the default 33 ms cadence therefore delivers ~9 ticks, so
  /// FrameTicker-driven widgets (typewriters, spinners, marquees)
  /// advance the correct number of frames for the elapsed time —
  /// rather than catching up just one frame regardless of duration.
  /// Animations compute their value from absolute elapsed
  /// time so this change is invisible to them.
  ///
  /// Use `tester.scheduler.advance(d)` directly if you need the
  /// low-level single-tick semantics (e.g. asserting one specific
  /// frame emit).
  ///
  /// Layout divergence from production: `pump` only flushes builds
  /// before draining post-frame callbacks, not layout. In a real
  /// runtime, `renderFrame` lays out + paints before draining, so a
  /// post-frame callback that reads `context.findRenderObject()?.size`
  /// sees the freshly-painted geometry. In tests, call [render] (or
  /// [renderToString]) before [pump] when a queued post-frame callback
  /// needs accurate geometry — otherwise the lookup returns null or
  /// stale dimensions.
  void pump([Duration? duration]) {
    _assertNotDisposed('pump');
    if (duration != null && duration > Duration.zero) {
      final step = _scheduler.frameInterval;
      var remaining = duration;
      while (remaining > step) {
        _scheduler.advance(step);
        remaining -= step;
      }
      if (remaining > Duration.zero) {
        _scheduler.advance(remaining);
      }
    }
    _owner.flushBuild();
    // Mirrors the runtime's drain order: build flush first, then
    // post-frame callbacks see the up-to-date tree. Drain is a no-op
    // when no callbacks are queued — idle pumps stay free.
    _binding.flushPostFrameCallbacks(_clock.now);
  }

  /// Pumps in [step] increments until no tickers are active (the
  /// usual proxy for "no further animation work to do") or [timeout]
  /// elapses. Throws when [timeout] is hit with tickers still active.
  ///
  /// Mirrors `WidgetTester.pumpAndSettle` for animation tests where
  /// the precise frame count doesn't matter and you want to read the
  /// final state.
  void pumpAndSettle({
    Duration step = const Duration(milliseconds: 16),
    Duration timeout = const Duration(seconds: 10),
  }) {
    _assertNotDisposed('pumpAndSettle');
    var elapsed = Duration.zero;
    while (_scheduler.activeTickerCount > 0 && elapsed < timeout) {
      pump(step);
      elapsed += step;
    }
    if (_scheduler.activeTickerCount > 0) {
      throw StateError(
        'pumpAndSettle timed out after $timeout with '
        '${_scheduler.activeTickerCount} active ticker(s) still running.',
      );
    }
  }

  /// Applies [finder] to the current tree, returning every match
  /// as a list. Throws if [pumpWidget] hasn't been called yet.
  List<Element> find(Finder finder) {
    _assertNotDisposed('find');
    final root = _root;
    if (root == null) {
      throw StateError(
        'FleuryTester.find called before pumpWidget; the tree is empty.',
      );
    }
    return finder.apply(root).toList(growable: false);
  }

  /// Like [find] but asserts exactly one match and returns it. On
  /// zero or multiple matches, throws a [pkg_test.TestFailure] with
  /// a dump of the current tree.
  Element findOne(Finder finder) {
    final matches = find(finder);
    if (matches.length == 1) return matches.single;
    final msg = StringBuffer()
      ..write('Expected exactly one element matching ${finder.describe()}, ')
      ..writeln('found ${matches.length}.');
    if (matches.isNotEmpty) {
      msg.writeln('Matches:');
      for (final m in matches) {
        msg.write('  ');
        msg.writeln(m.toStringShallow());
      }
    }
    msg
      ..writeln('Current tree:')
      ..write(_root?.toStringDeep('  ') ?? '  (no root)');
    throw pkg_test.TestFailure(msg.toString());
  }

  /// Returns true when [finder] matches at least one element.
  bool exists(Finder finder) => find(finder).isNotEmpty;

  /// Dispatches [event] through the input dispatcher and flushes any
  /// builds it triggered. Use for special chords (arrows, escape,
  /// ctrl-shortcuts).
  void sendKey(KeyEvent event) {
    _assertNotDisposed('sendKey');
    _dispatcher.dispatch(event);
    _owner.flushBuild();
  }

  /// Dispatches one or more graphemes of typed text through the
  /// input dispatcher. Equivalent to a `TextInputEvent(text)`.
  void type(String text) {
    _assertNotDisposed('type');
    _dispatcher.dispatch(TextInputEvent(text));
    _owner.flushBuild();
  }

  /// Dispatches a bracketed [PasteEvent] — the whole blob at once, as a
  /// real paste arrives (so embedded newlines don't act as Enter).
  void paste(String text) {
    _assertNotDisposed('paste');
    _dispatcher.dispatch(PasteEvent(text));
    _owner.flushBuild();
  }

  /// Dispatches a [MouseEvent] (e.g. a left-button click for
  /// click-to-focus). Render first so focus rects are recorded.
  void sendMouse(MouseEvent event) {
    _assertNotDisposed('sendMouse');
    _dispatcher.dispatch(event);
    _owner.flushBuild();
  }

  /// Renders the current tree into a fresh [CellBuffer] sized to
  /// [size] (defaulting to [viewportSize]).
  CellBuffer render({CellSize? size}) {
    _assertNotDisposed('render');
    final root = _root;
    if (root == null) {
      throw StateError(
        'FleuryTester.render called before pumpWidget; the tree is empty.',
      );
    }
    final buffer = CellBuffer(size ?? viewportSize);
    _pointerRouter.beginFrame();
    _owner.renderFrame(root, buffer);
    return buffer;
  }

  /// Renders the current tree and stringifies the buffer with one
  /// row per line. Leading cells write their grapheme, continuation
  /// cells contribute nothing (their leading cell handles them), and
  /// empty cells are rendered with [emptyMark] (default `·` for
  /// visibility against runs of whitespace).
  ///
  /// Trailing empty cells on a row are trimmed for readability.
  String renderToString({CellSize? size, String emptyMark = '·'}) {
    final buffer = render(size: size);
    final out = StringBuffer();
    for (var row = 0; row < buffer.size.rows; row++) {
      final line = StringBuffer();
      for (var col = 0; col < buffer.size.cols; col++) {
        final cell = buffer.atColRow(col, row);
        switch (cell.role) {
          case CellRole.empty:
            line.write(emptyMark);
          case CellRole.leading:
            line.write(cell.grapheme);
          case CellRole.continuation:
          case CellRole.protocolAnchor:
          case CellRole.protocolCovered:
            // Protocol cells render in the terminal via raw escape
            // bytes that have no string representation in the cell
            // grid; the snapshot is text-only so we treat them as
            // emptyMark.
            break;
        }
      }
      out.writeln(_rstrip(line.toString(), emptyMark));
    }
    return out.toString();
  }

  /// Multi-line dump of the current element tree. Useful in test
  /// failure messages and ad-hoc debugging.
  String describeTree() =>
      _root?.toStringDeep() ?? '(tester has no root; call pumpWidget first)';

  /// Tears down the test fixtures. Called automatically by
  /// [testWidgets]; tests that construct an [FleuryTester] manually
  /// must call this in their test teardown.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    final root = _root;
    if (root != null && root.mounted) {
      root.unmount();
    }
    _root = null;
    _binding.dispose();
    _focusManager.dispose();
  }

  Widget _wrap() {
    return TuiBindingScope(
      binding: _binding,
      child: MediaQuery(
        data: MediaQueryData(size: viewportSize),
        child: FocusManagerScope(
          manager: _focusManager,
          child: PointerRouterScope(
            router: _pointerRouter,
            child: Overlay(initialEntries: [_userEntry]),
          ),
        ),
      ),
    );
  }

  void _assertNotDisposed(String op) {
    if (_disposed) {
      throw StateError(
        'FleuryTester.$op() called after dispose(). Create a new tester '
        'for each test or use the testWidgets() wrapper.',
      );
    }
  }
}

String _rstrip(String s, String mark) {
  var end = s.length;
  while (end > 0 && s.substring(end - mark.length, end) == mark) {
    end -= mark.length;
  }
  return s.substring(0, end);
}

/// Registers a `package:test` test that runs [body] with a freshly-
/// constructed [FleuryTester]. The tester is disposed in `finally`,
/// even on exception.
///
/// Animation policy and viewport size default to "real-app" values.
/// Both can be overridden per-test:
///
///     testWidgets('snaps to end when policy is disabled', (t) {
///       ...
///     }, animationPolicy: AnimationPolicy.disabled);
@isTest
void testWidgets(
  String description,
  FutureOr<void> Function(FleuryTester tester) body, {
  AnimationPolicy animationPolicy = AnimationPolicy.enabled,
  CellSize viewportSize = const CellSize(80, 24),
  pkg_test.Timeout? timeout,
  Object? skip,
}) {
  pkg_test.test(
    description,
    () async {
      final tester = FleuryTester(
        animationPolicy: animationPolicy,
        viewportSize: viewportSize,
      );
      try {
        await body(tester);
      } finally {
        tester.dispose();
      }
    },
    timeout: timeout,
    skip: skip,
  );
}
