// Observational probes for the Testing guide DX review; these describe the
// current contract rather than locking undesirable behavior into unit tests.
import 'dart:async';
import 'dart:convert';

import 'package:fleury/fleury.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:fleury_widgets/fleury_widgets.dart';

Future<void> main() async {
  final result = <String, Object?>{};

  final layout = FleuryTester();
  try {
    layout.pumpWidget(LayoutBuilder(builder: (_, _) => const Text('Ready')));
    result['afterMount'] = layout.exists(text('Ready'));
    layout.pump();
    result['afterPump'] = layout.exists(text('Ready'));
    layout.render();
    result['afterRender'] = layout.exists(text('Ready'));
    layout.pumpWidget(LayoutBuilder(
      builder: (context, constraints) => Text(
        'layout=${constraints.maxCols}; media=${MediaQuery.sizeOf(context).cols}',
      ),
    ));
    result['renderSizeOverride'] = layout
        .renderToString(size: const CellSize(40, 3), emptyMark: ' ')
        .trim();
  } finally {
    layout.dispose();
  }

  final actions = FleuryTester();
  try {
    actions.pumpWidget(Column(children: [
      Button(label: 'Save', onPressed: () {}),
      Button(label: 'Save', onPressed: () {}),
      const Button(label: 'Disabled', onPressed: null),
    ]));
    actions.render();
    for (final label in ['Missing', 'Save', 'Disabled']) {
      result['action:$label'] = (await actions.invokeSemanticAction(
        SemanticAction.activate,
        role: SemanticRole.button,
        label: label,
        allowFailure: true,
      )).status.name;
    }
    try {
      actions.semantics().single(role: SemanticRole.button, label: 'Missing');
    } catch (error) {
      result['missingQueryDiagnostic'] = error.toString();
    }
  } finally {
    actions.dispose();
  }

  final async = FleuryTester();
  try {
    final pending = Completer<String>();
    async.pumpWidget(FutureBuilder<String>(
      future: pending.future,
      builder: (_, snapshot) => Text(snapshot.data ?? 'Waiting'),
    ));
    await async.settle(
      step: const Duration(milliseconds: 1),
      stableSteps: 2,
    );
    result['settledWithUnfinishedFuture'] = async.exists(text('Waiting'));
    result['requestCompleted'] = pending.isCompleted;
    pending.complete('Done');
    await async.settle(step: const Duration(milliseconds: 1), stableSteps: 2);
    result['afterControlledCompletion'] = async.exists(text('Done'));
  } finally {
    async.dispose();
  }

  print(const JsonEncoder.withIndent('  ').convert(result));
}
