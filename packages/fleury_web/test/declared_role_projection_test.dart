// Roles are an open vocabulary: a role declared outside the core set (by a
// widget package or an app) must project into the accessible DOM through its
// core role, while keeping its own name legible as data.
//
// Runs in a real browser (`dart test -p chrome`).
@TestOn('browser')
library;

import 'package:fleury/fleury_host.dart';
import 'package:test/test.dart';
import 'package:web/web.dart' as web;

import 'fixtures/semantic_dom_harness.dart';

const kanbanBoard = SemanticRole('kanbanBoard', base: SemanticRole.region);
const kanbanCard = SemanticRole('kanbanCard', base: SemanticRole.listItem);
const buildStatus = SemanticRole('buildStatus', base: SemanticRole.status);
const notesEditor = SemanticRole('notesEditor', base: SemanticRole.textArea);
// A two-level chain: projects through kanbanCard, then listItem.
const pinnedCard = SemanticRole('pinnedCard', base: kanbanCard);

void main() {
  test('a declared role lands on its core role\'s ARIA projection', () {
    final root = present(
      SemanticTree(
        root: const SemanticNode(
          id: SemanticNodeId('root'),
          role: SemanticRole.app,
          children: [
            SemanticNode(
              id: SemanticNodeId('board'),
              role: kanbanBoard,
              label: 'Sprint 12',
              children: [
                SemanticNode(
                  id: SemanticNodeId('card'),
                  role: kanbanCard,
                  label: 'Fix login',
                ),
                SemanticNode(
                  id: SemanticNodeId('pinned'),
                  role: pinnedCard,
                  label: 'Ship 1.0',
                ),
              ],
            ),
            SemanticNode(
              id: SemanticNodeId('build'),
              role: buildStatus,
              label: 'build passing',
            ),
          ],
        ),
      ),
    );

    final board = byId(root, 'board');
    expect(board.getAttribute('role'), 'region');
    expect(board.getAttribute('data-fleury-semantic-role'), 'kanbanBoard');
    expect(board.getAttribute('data-fleury-semantic-core-role'), 'region');

    final card = byId(root, 'card');
    expect(card.getAttribute('role'), 'listitem');
    expect(card.getAttribute('data-fleury-semantic-role'), 'kanbanCard');

    final pinned = byId(root, 'pinned');
    expect(pinned.getAttribute('role'), 'listitem', reason: 'chain resolves');
    expect(pinned.getAttribute('data-fleury-semantic-core-role'), 'listItem');

    final build = byId(root, 'build');
    expect(build.getAttribute('role'), 'status');
    expect(build.getAttribute('aria-live'), 'polite', reason: 'live region');

    // A core role carries no core-role attribute: the name already is one.
    expect(
      root
          .querySelector('[data-fleury-semantic-id="root"]')!
          .getAttribute('data-fleury-semantic-core-role'),
      isNull,
    );
  });

  test('a declared text area mirrors as a native multiline textbox', () {
    final root = present(
      SemanticTree(
        root: const SemanticNode(
          id: SemanticNodeId('root'),
          role: SemanticRole.app,
          children: [
            SemanticNode(
              id: SemanticNodeId('notes'),
              role: notesEditor,
              label: 'Notes',
              value: 'draft',
            ),
          ],
        ),
      ),
    );
    final notes = byId(root, 'notes');
    expect(notes.localName, 'textarea');
    expect(notes.getAttribute('role'), 'textbox');
    expect(notes.getAttribute('aria-multiline'), 'true');
    expect(notes.getAttribute('readonly'), isNotNull);
    expect((notes as web.HTMLTextAreaElement).value, 'draft');
  });

  test(
    'a role decoded from the wire projects exactly like the declared one',
    () {
      // What the served client sees: the name plus the core role, rebuilt with
      // fromWire — it has never imported the package that declared kanbanCard.
      final decoded = SemanticRole.fromWire(
        'kanbanCard',
        coreRoleName: 'listItem',
      );
      expect(decoded, kanbanCard, reason: 'name is identity');
      final root = present(
        SemanticTree(
          root: SemanticNode(
            id: const SemanticNodeId('root'),
            role: SemanticRole.app,
            children: [
              SemanticNode(
                id: const SemanticNodeId('card'),
                role: decoded,
                label: 'Fix login',
              ),
            ],
          ),
        ),
      );
      expect(byId(root, 'card').getAttribute('role'), 'listitem');
    },
  );
}
