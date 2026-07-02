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
    render
      ..rethrowContained =
          rethrowContained ?? owner.rethrowContainedRenderErrors
      ..onContained = onError ?? owner.onContainedRenderError
      // A contain/recover transition drops or restores the projected
      // semantic descendants — a structural change the retained-leaf
      // path can't express.
      ..onSemanticsStructureChanged =
          owner.semanticDirtyTracker.recordStructureDirty;
  }
}
