// ErrorBoundary: the widget face of layout/paint containment.
//
// Wrap a subtree whose layout or paint may fail on runtime data (a
// plugin panel, a chart over external input); a failure renders the
// red error presentation in the boundary's cells and the rest of the
// session keeps running. The framework installs implicit boundaries at
// Navigator route roots and OverlayEntry roots, so whole-screen crashes
// are already contained by default — explicit boundaries buy finer
// granularity.

import '../rendering/render_error_boundary.dart';
import '../rendering/render_object.dart';
import '../semantics/semantics.dart';
import 'framework.dart';
import 'focus.dart';
import 'pointer.dart';

export '../rendering/render_error_boundary.dart'
    show FrameContainmentError, FrameContainmentPhase;

/// Contains layout/paint exceptions thrown by [child].
class ErrorBoundary extends SingleChildRenderObjectWidget {
  const ErrorBoundary({
    super.key,
    super.child,
    this.onError,
    this.rethrowContained,
  });

  /// Observes each newly contained failure (once per error-state entry).
  /// Defaults to the runtime's [BuildOwner.onContainedRenderError] sink —
  /// the host's error reporter.
  final void Function(FrameContainmentError error)? onError;

  /// Overrides the owner-level containment policy for this boundary.
  /// Defaults to [BuildOwner.rethrowContainedRenderErrors] — false in
  /// production hosts (contain), true under FleuryTester (a widget test
  /// with a layout bug should fail the test, not render a red panel).
  final bool? rethrowContained;

  @override
  SingleChildRenderObjectElement createElement() => _ErrorBoundaryElement(this);

  @override
  RenderObject createRenderObject(BuildContext context) {
    final render = RenderErrorBoundary();
    _configure(context, render);
    return render;
  }

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    _configure(context, renderObject as RenderErrorBoundary);
  }

  void _configure(BuildContext context, RenderErrorBoundary render) {
    final owner = (context as Element).owner;
    // Both reads are dependencies. _ErrorBoundaryElement refreshes the bridge
    // from performRebuild, so inherited service swaps and global-key moves
    // transfer any active exclusion instead of leaving it in the old runtime.
    final focusManager = Focus.maybeOfIdentityDependency(context);
    final pointerRouter = PointerRouterScope.maybeOf(context);
    render
      ..rethrowContained =
          rethrowContained ?? owner.rethrowContainedRenderErrors
      ..onContained = onError ?? owner.onContainedRenderError
      // A contain/recover transition drops or restores the projected
      // semantic descendants — a structural change the retained-leaf
      // path can't express.
      ..onSemanticsStructureChanged =
          owner.semanticDirtyTracker.recordStructureDirty;
    render.updateInputContainmentBridge(
      elementToken: context,
      focusToken: focusManager,
      pointerToken: pointerRouter,
      onChanged: (excluded) {
        pointerRouter?.setSubtreeInputExcluded(render, excluded);
        focusManager?.setSubtreeInputExcluded(context, excluded);
      },
    );
  }
}

/// Refreshes the imperative containment bridge on dependency-only rebuilds.
///
/// The base render-object element updates render configuration only when its
/// widget instance changes; inherited notifications rebuild its child without
/// calling `updateRenderObject`. Input services are inherited, so this narrow
/// element hook keeps the bridge aligned with the element's current tree.
final class _ErrorBoundaryElement extends SingleChildRenderObjectElement {
  _ErrorBoundaryElement(ErrorBoundary super.widget);

  ErrorBoundary get _errorBoundaryWidget => widget as ErrorBoundary;
  RenderErrorBoundary get _errorBoundaryRenderObject =>
      renderObject as RenderErrorBoundary;

  void _refreshInputBridge() =>
      _errorBoundaryWidget._configure(this, _errorBoundaryRenderObject);

  void _clearInputBridge() =>
      _errorBoundaryRenderObject.clearInputContainmentBridge(this);

  @override
  void performRebuild() {
    _refreshInputBridge();
    super.performRebuild();
  }

  @override
  void deactivate() {
    _clearInputBridge();
    super.deactivate();
  }

  @override
  void activate() {
    super.activate();
    _refreshInputBridge();
  }

  @override
  void unmount() {
    _clearInputBridge();
    super.unmount();
  }
}
