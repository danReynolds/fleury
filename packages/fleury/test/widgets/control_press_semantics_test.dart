// A semantic `activate` on a control is a press, as Enter or a click is: its
// result reports the press (declined, failed, or done), and nothing waits on
// the work the press starts. Waiting would stall on a press whose handler
// waits for a frame (a form's submit, whose validation runs after one) or for
// the dialog it opened: a test or an agent must answer that dialog, which it
// can't while its press has yet to return.
import 'dart:async';

import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

import '../support/harness.dart';

final class _Capture extends StatelessWidget {
  const _Capture(this.sink, this.child);

  final void Function(BuildContext context) sink;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    sink(context);
    return child;
  }
}

// A press that waits would hang; fail fast instead.
Future<SemanticActionInvocationResult> _press(
  FleuryTester tester,
  String label,
) => tester
    .invokeSemanticAction(
      SemanticAction.activate,
      role: SemanticRole.button,
      label: label,
    )
    .timeout(const Duration(seconds: 2));

void main() {
  testWidgets('a press does not wait on the work it starts', (tester) async {
    final never = Completer<void>();
    tester.pumpWidget(Button(text: 'Save', onPressed: () => never.future));

    final result = await _press(tester, 'Save');

    expect(result.status, SemanticActionInvocationStatus.completed);
  });

  testWidgets('a press that opens a dialog returns, so the dialog can be '
      'answered', (tester) async {
    late BuildContext home;
    bool? confirmed;
    tester.pumpWidget(
      Navigator(
        transition: RouteTransition.none,
        home: _Capture(
          (context) => home = context,
          Button(
            text: 'Delete',
            onPressed: () async {
              confirmed = await Navigator.of(home).present<bool>(
                Button(
                  text: 'Confirm',
                  onPressed: () => Navigator.of(home).pop(true),
                ),
                transition: RouteTransition.none,
              );
            },
          ),
        ),
      ),
    );

    final delete = await _press(tester, 'Delete');
    tester.pump();
    final confirm = await _press(tester, 'Confirm');
    tester.pump();
    await Future<void>.delayed(Duration.zero);

    expect(delete.status, SemanticActionInvocationStatus.completed);
    expect(confirm.status, SemanticActionInvocationStatus.completed);
    expect(confirmed, isTrue);
  });

  testWidgets('work that fails after the press reaches the zone', (
    tester,
  ) async {
    final errors = <Object>[];
    SemanticActionInvocationResult? result;
    await runZonedGuarded(() async {
      tester.pumpWidget(
        Button(
          text: 'Sync',
          onPressed: () async {
            await Future<void>.delayed(Duration.zero);
            throw StateError('offline');
          },
        ),
      );
      result = await _press(tester, 'Sync');
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }, (error, _) => errors.add(error));

    expect(result?.status, SemanticActionInvocationStatus.completed);
    expect(errors, [isA<StateError>()]);
  });

  testWidgets('a press that throws fails', (tester) async {
    tester.pumpWidget(
      Button(text: 'Sync', onPressed: () => throw StateError('offline')),
    );

    final result = await _press(tester, 'Sync');

    expect(result.status, SemanticActionInvocationStatus.failed);
    expect(result.error, isA<StateError>());
  });

  testWidgets('a press that declines is unsupported, and Enter ignores it', (
    tester,
  ) async {
    final errors = <Object>[];
    SemanticActionInvocationResult? result;
    await runZonedGuarded(() async {
      tester.pumpWidget(
        Button(
          text: 'Undo',
          autofocus: true,
          onPressed: () => throw const SemanticActionDeclined(),
        ),
      );
      result = await _press(tester, 'Undo');
      tester.sendKey(const KeyEvent(KeyCode.enter));
      await Future<void>.delayed(Duration.zero);
    }, (error, _) => errors.add(error));

    expect(result?.status, SemanticActionInvocationStatus.unsupported);
    expect(errors, isEmpty);
  });
}
