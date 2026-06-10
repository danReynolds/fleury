import 'package:fleury/fleury_host.dart';

/// Browser focus ownership target known to the retained DOM host.
enum WebFocusTarget { host, visualSurface, keyboardCapture, semanticNode }

/// Current Fleury focus projection into the browser host.
final class WebFocusSnapshot {
  const WebFocusSnapshot({
    required this.activeSemanticNode,
    required this.activeCaretRect,
  });

  final SemanticNodeId? activeSemanticNode;
  final CellRect? activeCaretRect;
}

/// Coordinates browser, Fleury, and semantic-DOM focus state.
///
/// Fleury focus remains the source of truth for app behavior. This coordinator
/// records how that focus projects into browser-owned targets so the host can
/// keep keyboard/IME capture on the hidden textarea while still reflecting
/// semantic activation for assistive technology.
final class WebFocusCoordinator {
  SemanticNodeId? _activeSemanticNode;
  CellRect? _activeCaretRect;
  WebFocusTarget? _browserFocusTarget;

  SemanticNodeId? get activeSemanticNode => _activeSemanticNode;
  CellRect? get activeCaretRect => _activeCaretRect;
  WebFocusTarget? get browserFocusTarget => _browserFocusTarget;

  bool get keyboardCaptureActive =>
      _browserFocusTarget == WebFocusTarget.keyboardCapture;

  void handleBrowserFocusIn(WebFocusTarget target) {
    _browserFocusTarget = target;
  }

  void handleBrowserFocusOut(WebFocusTarget target) {
    if (_browserFocusTarget == target) _browserFocusTarget = null;
  }

  void handleSemanticActivation(SemanticNodeId id) {
    _activeSemanticNode = id;
    _browserFocusTarget = WebFocusTarget.semanticNode;
  }

  void syncFromFleuryFocus(WebFocusSnapshot snapshot) {
    _activeSemanticNode = snapshot.activeSemanticNode;
    _activeCaretRect = snapshot.activeCaretRect;
    if (_activeSemanticNode == null &&
        _browserFocusTarget == WebFocusTarget.semanticNode) {
      _browserFocusTarget = null;
    }
  }

  void syncFromSemanticTree(
    SemanticTree tree, {
    required CellRect? activeCaretRect,
  }) {
    syncFromFleuryFocus(
      WebFocusSnapshot(
        activeSemanticNode: _focusedNodeId(tree),
        activeCaretRect: activeCaretRect,
      ),
    );
  }

  bool shouldRestoreKeyboardCaptureAfterSemanticActivation() => true;
}

SemanticNodeId? _focusedNodeId(SemanticTree tree) {
  for (final node in tree.nodes) {
    if (node.focused) return node.id;
  }
  return null;
}
