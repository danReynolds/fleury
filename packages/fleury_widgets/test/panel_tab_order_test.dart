// Tab through a scrolled form whose fields are grouped in Panels. A Panel's
// repaint boundary clips its content, so ordering by clip placed a
// scrolled-out field at the boundary's own off-screen origin and Tab went
// to Submit before the remaining fields. Tab order follows the content.
import 'package:fleury/fleury.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:fleury_widgets/fleury_widgets.dart';
import 'package:test/test.dart';

void main() {
  testWidgets('Tab visits every field of a form grouped in panels', (tester) {
    const size = CellSize(24, 7);
    final controller = ScrollController();
    addTearDown(controller.dispose);
    final fields = [for (var i = 0; i < 6; i++) FocusNode(debugLabel: 'f$i')];
    final submit = FocusNode(debugLabel: 'submit');
    for (final node in [...fields, submit]) {
      addTearDown(node.dispose);
    }
    tester.pumpWidget(
      FocusTraversalGroup(
        child: Column(
          children: [
            SizedBox(
              height: 5,
              child: ScrollView(
                controller: controller,
                child: Column(
                  children: [
                    for (var p = 0; p < 3; p++)
                      Panel(
                        title: 'Group $p',
                        expandChild: false,
                        child: Column(
                          children: [
                            for (var i = 2 * p; i < 2 * p + 2; i++)
                              TextInput(
                                focusNode: fields[i],
                                autofocus: i == 0,
                                placeholder: 'f$i',
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Focus(focusNode: submit, child: const Text('[ Submit ]')),
          ],
        ),
      ),
    );
    tester.render(size: size);

    final landed = <String>[];
    for (var i = 0; i < 6; i++) {
      tester.sendKey(const KeyEvent(KeyCode.tab));
      tester.render(size: size);
      landed.add(
        [...fields, submit].where((n) => n.hasFocus).single.debugLabel!,
      );
    }

    expect(landed, ['f1', 'f2', 'f3', 'f4', 'f5', 'submit']);
  });
}
