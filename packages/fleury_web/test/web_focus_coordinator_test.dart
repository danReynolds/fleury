import 'package:fleury/fleury_host.dart';
import 'package:fleury_web/src/focus/web_focus_coordinator.dart';
import 'package:test/test.dart';

void main() {
  test('WebFocusCoordinator tracks browser and Fleury focus state', () {
    final coordinator = WebFocusCoordinator();

    coordinator.handleBrowserFocusIn(WebFocusTarget.keyboardCapture);
    expect(coordinator.browserFocusTarget, WebFocusTarget.keyboardCapture);
    expect(coordinator.keyboardCaptureActive, isTrue);

    const semanticId = SemanticNodeId('command');
    coordinator.handleSemanticActivation(semanticId);
    expect(coordinator.activeSemanticNode, semanticId);
    expect(coordinator.browserFocusTarget, WebFocusTarget.semanticNode);
    expect(
      coordinator.shouldRestoreKeyboardCaptureAfterSemanticActivation(),
      isTrue,
    );

    final caretRect = CellRect.fromLTWH(2, 3, 1, 1);
    coordinator.syncFromFleuryFocus(
      WebFocusSnapshot(
        activeSemanticNode: semanticId,
        activeCaretRect: caretRect,
      ),
    );
    expect(coordinator.activeSemanticNode, semanticId);
    expect(coordinator.activeCaretRect, caretRect);

    coordinator.handleBrowserFocusOut(WebFocusTarget.semanticNode);
    expect(coordinator.browserFocusTarget, isNull);
  });

  test('WebFocusCoordinator can derive active node from a semantic tree', () {
    final coordinator = WebFocusCoordinator();
    const focusedId = SemanticNodeId('focused');
    final tree = SemanticTree(
      root: SemanticNode(
        id: const SemanticNodeId('root'),
        role: SemanticRole.app,
        children: [
          const SemanticNode(
            id: SemanticNodeId('other'),
            role: SemanticRole.button,
          ),
          const SemanticNode(
            id: focusedId,
            role: SemanticRole.textField,
            focused: true,
          ),
        ],
      ),
    );

    coordinator.syncFromSemanticTree(
      tree,
      activeCaretRect: CellRect.fromLTWH(1, 1, 1, 1),
    );

    expect(coordinator.activeSemanticNode, focusedId);
    expect(coordinator.activeCaretRect, CellRect.fromLTWH(1, 1, 1, 1));
  });

  test('WebFocusCoordinator clears stale semantic browser target', () {
    final coordinator = WebFocusCoordinator();

    coordinator.handleSemanticActivation(const SemanticNodeId('command'));
    expect(coordinator.browserFocusTarget, WebFocusTarget.semanticNode);

    coordinator.syncFromFleuryFocus(
      const WebFocusSnapshot(activeSemanticNode: null, activeCaretRect: null),
    );

    expect(coordinator.activeSemanticNode, isNull);
    expect(coordinator.browserFocusTarget, isNull);

    coordinator.handleBrowserFocusIn(WebFocusTarget.keyboardCapture);
    coordinator.syncFromFleuryFocus(
      const WebFocusSnapshot(activeSemanticNode: null, activeCaretRect: null),
    );

    expect(coordinator.browserFocusTarget, WebFocusTarget.keyboardCapture);
  });
}
