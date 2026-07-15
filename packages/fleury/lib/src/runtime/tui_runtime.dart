import '../rendering/cell_buffer.dart';
import '../rendering/render_object.dart';
import '../semantics/semantics.dart';
import '../widgets/focus.dart';
import '../widgets/basic.dart' show ErrorWidget;
import '../widgets/framework.dart';
import '../widgets/pointer.dart';
import '../widgets/tui_binding.dart';

final class _CapturedRuntimeDisposeError {
  const _CapturedRuntimeDisposeError(this.error, this.stack);

  final Object error;
  final StackTrace stack;
}

final class _MultipleRuntimeDisposeErrors extends Error {
  _MultipleRuntimeDisposeErrors(this.errors);

  final List<_CapturedRuntimeDisposeError> errors;

  @override
  String toString() {
    final out = StringBuffer(
      'Multiple errors occurred while disposing TuiRuntime '
      '(${errors.length}):',
    );
    for (var i = 0; i < errors.length; i++) {
      out
        ..writeln()
        ..write('  ${i + 1}. ${errors[i].error}');
    }
    return out.toString();
  }
}

/// Shared framework-service owner for Fleury hosts.
///
/// Hosts still own platform concerns such as terminal setup, browser DOM
/// surfaces, input-source lifetimes, debug shells, and presentation. This
/// runtime owns the framework objects that native and browser hosts both need:
/// build owner, focus manager, binding, pointer router, and the mounted root
/// element lifecycle.
final class TuiRuntime {
  TuiRuntime({
    BuildOwner? owner,
    FocusManager? focusManager,
    TuiBinding? binding,
    PointerRouter? pointerRouter,
  }) : owner =
           owner ??
           BuildOwner(
             errorBuilder: (error, stack) => ErrorWidget.builder(error, stack),
           ),
       focusManager = focusManager ?? FocusManager(),
       binding = binding ?? TuiBinding(),
       pointerRouter = pointerRouter ?? PointerRouter();

  /// Owns element mounting, updates, frame rendering, and reassembly.
  final BuildOwner owner;

  /// Shared focus manager installed by host root scopes.
  final FocusManager focusManager;

  /// Shared binding for post-frame callbacks, ticker scheduling, and scopes.
  final TuiBinding binding;

  /// Pointer hit-test registry for the current frame.
  final PointerRouter pointerRouter;

  /// This runtime's frame damage signal (owned by [owner], attached at the
  /// root render object each frame). Hosts hand it to their [TuiFrameLoop]
  /// so presenter diff-bounds decisions consume this runtime's damage only.
  RenderDamageTracker get renderDamageTracker => owner.renderDamageTracker;

  /// Whether the next frame can produce output that differs from the last
  /// rendered frame.
  ///
  /// False means no element is waiting to rebuild and no render object has
  /// recorded an invalidation since the last frame: a frame request may skip
  /// build/layout/paint entirely (provided the host's buffer pool is warm —
  /// see `TuiFrameLoop.needsRender`).
  bool get hasFrameWork =>
      owner.hasScheduledBuilds || owner.renderDamageTracker.hasVisualChange;

  /// This runtime's semantic dirty tracker (owned per [BuildOwner]).
  ///
  /// Marks accumulate across frames until [SemanticDirtyTracker
  /// .takeDirtySnapshot] consumes them, so a deferred semantic presenter can
  /// coalesce multiple frames into one flush.
  SemanticDirtyTracker get semanticDirtyTracker => owner.semanticDirtyTracker;

  Element? _rootElement;
  var _disposed = false;

  /// The currently mounted root element, if any.
  Element? get rootElement => _rootElement;

  /// Mounts [root] as the runtime root.
  Element mountRoot(Widget root) {
    _ensureNotDisposed();
    if (_rootElement != null) {
      throw StateError('TuiRuntime already has a mounted root.');
    }
    try {
      return owner.mountRoot(root);
    } finally {
      // A failed initial mount rolls back through BuildOwner; mirror its
      // authoritative result so the host can safely attempt a fresh mount.
      _rootElement = owner.root;
    }
  }

  /// Replaces the mounted root widget and returns the current root element.
  Element updateRoot(Widget root) {
    _ensureNotDisposed();
    final current = _rootElement;
    if (current == null) {
      throw StateError('TuiRuntime has no mounted root.');
    }
    try {
      return owner.updateRoot(current, root);
    } finally {
      // Keep the host-facing pointer exactly aligned with BuildOwner even when
      // an incompatible old root throws from State.dispose during replacement.
      _rootElement = owner.root;
    }
  }

  /// Reassembles the mounted application after a hot reload.
  void reassembleApplication() {
    _ensureNotDisposed();
    owner.reassembleApplication();
  }

  /// Renders the mounted root into [buffer].
  void renderFrame(
    CellBuffer buffer, {
    void Function(Duration build, Duration layout, Duration paint)?
    onPhaseTiming,
    void Function(BuildFlushStats stats)? onBuildStats,
  }) {
    _ensureNotDisposed();
    final root = _rootElement;
    if (root == null) {
      throw StateError('TuiRuntime has no mounted root.');
    }
    pointerRouter.beginFrame();
    owner.renderFrame(
      root,
      buffer,
      onPhaseTiming: onPhaseTiming,
      onBuildStats: onBuildStats,
    );
  }

  /// Drains post-frame callbacks at the runtime clock's current time.
  void flushPostFrameCallbacks() {
    binding.flushPostFrameCallbacks(binding.tickerScheduler.clock.now);
  }

  /// Unmounts and disposes owned framework services.
  void dispose() {
    if (_disposed) return;
    _disposed = true;

    final errors = <_CapturedRuntimeDisposeError>[];
    void capture(void Function() action) {
      try {
        action();
      } catch (error, stack) {
        errors.add(_CapturedRuntimeDisposeError(error, stack));
      }
    }

    final root = _rootElement;
    try {
      if (root != null) capture(root.unmount);
    } finally {
      _rootElement = null;
    }
    // Subtrees deactivated but not yet finalized (a layout-time swap with no
    // frame after it) must still see State.dispose.
    capture(owner.drainInactiveElements);
    capture(pointerRouter.dispose);
    capture(focusManager.dispose);
    capture(binding.dispose);

    // Host callbacks commonly close over the session. A disposed runtime must
    // not keep that session reachable through its owner after the tree is gone.
    owner.onScheduleBuild = null;
    owner.onBuildError = null;
    owner.onContainedRenderError = null;

    if (errors.isEmpty) return;
    final first = errors.first;
    if (errors.length == 1) {
      Error.throwWithStackTrace(first.error, first.stack);
    }
    Error.throwWithStackTrace(
      _MultipleRuntimeDisposeErrors(
        List<_CapturedRuntimeDisposeError>.unmodifiable(errors),
      ),
      first.stack,
    );
  }

  void _ensureNotDisposed() {
    if (_disposed) throw StateError('TuiRuntime is disposed.');
  }
}
