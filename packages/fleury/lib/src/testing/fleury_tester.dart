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
import '../app/app.dart';
import '../app/commands.dart';
import '../foundation/geometry.dart';
import '../foundation/key.dart' show UniqueKey;
import '../rendering/cell.dart';
import '../rendering/cell_buffer.dart';
import '../rendering/surface_capabilities.dart';
import '../rendering/render_flex.dart' show RenderFlex;
import '../runtime/input_dispatcher.dart';
import '../semantics/accessibility.dart';
import '../semantics/inspection.dart';
import '../semantics/semantics.dart';
import '../input/events.dart';
import '../widgets/basic.dart';
import '../runtime/clipboard.dart';
import '../widgets/clipboard_scope.dart';
import '../widgets/focus.dart';
import '../widgets/framework.dart';
import '../widgets/media_query.dart';
import '../widgets/navigator.dart';
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
    this.colorMode = ColorMode.truecolor,
    this.glyphTier = GlyphTier.unicode,
    this.images = InlineImageSupport.none,
    Clipboard? clipboard,
  }) : clipboard = clipboard ?? InProcessClipboard(),
       _clock = FakeClock(),
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
    // Match the runtime: render an error panel for a thrown build()
    // rather than letting the exception escape the test harness. Per-owner,
    // so a test customizing hooks can't leak into the next test.
    _owner = BuildOwner(
      errorBuilder: (error, stack) => ErrorWidget.builder(error, stack),
    );
    // Containment inverts for tests: a layout/paint bug should FAIL the
    // test loudly, not render a red panel behind passing assertions. A
    // containment test opts back in per-boundary with
    // `ErrorBoundary(rethrowContained: false)`.
    _owner.rethrowContainedRenderErrors = true;
    // Off by default in tests so it doesn't perturb golden output; an
    // overflow-specific test opts back in.
    RenderFlex.debugShowOverflow = false;
  }

  /// The clipboard the tester installs via `ClipboardScope`. Defaults to a
  /// fresh [InProcessClipboard]; assert copies with
  /// `(tester.clipboard as InProcessClipboard).lastWritten` or pass a
  /// custom fake to the constructor.
  final Clipboard clipboard;

  /// Default size used by [render] / [renderToString] when no
  /// explicit size is given. Mutable so tests can grow / shrink the
  /// viewport mid-test:
  ///
  ///     tester.viewportSize = const CellSize(40, 10);
  CellSize viewportSize;

  /// Capability profile installed in the ambient [MediaQuery]. Tests set
  /// [glyphTier] to [GlyphTier.ascii] to exercise the ASCII drawing fallback,
  /// or [images] to [InlineImageSupport.placements] to exercise the
  /// true-pixel image path.
  ColorMode colorMode;
  GlyphTier glyphTier;
  InlineImageSupport images;

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

  /// Like [pumpWidget], but mounts [widget] as the `home` of a root
  /// [Navigator] — reproducing the runtime's root wrapper (`run_app.dart`),
  /// which always installs one. Use this for app-level tests so
  /// `context.present(...)` / `context.push(...)` and
  /// `TuiBinding.rootNavigator` resolve without hand-wrapping; use bare
  /// [pumpWidget] for widget-level tests. Mirrors Flutter's
  /// `pumpWidget(MyWidget())` vs `pumpWidget(MaterialApp(...))` split.
  ///
  /// Plain composition over [pumpWidget] — nothing latches: a later
  /// [pumpApp] REPLACES the whole app (fresh Navigator, fresh home; the
  /// Navigator is keyed because it snapshots `home` once and would silently
  /// ignore a swap), and a later [pumpWidget] mounts its widget bare.
  void pumpApp(Widget widget) {
    _assertNotDisposed('pumpApp');
    pumpWidget(Navigator(key: UniqueKey(), home: widget));
  }

  /// Advances time and flushes any pending rebuilds. When [duration]
  /// is null, just flushes — useful after dispatching an event that
  /// only mutates state.
  ///
  /// SYNCHRONOUS: `pump` never turns the event loop, so it cannot observe
  /// async work — a `StreamBuilder`/`QueryBuilder` whose first value arrives
  /// on a microtask/timer still shows its loading state after `pump()`. Reach
  /// for the async [settle] (or [pumpAndSettle] for animation-only trees) when
  /// a test binds to async data; don't hand-roll an `await Future.delayed` +
  /// `pump` loop.
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

  /// One settle step: advance the scheduler by [step], flush builds and
  /// post-frame callbacks, and report whether the tree did any *build* work.
  ///
  /// A step that rebuilds nothing is "quiescent" — no animation advanced a
  /// value and no pending `setState` remained. This is the test-side analog
  /// of Flutter's `hasScheduledFrame`: Fleury has no single scheduled-frame
  /// bool, but "did `flushBuild` rebuild anything this step" answers the same
  /// question. A perpetual-but-idle ticker (a 500 ms cursor blink) only
  /// rebuilds on the step that crosses its interval, so quiescence is reached
  /// in the gaps between its toggles — exactly as Flutter's `pumpAndSettle`
  /// returns *between* cursor blinks (a periodic-Timer blink leaves
  /// `hasScheduledFrame` false between fires). A second build flush is folded
  /// in so a post-frame callback that schedules a rebuild isn't read as idle.

  /// One settle step. [hasRendered] says whether a render already happened
  /// in this loop; returns `(quiescent, rendered)` so the caller threads the
  /// render state as a LOOP-LOCAL — sharing it as an instance field would let
  /// `pumpAndSettle` inherit a stale `true` from a prior `settle`/
  /// `pumpAndSettle` on the same tester and skip its own first render.
  (bool quiescent, bool rendered) _settleStep(
    Duration step, {
    required bool hasRendered,
  }) {
    if (step > Duration.zero) _scheduler.advance(step);
    final built = _owner.flushBuild().rebuiltElementCount;
    // Render a real layout+paint like a production frame — but only when it
    // can matter: the FIRST step (so widgets that build during layout, e.g.
    // LayoutBuilder subtrees, exist and their streams subscribe), and any
    // step that did build work (which is the only way a dirty LayoutBuilder
    // re-enters layout — its element marks BUILD, then relayouts). A
    // build-quiescent step after the first would render an unchanged tree,
    // so skipping it is free; a suite with hundreds of settle() calls saves
    // the wasted tail layouts+paints. Damage from paint-only tickers is
    // still consumed below whether or not we rendered.
    var rendered = false;
    if (_root != null && (!hasRendered || built > 0)) {
      render();
      rendered = true;
    }
    _binding.flushPostFrameCallbacks(_clock.now);
    final afterDrain = _owner.flushBuild().rebuiltElementCount;
    // Paint-only work counts as activity: a Ticker driving markNeedsPaintOnly
    // rebuilds nothing, but its animation is still in flight — treating the
    // tree as settled would abandon it mid-animation with the fake clock
    // stopped. The damage tracker records those audited paint invalidations;
    // consume it per step (the runtime's frame loop does the same). A
    // perpetual-but-idle ticker (cursor blink) stays settle-able: it records
    // damage only on the step that crosses its interval.
    final visualDamage = _owner.renderDamageTracker.takeVisualChange();
    return (built == 0 && afterDrain == 0 && !visualDamage, rendered);
  }

  /// Pumps in [step] increments until a frame does no build work (the tree
  /// has settled) or [timeout] elapses. Throws when [timeout] is hit while
  /// the tree still rebuilds every step.
  ///
  /// Mirrors `WidgetTester.pumpAndSettle`, and like it keys off "is another
  /// frame's worth of work pending" (here: did `flushBuild` rebuild anything)
  /// rather than "are any tickers registered" — so a focused `TextInput`'s
  /// perpetual cursor-blink ticker no longer hangs settle; it returns in the
  /// gaps between blinks. A genuinely *continuous* animation (one that
  /// rebuilds on every step) is what trips the timeout — pump a bounded
  /// duration for those instead of settling.
  ///
  /// NOTE: synchronous, so it cannot observe async work (stream/Future
  /// emissions). For data-bound widgets (`StreamBuilder`/`QueryBuilder`) use
  /// the async [settle].
  void pumpAndSettle({
    Duration step = const Duration(milliseconds: 16),
    Duration timeout = const Duration(seconds: 10),
  }) {
    _assertNotDisposed('pumpAndSettle');
    assert(
      step > Duration.zero,
      'pumpAndSettle needs a positive step; a zero step never advances the '
      'clock, so timeout is never reached.',
    );
    var elapsed = Duration.zero;
    var hasRendered = false;
    while (elapsed < timeout) {
      final (quiescent, rendered) = _settleStep(step, hasRendered: hasRendered);
      hasRendered = hasRendered || rendered;
      if (quiescent) return;
      elapsed += step;
    }
    throw StateError(
      'pumpAndSettle timed out after $timeout: the tree never reached a '
      'quiescent frame — something rebuilds on every step. '
      '${_scheduler.activeTickerCount} ticker(s) are active; if a continuous '
      'animation is intentional, pump a bounded duration instead of settling. '
      '(A perpetual-but-idle ticker such as a cursor blink does NOT cause '
      'this — settle returns in the gaps between its frames.)',
    );
  }

  /// The async analog of [pumpAndSettle] for data-bound widgets: yields to the
  /// real event loop between steps so pending microtasks, timers, and **stream
  /// emissions** land (a `StreamBuilder`/`QueryBuilder`'s first value arrives
  /// on a later event-loop turn), then flushes builds — repeating until a step
  /// does no build work or [timeout] is hit.
  ///
  /// This replaces the hand-rolled `for (i in 0..N) { await Future.delayed(d);
  /// pump(); }` loop every async test would otherwise need: synchronous [pump]
  /// can't observe async emissions because it never turns the event loop.
  ///
  /// Returns once the tree has been quiescent for [stableSteps] consecutive
  /// steps. Requiring a short run of idle steps (rather than returning on the
  /// first) guards the cold-start case: in-flight async work (a real DB query,
  /// an HTTP call) that hasn't produced its first rebuild yet gets a window to
  /// land and interrupt the idle streak — so `settle()` doesn't conclude
  /// "done" before the data arrives. Tune up for slower backends.
  ///
  /// Throws a [StateError] on timeout (the tree never settled) — the same
  /// signal as Flutter's `pumpAndSettle` timeout.
  Future<void> settle({
    Duration step = const Duration(milliseconds: 16),
    Duration timeout = const Duration(seconds: 5),
    int stableSteps = 4,
  }) async {
    _assertNotDisposed('settle');
    assert(
      step > Duration.zero,
      'settle needs a positive step; a zero step never advances the clock '
      '(nor elapsed), so timeout is never reached and the loop spins.',
    );
    var elapsed = Duration.zero;
    var steps = 0;
    var stable = 0;
    var hasRendered = false;
    while (elapsed < timeout) {
      // Turn the real event loop so async completions (stream/Future) run
      // their setState before we flush + test for quiescence.
      await Future<void>.delayed(step);
      final (quiescent, rendered) = _settleStep(step, hasRendered: hasRendered);
      hasRendered = hasRendered || rendered;
      stable = quiescent ? stable + 1 : 0;
      if (stable >= stableSteps) return;
      elapsed += step;
      steps++;
    }
    throw StateError(
      'settle() timed out after $timeout ($steps steps): the tree never '
      'reached $stableSteps consecutive quiescent frames. A stream that never '
      'stops emitting, or a continuous animation, will not settle — assert on '
      'a bounded pump instead. ${_scheduler.activeTickerCount} ticker(s) are '
      'active.',
    );
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
          case CellRole.overlay:
            // Overlay (inline-image) cells render as pixels via the
            // presenter, not text; the snapshot is text-only so we
            // treat them as emptyMark.
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

  /// Returns an immutable semantic snapshot for the current tree.
  ///
  /// This is collected on demand so early semantic work has no runtime cost
  /// unless tests or debug tools ask for it.
  SemanticTree semantics() {
    _assertNotDisposed('semantics');
    final root = _root;
    if (root == null) {
      throw StateError(
        'FleuryTester.semantics called before pumpWidget; the tree is empty.',
      );
    }
    _owner.flushBuild();
    return SemanticTree.fromElement(root);
  }

  /// Returns a text-first accessibility/fallback snapshot for the tree.
  ///
  /// The snapshot is derived from semantic nodes, so it preserves redaction,
  /// focus, selection, validation, capability fallback, progress, and action
  /// state without reading rendered cells.
  AccessibilitySnapshot accessibilitySnapshot() {
    _assertNotDisposed('accessibilitySnapshot');
    return semantics().toAccessibilitySnapshot();
  }

  /// Returns a machine-readable semantic inspection snapshot for the tree.
  ///
  /// The snapshot uses the same redaction-aware serializer as debug capture,
  /// making it useful for regression tests and future automation adapters
  /// without depending on rendered cells or debug-capture artifacts.
  SemanticInspectionSnapshot semanticInspectionSnapshot() {
    _assertNotDisposed('semanticInspectionSnapshot');
    return semantics().toInspectionSnapshot();
  }

  /// Returns [semanticInspectionSnapshot] as schema-versioned JSON.
  Map<String, Object?> semanticInspectionJson() {
    _assertNotDisposed('semanticInspectionJson');
    return semantics().toInspectionJson();
  }

  /// Returns a deterministic, redaction-aware semantic tree dump.
  ///
  /// Use this directly in failure messages or while authoring tests:
  ///
  /// ```dart
  /// print(tester.semanticTreeDebugString());
  /// ```
  String semanticTreeDebugString({bool includeState = true}) {
    _assertNotDisposed('semanticTreeDebugString');
    return semantics().debugTree(includeState: includeState);
  }

  /// Invokes a semantic action on a node in the current semantic tree.
  ///
  /// When [node] is omitted, the remaining filters must identify exactly one
  /// node that advertises [action]. This is intentionally semantic-first: tests
  /// can exercise app commands, controls, fields, and app-authored regions by
  /// role/label/action instead of reaching through widget internals.
  ///
  /// For [SemanticAction.setValue], pass the value to apply as [payload] (the
  /// [value] argument is a node *filter*, not the payload).
  Future<SemanticActionInvocationResult> invokeSemanticAction(
    SemanticAction action, {
    SemanticNode? node,
    SemanticNodeId? id,
    SemanticRole? role,
    String? label,
    Object? value,
    Object? payload,
    bool? focused,
    bool? selected,
    bool? enabled,
    bool? checked,
    bool? busy,
    String? validationError,
  }) async {
    _assertNotDisposed('invokeSemanticAction');
    final root = _root;
    if (root == null) {
      return SemanticActionInvocationResult.notFound(action);
    }

    final tree = semantics();
    final target = _resolveSemanticActionTarget(
      tree,
      action,
      node: node,
      id: id,
      role: role,
      label: label,
      value: value,
      focused: focused,
      selected: selected,
      enabled: enabled,
      checked: checked,
      busy: busy,
      validationError: validationError,
    );
    if (target == null) {
      return SemanticActionInvocationResult.notFound(action);
    }
    if (!target.enabled) {
      return SemanticActionInvocationResult.disabled(target, action);
    }
    if (!target.actions.contains(action)) {
      return SemanticActionInvocationResult.unsupported(target, action);
    }

    // Dispatch through the same map-based path the live wire uses, so the tester
    // can't pass where production fails (the divergence that previously hid a
    // cross-fire bug). The tree from `semantics()` carries the id→element map.
    final result = await invokeSemanticActionFromElement(
      tree: tree,
      id: target.id,
      action: action,
      value: payload,
    );
    _owner.flushBuild();
    return result;
  }

  /// Returns the active command registry for [context], or for the current
  /// focus/default test context when [context] is omitted.
  CommandRegistry commandRegistry({BuildContext? context}) {
    _assertNotDisposed('commandRegistry');
    final buildContext = _defaultCommandContext(context);
    final registry = buildContext == null
        ? null
        : CommandRegistryScope.maybeOf(buildContext);
    if (registry == null) {
      throw StateError(
        'FleuryTester.commandRegistry could not locate a CommandRegistryScope '
        'in the current tree.',
      );
    }
    return registry;
  }

  /// Latest command invocation result for the active command registry, if any.
  CommandInvocationResult? get lastCommandResult {
    _assertNotDisposed('lastCommandResult');
    final buildContext = _defaultCommandContext(null);
    if (buildContext == null) return null;
    return FleuryApp.maybeOf(buildContext)?.commands.lastResult ??
        CommandRegistryScope.maybeOf(buildContext)?.lastResult;
  }

  /// Invokes a command by stable ID and flushes builds triggered by it.
  ///
  /// Resolution follows app-shell expectations: nearest local command scopes
  /// win first, then active screen commands, then app/parent commands.
  Future<CommandInvocationResult> invokeCommand(
    CommandId id, {
    BuildContext? context,
  }) async {
    _assertNotDisposed('invokeCommand');
    final buildContext = _defaultCommandContext(context);
    final registry = commandRegistry(context: buildContext);
    final resolution = _resolveCommandForTester(id, registry, buildContext);
    final result = resolution == null
        ? await registry.invoke(id, buildContext: buildContext)
        : await resolution.registry.invokeCommand(
            resolution.command,
            buildContext: buildContext,
          );
    _owner.flushBuild();
    return result;
  }

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
    // A layout-time swap in the final pump can leave deactivated subtrees
    // unfinalized; drain so their State.dispose runs and cannot leak
    // timers/subscriptions into the next test.
    _owner.drainInactiveElements();
    _binding.dispose();
    _focusManager.dispose();
  }

  Widget _wrap() {
    return TuiBindingScope(
      binding: _binding,
      child: MediaQuery(
        data: MediaQueryData(
          size: viewportSize,
          capabilities: SurfaceCapabilities(
            colorMode: colorMode,
            glyphTier: glyphTier,
            images: images,
          ),
        ),
        child: FocusManagerScope(
          manager: _focusManager,
          child: PointerRouterScope(
            router: _pointerRouter,
            child: ClipboardScope(
              clipboard: clipboard,
              child: Overlay(initialEntries: [_userEntry]),
            ),
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

  BuildContext? _defaultCommandContext(BuildContext? explicit) {
    if (explicit != null) return explicit;
    final focused = _focusManager.focusedNode?.context;
    if (focused != null && focused.mounted) return focused;
    final root = _root;
    if (root == null) return null;
    Element? deepest;
    void visit(Element element) {
      if (!element.mounted) return;
      deepest = element;
      element.visitChildren(visit);
    }

    visit(root);
    return deepest;
  }

  _CommandResolution? _resolveCommandForTester(
    CommandId id,
    CommandRegistry registry,
    BuildContext? buildContext,
  ) {
    final app = buildContext == null ? null : FleuryApp.maybeOf(buildContext);
    final local = _localCommand(registry, id, buildContext);
    if (local != null && !identical(registry, app?.commands)) {
      return _CommandResolution(local, registry);
    }

    final command = registry.command(id, buildContext: buildContext);
    if (command == null) return null;
    final appCommands = app?.commands;
    if (appCommands != null && _ownsCommand(appCommands, command)) {
      return _CommandResolution(command, appCommands);
    }
    return _CommandResolution(command, registry);
  }

  bool _ownsCommand(CommandRegistry registry, AppCommand command) {
    for (final local in registry.localCommands) {
      if (identical(local, command)) return true;
    }
    return false;
  }

  AppCommand? _localCommand(
    CommandRegistry registry,
    CommandId id,
    BuildContext? buildContext,
  ) {
    for (final command in registry.localCommands) {
      if (command.id != id) continue;
      if (!registry.isVisible(command, buildContext: buildContext)) continue;
      return command;
    }
    return null;
  }

  SemanticNode? _resolveSemanticActionTarget(
    SemanticTree tree,
    SemanticAction action, {
    SemanticNode? node,
    SemanticNodeId? id,
    SemanticRole? role,
    String? label,
    Object? value,
    bool? focused,
    bool? selected,
    bool? enabled,
    bool? checked,
    bool? busy,
    String? validationError,
  }) {
    if (node != null) {
      for (final current in tree.nodes) {
        if (current.id == node.id) return current;
      }
      return null;
    }
    try {
      return tree.single(
        id: id,
        role: role,
        label: label,
        value: value,
        action: action,
        focused: focused,
        selected: selected,
        enabled: enabled,
        checked: checked,
        busy: busy,
        validationError: validationError,
      );
    } on StateError {
      return null;
    }
  }
}

final class _CommandResolution {
  const _CommandResolution(this.command, this.registry);

  final AppCommand command;
  final CommandRegistry registry;
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
  ColorMode colorMode = ColorMode.truecolor,
  GlyphTier glyphTier = GlyphTier.unicode,
  InlineImageSupport images = InlineImageSupport.none,
  pkg_test.Timeout? timeout,
  Object? skip,
}) {
  pkg_test.test(
    description,
    () async {
      final tester = FleuryTester(
        animationPolicy: animationPolicy,
        viewportSize: viewportSize,
        colorMode: colorMode,
        glyphTier: glyphTier,
        images: images,
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
