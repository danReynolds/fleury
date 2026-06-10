import '../rendering/cell_buffer.dart';
import '../rendering/render_object.dart';
import '../semantics/semantics.dart';
import '../widgets/focus.dart';
import '../widgets/framework.dart';
import '../widgets/pointer.dart';
import '../widgets/tui_binding.dart';

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
  }) : owner = owner ?? BuildOwner(),
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
    return _rootElement = owner.mountRoot(root);
  }

  /// Replaces the mounted root widget and returns the current root element.
  Element updateRoot(Widget root) {
    _ensureNotDisposed();
    final current = _rootElement;
    if (current == null) {
      throw StateError('TuiRuntime has no mounted root.');
    }
    return _rootElement = owner.updateRoot(current, root);
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
    _rootElement?.unmount();
    _rootElement = null;
    focusManager.dispose();
    binding.dispose();
  }

  void _ensureNotDisposed() {
    if (_disposed) throw StateError('TuiRuntime is disposed.');
  }
}
