import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_test.dart';
import 'package:test/test.dart';

void main() {
  test(
    'semantic inspection snapshot is queryable, redacted, and JSON-safe',
    () {
      final tree = SemanticTree(
        root: SemanticNode(
          id: const SemanticNodeId('root'),
          role: SemanticRole.app,
          children: [
            const SemanticNode(
              id: SemanticNodeId('field:api-key'),
              role: SemanticRole.textField,
              label: 'API key\x1b]52;c;secret-token\x07',
              value: 'secret-token',
              focused: true,
              validationError: 'secret-token rejected',
              actions: {SemanticAction.submit, SemanticAction.copy},
              state: SemanticState({
                'redactedValue': true,
                'text': 'secret-token',
                'apiToken': 'secret-token',
                'historyCount': 2,
              }),
            ),
            const SemanticNode(
              id: SemanticNodeId('button:save'),
              role: SemanticRole.button,
              label: 'Save',
              actions: {SemanticAction.activate},
            ),
          ],
        ),
      );

      final snapshot = tree.toInspectionSnapshot();
      final json = snapshot.toJson();

      expect(snapshot.schemaVersion, 1);
      expect(snapshot.nodeCount, 3);
      expect(snapshot.focusedNodeId, 'field:api-key');
      expect(snapshot.roleCounts, containsPair('app', 1));
      expect(snapshot.roleCounts, containsPair('button', 1));
      expect(snapshot.roleCounts, containsPair('textField', 1));
      expect(snapshot.actionCount, 3);
      expect(json.toString(), isNot(contains('secret-token')));

      final debug = snapshot.debugTree();
      expect(debug, contains('SemanticInspectionSnapshot('));
      expect(debug, contains('nodeCount: 3'));
      expect(debug, contains('actionCount: 3'));
      expect(debug, contains('focusedNodeId: field:api-key'));
      expect(debug, contains('textField#field:api-key'));
      expect(debug, contains('label:"API key�"'));
      expect(debug, contains('value:"<redacted>"'));
      expect(debug, contains('actions:[copy, submit]'));
      expect(debug, contains('apiToken: "<redacted>"'));
      expect(debug, isNot(contains('secret-token')));
      expect(snapshot.toDebugString(), debug);
      expect(snapshot.toString(), debug);
      expect(tree.debugTree(includeState: false), isNot(contains('state:')));

      final field = snapshot.single(
        role: 'textField',
        action: 'copy',
        focused: true,
        stateContains: const {'historyCount': 2},
      );
      expect(field.label, 'API key�');
      expect(field.value, '<redacted>');
      expect(field.validationError, '<redacted>');
      expect(field.actions, ['copy', 'submit']);
      expect(field.state, containsPair('redactedValue', true));
      expect(field.state, containsPair('apiToken', '<redacted>'));
      expect(field.state, containsPair('text', '<redacted>'));
      expect(field.state, containsPair('historyCount', 2));

      final button = snapshot.single(role: 'button', label: 'Save');
      expect(button.actions, ['activate']);
    },
  );

  test('single failure explains the query and includes a debug tree', () {
    final snapshot = SemanticTree(
      root: const SemanticNode(
        id: SemanticNodeId('root'),
        role: SemanticRole.app,
        children: [
          SemanticNode(
            id: SemanticNodeId('button:save'),
            role: SemanticRole.button,
            label: 'Save',
            actions: {SemanticAction.activate},
          ),
        ],
      ),
    ).toInspectionSnapshot();

    expect(
      () => snapshot.single(
        role: 'command',
        action: 'activate',
        stateContains: const {'commandId': 'save'},
      ),
      throwsA(
        isA<StateError>()
            .having(
              (error) => error.message,
              'message',
              contains('found 0 for role:"command" action:"activate"'),
            )
            .having(
              (error) => error.message,
              'message',
              contains('stateContains:{commandId: "save"}'),
            )
            .having(
              (error) => error.message,
              'message',
              contains('SemanticInspectionSnapshot('),
            )
            .having(
              (error) => error.message,
              'message',
              contains('button#button:save label:"Save"'),
            ),
      ),
    );
  });

  test(
    'semantic inspection JSON parser ignores additive fields and recomputes summaries',
    () {
      final snapshot = SemanticInspectionSnapshot.fromJson({
        'schemaVersion': 2,
        'nodeCount': 999,
        'roleCounts': {'wrong': 999},
        'actionCount': 999,
        'focusedNodeId': 'field:secret',
        'futureSummary': 'ignored',
        'root': {
          'id': 'root',
          'role': 'app',
          'futureNodeFlag': true,
          'children': [
            {
              'id': 'field:secret',
              'role': 'textField',
              'label': 'Token\x1b[31m',
              'value': 'secret-token',
              'focused': true,
              'validationError': 'secret-token rejected',
              'actions': ['submit', 'copy', 'copy'],
              'state': {
                'redactedValue': true,
                'apiToken': 'secret-token',
                'historyCount': 2,
              },
              'futureNodePayload': {'can': 'be ignored'},
            },
          ],
        },
      });

      expect(SemanticInspectionSnapshot.currentSchemaVersion, 1);
      expect(SemanticInspectionSnapshot.isSchemaVersionCompatible(2), isTrue);
      expect(
        SemanticInspectionSnapshot.stableJsonFields,
        containsAll(['schemaVersion', 'root', 'nodeCount']),
      );
      expect(
        SemanticInspectionNode.stableJsonFields,
        containsAll(['id', 'role', 'actions', 'state', 'children']),
      );
      expect(snapshot.schemaVersion, 2);
      expect(snapshot.nodeCount, 2);
      expect(snapshot.roleCounts, {'app': 1, 'textField': 1});
      expect(snapshot.actionCount, 2);
      expect(snapshot.focusedNodeId, 'field:secret');

      final field = snapshot.single(role: 'textField', action: 'copy');
      expect(field.label, 'Token�');
      expect(field.actions, ['copy', 'submit']);
      expect(field.value, '<redacted>');
      expect(field.validationError, '<redacted>');
      expect(field.state, containsPair('apiToken', '<redacted>'));
      expect(field.state, containsPair('historyCount', 2));
      expect(field.toJson(), isNot(contains('futureNodePayload')));
      expect(snapshot.toJson(), isNot(contains('futureSummary')));
    },
  );

  test('semantic inspection JSON rejects unsupported/malformed roots', () {
    expect(
      () => SemanticInspectionSnapshot.fromJson({
        'schemaVersion': 0,
        'root': {'id': 'root', 'role': 'app'},
      }),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => SemanticInspectionSnapshot.fromJson({'schemaVersion': 1}),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => SemanticInspectionSnapshot.fromJson({
        'schemaVersion': 1,
        'root': {'id': 'root'},
      }),
      throwsA(isA<FormatException>()),
    );
  });

  test('semantic inspection snapshot keeps non-sensitive structured state', () {
    final snapshot = SemanticTree(
      root: const SemanticNode(
        id: SemanticNodeId('root'),
        role: SemanticRole.app,
        children: [
          SemanticNode(
            id: SemanticNodeId('chart:latency'),
            role: SemanticRole.chart,
            label: 'Latency',
            value: {
              'latest': 42,
              'series': ['p50', 'p95\x1b[31m'],
            },
            state: SemanticState({
              'chartType': 'sparkline',
              'chartPointCount': 64,
            }),
          ),
        ],
      ),
    ).toInspectionSnapshot();

    final chart = snapshot.single(role: 'chart', label: 'Latency');

    expect(chart.value, {
      'latest': 42,
      'series': ['p50', 'p95�'],
    });
    expect(chart.state, containsPair('chartType', 'sparkline'));
    expect(chart.state, containsPair('chartPointCount', 64));
  });

  testWidgets('tester exposes semantic inspection snapshot and JSON', (
    tester,
  ) async {
    var activated = 0;
    tester.pumpWidget(
      Semantics(
        id: const SemanticNodeId('command:save'),
        role: SemanticRole.command,
        label: 'Save',
        focused: true,
        actions: const {SemanticAction.activate},
        state: const SemanticState({'commandId': 'save'}),
        onAction: (action) {
          expect(action, SemanticAction.activate);
          activated += 1;
        },
        child: const Text('Save'),
      ),
    );

    final snapshot = tester.semanticInspectionSnapshot();
    final command = snapshot.single(
      role: 'command',
      label: 'Save',
      action: 'activate',
      focused: true,
      stateContains: const {'commandId': 'save'},
    );
    expect(snapshot.nodeById(command.id), same(command));
    final json = tester.semanticInspectionJson();
    final parsed = SemanticInspectionSnapshot.fromJson(json);
    final parsedCommand = parsed.single(
      role: 'command',
      label: 'Save',
      action: 'activate',
      focused: true,
      stateContains: const {'commandId': 'save'},
    );

    expect(command.id, 'command:save');
    expect(parsedCommand.id, command.id);
    expect(snapshot.roleCounts, containsPair('command', 1));
    expect(parsed.roleCounts, containsPair('command', 1));
    expect(snapshot.actionCount, 1);
    expect(parsed.actionCount, 1);
    expect(json['schemaVersion'], 1);
    expect(json['focusedNodeId'], 'command:save');
    expect(json['roleCounts'], containsPair('command', 1));
    expect(
      tester.semanticTreeDebugString(includeState: false),
      allOf(
        contains('SemanticInspectionSnapshot('),
        contains('command#command:save label:"Save" focused'),
        isNot(contains('state:')),
      ),
    );

    final result = await tester.invokeSemanticAction(
      SemanticAction.activate,
      id: SemanticNodeId(parsedCommand.id),
    );

    expect(result.completed, isTrue);
    expect(result.node?.id, const SemanticNodeId('command:save'));
    expect(activated, 1);
  });
}
