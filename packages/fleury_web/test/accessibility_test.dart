@TestOn('browser')
library;

// Accessibility assertion suite for the web target's semantic surface.
//
// fleury_web makes a Fleury app screen-reader-accessible in the browser by
// projecting the semantic tree into a real ARIA accessibility DOM (separate from
// the visual cell grid, which is aria-hidden). This suite asserts the INVARIANTS
// that make that DOM accessible — not just that each role maps to some string
// (which would only re-state the presenter's switch), but that the output obeys
// the rules a screen reader and an automated checker (axe/WCAG) rely on:
//
//   • every interactive node gets an accessible NAME (the #1 a11y failure mode),
//   • every emitted `role` is a VALID ARIA role,
//   • dynamic/status roles get a LIVE REGION so updates are announced,
//   • interaction STATES (checked/expanded/selected/disabled/…) are reflected,
//   • the FOCUSED node is exposed as a focusable element,
//   • and EVERY SemanticRole resolves to valid-ARIA-or-a-plain-container, so a
//     role added later can't silently ship without an accessibility decision.
//
// Runs in a real browser (`dart test -p chrome`).

import 'package:fleury/fleury_host.dart';
import 'package:fleury_web/src/semantics/semantic_dom_presenter.dart';
import 'package:test/test.dart';
import 'package:web/web.dart' as web;

/// Presents [tree] into a fresh detached root and returns it for inspection.
web.Element present(SemanticTree tree) {
  final root = web.document.createElement('div');
  SemanticDomPresenter(root: root).present(tree);
  return root;
}

SemanticTree _appOf(List<SemanticNode> children) => SemanticTree(
  root: SemanticNode(
    id: const SemanticNodeId('root'),
    role: SemanticRole.app,
    children: children,
  ),
);

web.Element _byId(web.Element root, String id) =>
    root.querySelector('[data-fleury-semantic-id="$id"]')!;

/// The accessible name a screen reader would compute: an explicit `aria-label`,
/// else the element's own text. (Good enough for the labelled cases here, which
/// is what the invariant requires.)
String _accessibleName(web.Element el) {
  final label = el.getAttribute('aria-label');
  if (label != null && label.trim().isNotEmpty) return label.trim();
  return (el.textContent ?? '').trim();
}

/// Valid ARIA roles the presenter is allowed to emit (ARIA 1.2). A `role`
/// attribute outside this set is an accessibility bug (screen readers ignore or
/// mishandle unknown roles).
const _validAriaRoles = <String>{
  'group', 'region', 'navigation', 'list', 'listitem', 'table', 'row', 'cell',
  'link', 'img', 'textbox', 'button', 'checkbox', 'radio', 'switch',
  'spinbutton', 'slider', 'menu', 'menuitem', 'dialog', 'progressbar', 'log',
  'status', 'tab', 'tree', 'treeitem', 'form',
};

/// Roles that present an interactive control, which ARIA requires to have an
/// accessible name.
const _interactiveRoles = <SemanticRole>{
  SemanticRole.button,
  SemanticRole.link,
  SemanticRole.textField,
  SemanticRole.textArea,
  SemanticRole.checkbox,
  SemanticRole.radio,
  SemanticRole.toggle,
  SemanticRole.slider,
  SemanticRole.spinButton,
  SemanticRole.menuItem,
  SemanticRole.tab,
};

void main() {
  group('accessible names (the #1 a11y rule)', () {
    test('every labelled interactive node gets a non-empty accessible name', () {
      final nodes = [
        for (final (i, role) in _interactiveRoles.indexed)
          SemanticNode(
            id: SemanticNodeId('n$i'),
            role: role,
            label: 'Control $i',
            actions: const {SemanticAction.activate},
          ),
      ];
      final root = present(_appOf(nodes));

      for (var i = 0; i < nodes.length; i++) {
        final el = _byId(root, 'n$i');
        expect(
          _accessibleName(el),
          isNotEmpty,
          reason: '${nodes[i].role} produced an element with no accessible name',
        );
      }
    });

    test('a button with no label but text content is still named', () {
      final root = present(
        _appOf([
          SemanticNode(
            id: const SemanticNodeId('b'),
            role: SemanticRole.button,
            value: 'Save',
            actions: const {SemanticAction.activate},
          ),
        ]),
      );
      expect(_accessibleName(_byId(root, 'b')), isNotEmpty);
    });
  });

  group('valid ARIA roles', () {
    test('EVERY SemanticRole resolves to a valid ARIA role or a plain container',
        () {
      // Guards the future: a newly added role that maps to a bogus ARIA string
      // (or is forgotten) fails here, forcing an accessibility decision.
      for (final role in SemanticRole.values) {
        final root = present(
          _appOf([
            SemanticNode(
              id: const SemanticNodeId('x'),
              role: role,
              label: 'X',
            ),
          ]),
        );
        final ariaRole = _byId(root, 'x').getAttribute('role');
        expect(
          ariaRole == null || _validAriaRoles.contains(ariaRole),
          isTrue,
          reason: 'role $role emitted invalid ARIA role "$ariaRole"',
        );
      }
    });
  });

  group('structural role mapping (screen-reader navigation depends on it)', () {
    test('a table exposes table/row/cell structure', () {
      final root = present(
        _appOf([
          SemanticNode(
            id: const SemanticNodeId('t'),
            role: SemanticRole.table,
            label: 'People',
            children: [
              SemanticNode(
                id: const SemanticNodeId('r0'),
                role: SemanticRole.tableRow,
                children: [
                  SemanticNode(
                    id: const SemanticNodeId('c0'),
                    role: SemanticRole.tableCell,
                    label: 'name',
                    value: 'dan',
                  ),
                ],
              ),
            ],
          ),
        ]),
      );
      expect(_byId(root, 't').getAttribute('role'), 'table');
      expect(_byId(root, 'r0').getAttribute('role'), 'row');
      expect(_byId(root, 'c0').getAttribute('role'), 'cell');
    });

    test('a text field is a real, named, value-bearing input', () {
      final root = present(
        _appOf([
          SemanticNode(
            id: const SemanticNodeId('f'),
            role: SemanticRole.textField,
            label: 'Email',
            value: 'a@b.com',
            actions: const {SemanticAction.focus},
          ),
        ]),
      );
      final f = _byId(root, 'f') as web.HTMLInputElement;
      expect(f.localName, 'input');
      expect(f.getAttribute('role'), 'textbox');
      expect(f.getAttribute('aria-label'), 'Email');
      expect(f.value, 'a@b.com');
    });

    test('a link is an anchor with link role', () {
      final root = present(
        _appOf([
          SemanticNode(
            id: const SemanticNodeId('l'),
            role: SemanticRole.link,
            label: 'Docs',
            actions: const {SemanticAction.activate},
          ),
        ]),
      );
      final l = _byId(root, 'l');
      expect(l.localName, 'a');
      expect(l.getAttribute('role'), 'link');
    });
  });

  group('interaction states are reflected as ARIA', () {
    test('checked / expanded / selected / disabled map to aria-*', () {
      final root = present(
        _appOf([
          SemanticNode(
            id: const SemanticNodeId('cb'),
            role: SemanticRole.checkbox,
            label: 'Agree',
            checked: true,
            actions: const {SemanticAction.activate},
          ),
          SemanticNode(
            id: const SemanticNodeId('row'),
            role: SemanticRole.treeItem,
            label: 'Branch',
            expanded: true,
            selected: true,
          ),
          SemanticNode(
            id: const SemanticNodeId('btn'),
            role: SemanticRole.button,
            label: 'Submit',
            enabled: false,
            actions: const {SemanticAction.activate},
          ),
        ]),
      );
      expect(_byId(root, 'cb').getAttribute('aria-checked'), 'true');
      expect(_byId(root, 'row').getAttribute('aria-expanded'), 'true');
      expect(_byId(root, 'row').getAttribute('aria-selected'), 'true');
      expect(_byId(root, 'btn').getAttribute('aria-disabled'), 'true');
    });
  });

  group('live regions (so dynamic updates are announced, not spammed)', () {
    test('status / progress / log roles carry aria-live', () {
      final root = present(
        _appOf([
          SemanticNode(
            id: const SemanticNodeId('s'),
            role: SemanticRole.status,
            label: 'Ready',
          ),
          SemanticNode(
            id: const SemanticNodeId('p'),
            role: SemanticRole.progress,
            label: 'Uploading',
            value: 0.4,
          ),
          SemanticNode(
            id: const SemanticNodeId('lg'),
            role: SemanticRole.log,
            label: 'Output',
          ),
        ]),
      );
      for (final id in ['s', 'p', 'lg']) {
        expect(
          _byId(root, id).getAttribute('aria-live'),
          isNotNull,
          reason: 'live-region role for "$id" must set aria-live',
        );
      }
    });
  });

  group('focus is exposed to assistive tech', () {
    test('the focused node becomes a focusable element marked focused', () {
      final root = present(
        _appOf([
          SemanticNode(
            id: const SemanticNodeId('cmd'),
            role: SemanticRole.textField,
            label: 'Command',
            focused: true,
            actions: const {SemanticAction.focus},
          ),
        ]),
      );
      final el = _byId(root, 'cmd');
      expect(el.hasAttribute('tabindex'), isTrue,
          reason: 'a focused node must be focusable');
      expect(el.getAttribute('data-fleury-focused'), 'true');
    });
  });

  group('no double-exposure', () {
    test('the exposed semantic root is NOT aria-hidden', () {
      // The visual cell grid is aria-hidden (a screen reader hitting positioned
      // single-character cells gets gibberish); the SEMANTIC surface is the one
      // assistive tech reads, so it must stay exposed.
      final root = present(_appOf(const []));
      expect(root.getAttribute('aria-hidden'), isNull);
      expect(root.className, 'fleury-semantics');
    });
  });

  group('structural integrity', () {
    test('no two accessible nodes share an id (would break SR navigation)', () {
      final root = present(
        _appOf([
          for (var i = 0; i < 5; i++)
            SemanticNode(
              id: SemanticNodeId('item-$i'),
              role: SemanticRole.listItem,
              label: 'Item $i',
            ),
        ]),
      );
      final ids = [
        for (final el in root.querySelectorAll('[data-fleury-semantic-id]').toIterable())
          (el as web.Element).getAttribute('data-fleury-semantic-id'),
      ];
      expect(ids.toSet().length, ids.length, reason: 'duplicate semantic ids: $ids');
    });

    test('a list contains its list items (ARIA required-children)', () {
      final root = present(
        _appOf([
          SemanticNode(
            id: const SemanticNodeId('list'),
            role: SemanticRole.list,
            label: 'Files',
            children: [
              SemanticNode(
                id: const SemanticNodeId('li0'),
                role: SemanticRole.listItem,
                label: 'a.dart',
              ),
              SemanticNode(
                id: const SemanticNodeId('li1'),
                role: SemanticRole.listItem,
                label: 'b.dart',
              ),
            ],
          ),
        ]),
      );
      final list = _byId(root, 'list');
      expect(list.getAttribute('role'), 'list');
      expect(list.querySelectorAll('[role="listitem"]').length, 2);
    });
  });
}

extension on web.NodeList {
  Iterable<web.Node> toIterable() sync* {
    for (var i = 0; i < length; i++) {
      yield item(i)!;
    }
  }
}
