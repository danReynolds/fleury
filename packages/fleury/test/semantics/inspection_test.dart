import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_test.dart';
import 'package:test/test.dart';

void main() {
  test('toJsonCapped bounds the tree and marks what it dropped', () {
    final root = SemanticNode(
      id: const SemanticNodeId('root'),
      role: SemanticRole.app,
      children: <SemanticNode>[
        for (var i = 0; i < 6; i++)
          SemanticNode(
            id: SemanticNodeId('item-$i'),
            role: SemanticRole.listItem,
            label: 'Item $i',
          ),
      ],
    );
    final snapshot = SemanticTree(root: root).toInspectionSnapshot();
    expect(snapshot.nodeCount, 7);

    // Under a generous cap it is byte-identical to the unbounded toJson — no
    // truncation markers leak onto a tree that fits.
    final full = snapshot.toJsonCapped(maxNodes: 1000);
    expect(full.containsKey('truncated'), isFalse);
    expect(full, snapshot.toJson());

    // A tight cap keeps the root + budget nodes and flags exactly what it cut,
    // while the summary still describes the full tree so the agent knows to
    // drill in with find_nodes.
    final capped = snapshot.toJsonCapped(maxNodes: 4);
    expect(capped['truncated'], isTrue);
    expect(capped['nodeCount'], 7);
    final rootJson = capped['root'] as Map<String, Object?>;
    expect((rootJson['children'] as List).length, 3);
    expect(rootJson['childrenTruncated'], 3);
  });

  test(
    'semantic inspection snapshot is queryable, redacted, and JSON-safe',
    () {
      final tree = SemanticTree(
        root: SemanticNode(
          id: const SemanticNodeId('root'),
          role: SemanticRole.app,
          children: [
            SemanticNode(
              id: SemanticNodeId('field:api-key'),
              role: SemanticRole.textField,
              label: 'API key\x1b]52;c;secret-token\x07',
              value: 'secret-token',
              focused: true,
              validationError: 'secret-token rejected',
              bounds: CellRect.fromLTWH(1, 2, 10, 1),
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
      expect(field.bounds, CellRect.fromLTWH(1, 2, 10, 1));
      expect(field.toJson()['bounds'], {
        'left': 1,
        'top': 2,
        'width': 10,
        'height': 1,
      });
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
              'bounds': {'left': 3, 'top': 4, 'width': 12, 'height': 1},
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
      expect(field.bounds, CellRect.fromLTWH(3, 4, 12, 1));
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

  group('toSemanticTree reconstruction (the serve-wire consumer path)', () {
    test('rebuilds a SemanticNode tree, preserving structure and state', () {
      final original = SemanticTree(
        root: SemanticNode(
          id: const SemanticNodeId('root'),
          role: SemanticRole.app,
          children: [
            SemanticNode(
              id: const SemanticNodeId('btn:save'),
              role: SemanticRole.button,
              label: 'Save',
              hint: 'Persist the document',
              enabled: false,
              actions: const {SemanticAction.activate, SemanticAction.focus},
              state: const SemanticState({'commandId': 'save'}),
            ),
            const SemanticNode(
              id: SemanticNodeId('chk:wrap'),
              role: SemanticRole.checkbox,
              label: 'Wrap',
              checked: true,
              focused: true,
              expanded: false,
            ),
          ],
        ),
      );

      final rebuilt = original.toInspectionSnapshot().toSemanticTree();

      expect(rebuilt.root.role, SemanticRole.app);
      expect(rebuilt.root.id, const SemanticNodeId('root'));
      expect(rebuilt.root.children, hasLength(2));

      final button = rebuilt.root.children[0];
      expect(button.id, const SemanticNodeId('btn:save'));
      expect(button.role, SemanticRole.button);
      expect(button.label, 'Save');
      expect(button.hint, 'Persist the document');
      expect(button.enabled, isFalse);
      expect(button.actions, {SemanticAction.activate, SemanticAction.focus});
      expect(button.state['commandId'], 'save');

      final checkbox = rebuilt.root.children[1];
      expect(checkbox.role, SemanticRole.checkbox);
      expect(checkbox.checked, isTrue);
      expect(checkbox.focused, isTrue);
      expect(checkbox.expanded, isFalse);
    });

    test('redaction survives reconstruction — no plaintext reaches the tree', () {
      final rebuilt = SemanticTree(
        root: SemanticNode(
          id: const SemanticNodeId('root'),
          role: SemanticRole.app,
          children: [
            SemanticNode(
              id: const SemanticNodeId('field:key'),
              role: SemanticRole.textField,
              label: 'API key',
              value: 'secret-token',
              state: const SemanticState({
                'redactedValue': true,
                'apiToken': 'secret-token',
              }),
            ),
          ],
        ),
      ).toInspectionSnapshot().toSemanticTree();

      final field = rebuilt.root.children.single;
      expect(field.value, '<redacted>');
      expect(field.state['apiToken'], '<redacted>');
      // The reconstructed tree, re-serialized, still carries no plaintext.
      expect(
        rebuilt.toInspectionSnapshot().toJson().toString(),
        isNot(contains('secret-token')),
      );
    });

    test('an unknown role degrades to text; unknown actions are dropped', () {
      final snapshot = SemanticInspectionSnapshot.fromJson({
        'schemaVersion': 1,
        'root': {
          'id': 'root',
          'role': 'app',
          'children': [
            {
              'id': 'mystery',
              'role': 'hologram', // not a SemanticRole
              'label': 'Future node',
              'actions': ['activate', 'teleport'], // teleport is unknown
            },
          ],
        },
      });

      final node = snapshot.toSemanticTree().root.children.single;
      expect(node.role, SemanticRole.text, reason: 'unknown role falls back');
      expect(node.label, 'Future node');
      expect(
        node.actions,
        {SemanticAction.activate},
        reason: 'the unrecognized action is dropped, not an error',
      );
    });
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
