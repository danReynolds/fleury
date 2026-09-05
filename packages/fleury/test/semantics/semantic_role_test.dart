// SemanticRole is an open vocabulary: the core set is a list of constants, and
// any package can declare a role that projects through a core role. These
// tests pin the contract every surface relies on — identity by name, the
// projection chain, default labels, and a declared role surviving the
// inspection JSON and the serve wire intact.
@TestOn('vm')
library;

import 'dart:convert';

import 'package:fleury/fleury_host.dart';
import 'package:fleury/fleury_wire.dart';
import 'package:test/test.dart';

const kanbanBoard = SemanticRole('kanbanBoard', base: SemanticRole.region);
const kanbanCard = SemanticRole('kanbanCard', base: SemanticRole.listItem);
const pinnedCard = SemanticRole('pinnedCard', base: kanbanCard);

SemanticTree _board() => SemanticTree(
  root: const SemanticNode(
    id: SemanticNodeId('root'),
    role: SemanticRole.app,
    children: [
      SemanticNode(
        id: SemanticNodeId('board'),
        role: kanbanBoard,
        label: 'Sprint 12',
        bounds: CellRect(offset: CellOffset(0, 0), size: CellSize(20, 4)),
        children: [
          SemanticNode(
            id: SemanticNodeId('card'),
            role: kanbanCard,
            label: 'Fix login',
            actions: {SemanticAction.activate},
            bounds: CellRect(offset: CellOffset(0, 1), size: CellSize(9, 1)),
          ),
          SemanticNode(
            id: SemanticNodeId('pinned'),
            role: pinnedCard,
            label: 'Ship 1.0',
            bounds: CellRect(offset: CellOffset(0, 2), size: CellSize(8, 1)),
          ),
        ],
      ),
    ],
  ),
);

void main() {
  group('identity and projection', () {
    test('a role is identified by its name, not its instance', () {
      const again = SemanticRole('kanbanCard', base: SemanticRole.text);
      expect(again, kanbanCard, reason: 'same name, different base/instance');
      expect(again.hashCode, kanbanCard.hashCode);
      expect(kanbanCard, isNot(SemanticRole.listItem));
      expect(SemanticRole.button, SemanticRole.button);
      expect({kanbanCard, again}, hasLength(1));
    });

    test('core roles have no base; declared roles chain to a core role', () {
      expect(SemanticRole.button.isCore, isTrue);
      expect(SemanticRole.button.coreRole, SemanticRole.button);
      expect(kanbanCard.isCore, isFalse);
      expect(kanbanCard.coreRole, SemanticRole.listItem);
      expect(pinnedCard.isCore, isFalse);
      expect(pinnedCard.coreRole, SemanticRole.listItem, reason: 'two hops');
      for (final role in SemanticRole.values) {
        expect(role.isCore, isTrue, reason: '$role');
        expect(SemanticRole.coreByName(role.name), same(role));
      }
      expect(SemanticRole.coreByName('kanbanCard'), isNull);
    });

    test('labels default to the humanized name, with core overrides kept', () {
      expect(SemanticRole.spinButton.label, 'spin button');
      expect(SemanticRole.jsonNode.label, 'json node');
      expect(SemanticRole.app.label, 'application');
      expect(SemanticRole.errorBoundary.label, 'rendering error');
      expect(SemanticRole.json.label, 'json document');
      expect(SemanticRole.markdown.label, 'markdown document');
      expect(kanbanBoard.label, 'kanban board');
      expect(pinnedCard.label, 'pinned card', reason: 'derived from the name');
      expect(
        humanizeSemanticRoleName('fileMentionPicker'),
        'file mention picker',
      );
      expect(SemanticRole.textField.toString(), 'SemanticRole.textField');
      expect(
        kanbanCard.toString(),
        "SemanticRole('kanbanCard', base: listItem)",
      );
      expect(
        pinnedCard.toString(),
        "SemanticRole('pinnedCard', base: kanbanCard)",
      );
    });

    test('role names are identifiers, because they are embedded in ids', () {
      expect(isValidSemanticRoleName('kanbanCard'), isTrue);
      expect(isValidSemanticRoleName('card_2'), isTrue);
      expect(isValidSemanticRoleName(''), isFalse);
      expect(isValidSemanticRoleName('kanban card'), isFalse);
      expect(isValidSemanticRoleName('a/b'), isFalse);
      expect(isValidSemanticRoleName('auto~1'), isFalse);
      expect(isValidSemanticRoleName('1st'), isFalse);
      expect(isValidSemanticRoleName('_card'), isFalse);
    });

    test('fromWire resolves core names and rebuilds declared roles', () {
      expect(SemanticRole.fromWire('button'), same(SemanticRole.button));
      final rebuilt = SemanticRole.fromWire(
        'kanbanCard',
        coreRoleName: 'listItem',
      );
      expect(rebuilt, kanbanCard);
      expect(rebuilt.coreRole, SemanticRole.listItem);
      // Unknown core role (added by a newer producer): degrade to text, keep
      // the name so an agent can still match on it.
      final future = SemanticRole.fromWire('hologram', coreRoleName: 'portal');
      expect(future.name, 'hologram');
      expect(future.coreRole, SemanticRole.text);
      expect(SemanticRole.fromWire('hologram').coreRole, SemanticRole.text);
    });

    test('fromWire hands back one instance per declared name', () {
      final a = SemanticRole.fromWire('kanbanCard', coreRoleName: 'listItem');
      final b = SemanticRole.fromWire('kanbanCard', coreRoleName: 'listItem');
      expect(identical(a, b), isTrue, reason: 'decoders rebuild every frame');
      final moved = SemanticRole.fromWire('kanbanCard', coreRoleName: 'region');
      expect(identical(a, moved), isFalse);
      expect(moved.coreRole, SemanticRole.region);
      expect(SemanticRole.fromWire('button'), same(SemanticRole.button));
    });
  });

  group('declared roles across the surfaces', () {
    test(
      'inspection JSON carries the name and the core role, and rebuilds',
      () {
        final json = _board().toInspectionSnapshot().toJson();
        final root = json['root'] as Map<String, Object?>;
        final board = (root['children'] as List).first as Map<String, Object?>;
        expect(board['role'], 'kanbanBoard');
        expect(board['coreRole'], 'region');
        final card = (board['children'] as List).first as Map<String, Object?>;
        expect(card['coreRole'], 'listItem');
        final pinned = (board['children'] as List).last as Map<String, Object?>;
        expect(
          pinned['coreRole'],
          'listItem',
          reason: 'the wire carries the core root, not the direct base',
        );
        expect(
          root.containsKey('coreRole'),
          isFalse,
          reason: 'core role: absent',
        );

        final rebuilt = SemanticInspectionSnapshot.fromJson(
          jsonDecode(jsonEncode(json)) as Map<String, Object?>,
        ).toSemanticTree();
        final rebuiltCard = rebuilt.nodeById(const SemanticNodeId('card'))!;
        expect(rebuiltCard.role, kanbanCard);
        expect(rebuiltCard.role.coreRole, SemanticRole.listItem);
        expect(rebuilt.byRole(kanbanCard).map((n) => n.id.value), ['card']);
      },
    );

    test('the serve wire round-trips a declared role through a peer that '
        'never imported it', () {
      final encoder = SemanticsWireEncoder();
      final decoder = SemanticsWireDecoder();
      final bytes = encoder.encodeTree(_board())!;
      final mirrored = decoder.apply(bytes)!;
      final card = mirrored.nodeById(const SemanticNodeId('card'))!;
      expect(card.role.name, 'kanbanCard');
      expect(card.role.coreRole, SemanticRole.listItem);
      expect(card.role, kanbanCard);
      // Equality by name also keeps the owner's diff honest: an unchanged
      // declared-role node is not "changed" just because it was rebuilt.
      expect(
        encoder.encodeTree(_board()),
        isNull,
        reason: 'identical frame encodes nothing',
      );
    });

    test('the accessibility snapshot labels a declared role sensibly', () {
      final snapshot = _board().toAccessibilitySnapshot();
      final board = snapshot.root.children.single;
      expect(board.roleLabel, 'kanban board');
      expect(board.announcement, startsWith('kanban board | Sprint 12'));
      final json = board.toJson();
      expect(json['role'], 'kanbanBoard');
      expect(json['coreRole'], 'region');
      expect(board.children.last.roleLabel, 'pinned card');
    });

    test('coverage treats a declared container like its core container', () {
      // A region-based role covers nothing by itself: the text under it must
      // be covered by readable descendants, exactly as a core region would.
      final buffer = CellBuffer(const CellSize(20, 4))
        ..writeText(const CellOffset(0, 0), 'Sprint 12')
        ..writeText(const CellOffset(0, 1), 'Fix login')
        ..writeText(const CellOffset(0, 2), 'Ship 1.0')
        ..writeText(const CellOffset(0, 3), 'orphan');
      final result = applySemanticTextFallback(tree: _board(), buffer: buffer);
      // Rows 1 and 2 are covered by the (list-item based) cards. Row 0 sits
      // under the board only — a region-based container, so it covers nothing
      // by itself — and row 3 under nothing; both surface as fallback text.
      final fallbackText = result.tree.root.descendants
          .where((n) => n.role == SemanticRole.text)
          .map((n) => '${n.label ?? n.value}')
          .join(' | ');
      // (Fallback nodes are per word run, so the title arrives as two.)
      expect(result.audit.fallbackNodeCount, greaterThan(0));
      expect(fallbackText, contains('Sprint'));
      expect(fallbackText, contains('12'));
      expect(fallbackText, contains('orphan'));
      expect(fallbackText, isNot(contains('Fix')));
      expect(fallbackText, isNot(contains('Ship')));
    });
  });
}
