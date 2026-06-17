@TestOn('browser')
library;

import 'package:fleury/fleury_host.dart';
import 'package:fleury_web/src/semantics/semantic_dom_presenter.dart';
import 'package:test/test.dart';
import 'package:web/web.dart' as web;

void main() {
  group('SemanticDomPresenter', () {
    test('renders semantic roles and states into accessible DOM', () {
      final root = web.document.createElement('div');
      final presenter = SemanticDomPresenter(root: root);

      presenter.present(
        SemanticTree(
          root: SemanticNode(
            id: SemanticNodeId('root'),
            role: SemanticRole.app,
            children: [
              SemanticNode(
                id: SemanticNodeId('command'),
                role: SemanticRole.textField,
                label: 'Command',
                value: 'deploy',
                hint: 'Type a command',
                focused: true,
                bounds: CellRect.fromLTWH(2, 3, 10, 1),
                actions: {SemanticAction.focus, SemanticAction.submit},
                state: SemanticState({'readOnly': true}),
              ),
              SemanticNode(
                id: SemanticNodeId('status'),
                role: SemanticRole.status,
                label: 'Ready',
                busy: true,
              ),
            ],
          ),
        ),
      );

      final field =
          root.querySelector('[data-fleury-semantic-id="command"]')!
              as web.HTMLInputElement;
      final status = root.querySelector('[data-fleury-semantic-id="status"]')!;

      expect(root.className, 'fleury-semantics');
      expect(root.getAttribute('aria-hidden'), isNull);
      expect(root.getAttribute('style'), contains('position:absolute'));
      expect(field.localName, 'input');
      expect(field.getAttribute('role'), 'textbox');
      expect(field.getAttribute('aria-label'), 'Command');
      expect(field.value, 'deploy');
      expect(field.getAttribute('data-fleury-value'), 'deploy');
      expect(field.getAttribute('data-fleury-bounds-left'), '2');
      expect(field.getAttribute('data-fleury-bounds-top'), '3');
      expect(field.getAttribute('data-fleury-bounds-width'), '10');
      expect(field.getAttribute('data-fleury-bounds-height'), '1');
      expect(field.getAttribute('aria-description'), 'Type a command');
      expect(field.getAttribute('data-fleury-focused'), 'true');
      expect(field.getAttribute('aria-readonly'), 'true');
      expect(field.hasAttribute('readonly'), isTrue);
      expect(field.getAttribute('tabindex'), '-1');
      expect(field.getAttribute('data-fleury-actions'), 'focus submit');
      expect(field.getAttribute('data-fleury-primary-action'), 'focus');
      expect(status.getAttribute('role'), 'status');
      expect(status.getAttribute('aria-live'), 'polite');
      expect(status.getAttribute('aria-busy'), 'true');
    });

    test('uses text nodes for unsafe-looking semantic text', () {
      final root = web.document.createElement('div');
      final presenter = SemanticDomPresenter(root: root);

      presenter.present(
        const SemanticTree(
          root: SemanticNode(
            id: SemanticNodeId('root'),
            role: SemanticRole.app,
            children: [
              SemanticNode(
                id: SemanticNodeId('unsafe'),
                role: SemanticRole.button,
                label: '<img src=x onerror=alert(1)>',
                actions: {SemanticAction.activate},
              ),
            ],
          ),
        ),
      );

      final button = root.querySelector('[data-fleury-semantic-id="unsafe"]')!;
      expect(button.getAttribute('role'), 'button');
      expect(button.textContent, '<img src=x onerror=alert(1)>');
      expect(button.querySelector('img'), isNull);
    });

    test('projects safe semantic links as anchors', () {
      final root = web.document.createElement('div');
      final presenter = SemanticDomPresenter(root: root);

      presenter.present(
        const SemanticTree(
          root: SemanticNode(
            id: SemanticNodeId('root'),
            role: SemanticRole.app,
            children: [
              SemanticNode(
                id: SemanticNodeId('docs'),
                role: SemanticRole.link,
                label: 'docs',
                value: 'https://fleury.dev',
                state: SemanticState({
                  'linkUrl': 'https://fleury.dev',
                  'safeLinkScheme': true,
                }),
              ),
            ],
          ),
        ),
      );

      final link = root.querySelector('[data-fleury-semantic-id="docs"]')!;
      expect(link.localName, 'a');
      expect(link.getAttribute('role'), 'link');
      expect(link.getAttribute('href'), 'https://fleury.dev');
      expect(link.getAttribute('target'), '_blank');
      expect(link.getAttribute('rel'), 'noopener noreferrer');
      expect(link.getAttribute('tabindex'), '-1');
      expect(link.getAttribute('data-fleury-link-url'), 'https://fleury.dev');
      expect(link.textContent, 'docs');
    });

    test('keeps unsafe semantic links non-navigating', () {
      final root = web.document.createElement('div');
      final presenter = SemanticDomPresenter(root: root);

      presenter.present(
        const SemanticTree(
          root: SemanticNode(
            id: SemanticNodeId('root'),
            role: SemanticRole.app,
            children: [
              SemanticNode(
                id: SemanticNodeId('local'),
                role: SemanticRole.link,
                label: 'local',
                value: 'myapp://open/project',
                state: SemanticState({
                  'linkUrl': 'myapp://open/project',
                  'safeLinkScheme': false,
                }),
              ),
            ],
          ),
        ),
      );

      final link = root.querySelector('[data-fleury-semantic-id="local"]')!;
      expect(link.localName, 'a');
      expect(link.getAttribute('role'), 'link');
      expect(link.getAttribute('href'), isNull);
      expect(link.getAttribute('target'), isNull);
      expect(link.getAttribute('rel'), isNull);
      expect(link.getAttribute('tabindex'), '-1');
      expect(link.getAttribute('data-fleury-link-url'), 'myapp://open/project');
    });

    test('keeps disabled safe semantic links non-navigating', () {
      final root = web.document.createElement('div');
      final presenter = SemanticDomPresenter(root: root);

      presenter.present(
        const SemanticTree(
          root: SemanticNode(
            id: SemanticNodeId('root'),
            role: SemanticRole.app,
            children: [
              SemanticNode(
                id: SemanticNodeId('docs'),
                role: SemanticRole.link,
                label: 'docs',
                value: 'https://fleury.dev',
                enabled: false,
                state: SemanticState({
                  'linkUrl': 'https://fleury.dev',
                  'safeLinkScheme': true,
                }),
              ),
            ],
          ),
        ),
      );

      final link = root.querySelector('[data-fleury-semantic-id="docs"]')!;
      expect(link.localName, 'a');
      expect(link.getAttribute('role'), 'link');
      expect(link.getAttribute('aria-disabled'), 'true');
      expect(link.getAttribute('href'), isNull);
      expect(link.getAttribute('target'), isNull);
      expect(link.getAttribute('rel'), isNull);
      expect(link.getAttribute('data-fleury-link-url'), 'https://fleury.dev');
    });

    test('does not dispatch actions from disabled semantic nodes', () {
      final root = web.document.createElement('div');
      final presenter = SemanticDomPresenter(root: root);
      final requests = <(SemanticNodeId, SemanticAction)>[];
      presenter.onSemanticActionRequest = (id, action) {
        requests.add((id, action));
      };

      presenter.present(
        const SemanticTree(
          root: SemanticNode(
            id: SemanticNodeId('root'),
            role: SemanticRole.app,
            children: [
              SemanticNode(
                id: SemanticNodeId('run'),
                role: SemanticRole.button,
                label: 'Run',
                enabled: false,
                actions: {SemanticAction.activate},
              ),
            ],
          ),
        ),
      );

      final button = root.querySelector('[data-fleury-semantic-id="run"]')!;
      expect(button.getAttribute('aria-disabled'), 'true');
      expect(button.getAttribute('data-fleury-primary-action'), 'activate');

      button.dispatchEvent(
        web.Event('click', web.EventInit(bubbles: true, cancelable: true)),
      );

      expect(requests, isEmpty);
    });

    test('disabled semantic nodes do not bubble to ancestor actions', () {
      final root = web.document.createElement('div');
      final presenter = SemanticDomPresenter(root: root);
      final requests = <(SemanticNodeId, SemanticAction)>[];
      presenter.onSemanticActionRequest = (id, action) {
        requests.add((id, action));
      };

      presenter.present(
        const SemanticTree(
          root: SemanticNode(
            id: SemanticNodeId('root'),
            role: SemanticRole.app,
            actions: {SemanticAction.activate},
            children: [
              SemanticNode(
                id: SemanticNodeId('run'),
                role: SemanticRole.button,
                label: 'Run',
                enabled: false,
                actions: {SemanticAction.activate},
              ),
            ],
          ),
        ),
      );

      final button = root.querySelector('[data-fleury-semantic-id="run"]')!;
      final event = web.Event(
        'click',
        web.EventInit(bubbles: true, cancelable: true),
      );
      button.dispatchEvent(event);

      expect(event.defaultPrevented, isTrue);
      expect(requests, isEmpty);
    });

    test('dispose clears retained action listeners and callbacks', () async {
      final root = web.document.createElement('div');
      final presenter = SemanticDomPresenter(root: root);
      final requests = <(SemanticNodeId, SemanticAction)>[];
      presenter.onSemanticActionRequest = (id, action) {
        requests.add((id, action));
      };

      presenter.present(
        const SemanticTree(
          root: SemanticNode(
            id: SemanticNodeId('root'),
            role: SemanticRole.app,
            children: [
              SemanticNode(
                id: SemanticNodeId('run'),
                role: SemanticRole.button,
                label: 'Run',
                actions: {SemanticAction.activate},
              ),
            ],
          ),
        ),
      );

      final button = root.querySelector('[data-fleury-semantic-id="run"]')!;
      await presenter.dispose();

      button.dispatchEvent(
        web.Event('click', web.EventInit(bubbles: true, cancelable: true)),
      );

      expect(root.textContent, isEmpty);
      expect(requests, isEmpty);
    });

    test('replaces the prior snapshot on each present', () {
      final root = web.document.createElement('div');
      final presenter = SemanticDomPresenter(root: root);

      presenter.present(
        const SemanticTree(
          root: SemanticNode(
            id: SemanticNodeId('root'),
            role: SemanticRole.app,
            children: [
              SemanticNode(
                id: SemanticNodeId('first'),
                role: SemanticRole.text,
                label: 'First',
                value: 'First',
              ),
            ],
          ),
        ),
      );
      expect(root.textContent, contains('First'));

      presenter.present(
        const SemanticTree(
          root: SemanticNode(
            id: SemanticNodeId('root'),
            role: SemanticRole.app,
            children: [
              SemanticNode(
                id: SemanticNodeId('second'),
                role: SemanticRole.text,
                label: 'Second',
                value: 'Second',
              ),
            ],
          ),
        ),
      );

      expect(root.querySelector('[data-fleury-semantic-id="first"]'), isNull);
      expect(root.textContent, contains('Second'));
    });

    test('skips DOM work for unchanged semantic updates', () {
      final root = web.document.createElement('div');
      final presenter = SemanticDomPresenter(root: root);
      final owner = SemanticsOwner();
      const tree = SemanticTree(
        root: SemanticNode(
          id: SemanticNodeId('root'),
          role: SemanticRole.app,
          children: [
            SemanticNode(
              id: SemanticNodeId('stable'),
              role: SemanticRole.text,
              label: 'Stable',
              value: 'Stable',
            ),
          ],
        ),
      );

      final firstStats = presenter.present(tree, update: owner.update(tree));
      final firstElement = root.firstElementChild;
      final secondStats = presenter.present(tree, update: owner.update(tree));

      expect(firstStats.createdElementCount, 2);
      expect(firstElement, isNotNull);
      expect(root.firstElementChild, same(firstElement));
      expect(secondStats.nodeCount, 2);
      expect(secondStats.addedNodeCount, 0);
      expect(secondStats.updatedNodeCount, 0);
      expect(secondStats.createdElementCount, 0);
      expect(secondStats.reusedElementCount, 0);
      expect(secondStats.attributesSetCount, 0);
      expect(secondStats.attributesRemovedCount, 0);
    });

    test('passive text roles rely on own text instead of value attributes', () {
      final root = web.document.createElement('div');
      final presenter = SemanticDomPresenter(root: root);

      presenter.present(
        const SemanticTree(
          root: SemanticNode(
            id: SemanticNodeId('root'),
            role: SemanticRole.app,
            children: [
              SemanticNode(
                id: SemanticNodeId('line'),
                role: SemanticRole.text,
                label: 'Count 0',
                value: 'Count 0',
              ),
            ],
          ),
        ),
      );

      final line = root.querySelector('[data-fleury-semantic-id="line"]')!;
      expect(line.localName, 'span');
      expect(line.textContent, 'Count 0');
      expect(line.getAttribute('role'), isNull);
      expect(line.getAttribute('aria-label'), isNull);
      expect(line.getAttribute('data-fleury-value'), isNull);
    });

    test('updates passive text without attribute churn', () {
      final root = web.document.createElement('div');
      final presenter = SemanticDomPresenter(root: root);
      final owner = SemanticsOwner();
      const firstTree = SemanticTree(
        root: SemanticNode(
          id: SemanticNodeId('root'),
          role: SemanticRole.app,
          children: [
            SemanticNode(
              id: SemanticNodeId('line'),
              role: SemanticRole.text,
              label: 'Count 0',
              value: 'Count 0',
            ),
          ],
        ),
      );
      presenter.present(firstTree, update: owner.update(firstTree));
      final line = root.querySelector('[data-fleury-semantic-id="line"]')!;
      final textNode = line.firstChild;
      expect(textNode, isNotNull);

      const secondTree = SemanticTree(
        root: SemanticNode(
          id: SemanticNodeId('root'),
          role: SemanticRole.app,
          children: [
            SemanticNode(
              id: SemanticNodeId('line'),
              role: SemanticRole.text,
              label: 'Count 1',
              value: 'Count 1',
            ),
          ],
        ),
      );
      final stats = presenter.present(
        secondTree,
        update: owner.update(secondTree),
      );

      final retained = root.querySelector('[data-fleury-semantic-id="line"]')!;
      expect(retained, same(line));
      expect(retained.firstChild, same(textNode));
      expect(retained.textContent, 'Count 1');
      expect(retained.getAttribute('aria-label'), isNull);
      expect(retained.getAttribute('data-fleury-value'), isNull);
      expect(stats.updatedNodeCount, 1);
      expect(stats.createdElementCount, 0);
      expect(stats.reusedElementCount, 1);
      expect(stats.attributesSetCount, 0);
      expect(stats.attributesRemovedCount, 0);
    });

    test('updates changed leaf semantics without rebuilding the tree', () {
      final root = web.document.createElement('div');
      final presenter = SemanticDomPresenter(root: root);
      final owner = SemanticsOwner();
      const firstTree = SemanticTree(
        root: SemanticNode(
          id: SemanticNodeId('root'),
          role: SemanticRole.app,
          children: [
            SemanticNode(
              id: SemanticNodeId('stable'),
              role: SemanticRole.text,
              label: 'Stable',
              value: 'Stable',
            ),
            SemanticNode(
              id: SemanticNodeId('counter'),
              role: SemanticRole.text,
              label: 'Count 0',
              value: 'Count 0',
            ),
          ],
        ),
      );
      final firstStats = presenter.present(
        firstTree,
        update: owner.update(firstTree),
      );
      final semanticRoot = root.firstElementChild;
      final stable = root.querySelector('[data-fleury-semantic-id="stable"]');
      final counter = root.querySelector('[data-fleury-semantic-id="counter"]');

      final secondTree = SemanticTree(
        root: SemanticNode(
          id: const SemanticNodeId('root'),
          role: SemanticRole.app,
          children: [
            const SemanticNode(
              id: SemanticNodeId('stable'),
              role: SemanticRole.text,
              label: 'Stable',
              value: 'Stable',
            ),
            SemanticNode(
              id: const SemanticNodeId('counter'),
              role: SemanticRole.text,
              label: 'Count 1',
              value: 'Count 1',
              bounds: CellRect.fromLTWH(3, 4, 7, 1),
            ),
          ],
        ),
      );
      final secondStats = presenter.present(
        secondTree,
        update: owner.update(secondTree),
      );

      final retainedCounter = root.querySelector(
        '[data-fleury-semantic-id="counter"]',
      )!;
      expect(firstStats.createdElementCount, 3);
      expect(root.firstElementChild, same(semanticRoot));
      expect(
        root.querySelector('[data-fleury-semantic-id="stable"]'),
        same(stable),
      );
      expect(retainedCounter, same(counter));
      expect(retainedCounter.textContent, 'Count 1');
      expect(retainedCounter.getAttribute('data-fleury-bounds-left'), '3');
      expect(retainedCounter.getAttribute('data-fleury-bounds-top'), '4');
      expect(secondStats.nodeCount, 3);
      expect(secondStats.addedNodeCount, 0);
      expect(secondStats.removedNodeCount, 0);
      expect(secondStats.updatedNodeCount, 1);
      expect(secondStats.createdElementCount, 0);
      expect(secondStats.replacedElementCount, 0);
      expect(secondStats.reusedElementCount, 1);
      expect(secondStats.attributesSetCount, 4);
      expect(retainedCounter.getAttribute('aria-label'), isNull);
      expect(retainedCounter.getAttribute('data-fleury-value'), isNull);
    });

    test('falls back to full rebuild for structural semantic changes', () {
      final root = web.document.createElement('div');
      final presenter = SemanticDomPresenter(root: root);
      final owner = SemanticsOwner();
      const firstTree = SemanticTree(
        root: SemanticNode(
          id: SemanticNodeId('root'),
          role: SemanticRole.app,
          children: [
            SemanticNode(
              id: SemanticNodeId('first'),
              role: SemanticRole.text,
              label: 'First',
              value: 'First',
            ),
            SemanticNode(
              id: SemanticNodeId('second'),
              role: SemanticRole.text,
              label: 'Second',
              value: 'Second',
            ),
          ],
        ),
      );
      presenter.present(firstTree, update: owner.update(firstTree));
      final first = root.querySelector('[data-fleury-semantic-id="first"]');
      final second = root.querySelector('[data-fleury-semantic-id="second"]');

      const secondTree = SemanticTree(
        root: SemanticNode(
          id: SemanticNodeId('root'),
          role: SemanticRole.app,
          children: [
            SemanticNode(
              id: SemanticNodeId('second'),
              role: SemanticRole.text,
              label: 'Second',
              value: 'Second',
            ),
            SemanticNode(
              id: SemanticNodeId('first'),
              role: SemanticRole.text,
              label: 'First',
              value: 'First',
            ),
          ],
        ),
      );
      final stats = presenter.present(
        secondTree,
        update: owner.update(secondTree),
      );
      final semanticRoot = root.querySelector(
        '[data-fleury-semantic-id="root"]',
      )!;

      expect(stats.updatedNodeCount, 1);
      expect(stats.reusedElementCount, 3);
      expect(
        root.querySelector('[data-fleury-semantic-id="first"]'),
        same(first),
      );
      expect(
        root.querySelector('[data-fleury-semantic-id="second"]'),
        same(second),
      );
      expect(semanticRoot.textContent, 'SecondFirst');
    });

    test('retains same-id elements and removes stale attributes', () {
      final root = web.document.createElement('div');
      final presenter = SemanticDomPresenter(root: root);

      presenter.present(
        SemanticTree(
          root: SemanticNode(
            id: const SemanticNodeId('root'),
            role: SemanticRole.app,
            children: [
              SemanticNode(
                id: const SemanticNodeId('save'),
                role: SemanticRole.button,
                label: 'Save',
                selected: true,
                busy: true,
                bounds: CellRect.fromLTWH(1, 2, 3, 1),
                actions: const {SemanticAction.activate},
              ),
            ],
          ),
        ),
      );

      final save = root.querySelector('[data-fleury-semantic-id="save"]')!;
      expect(save.getAttribute('aria-busy'), 'true');
      expect(save.getAttribute('aria-selected'), 'true');
      expect(save.getAttribute('data-fleury-actions'), 'activate');
      expect(save.getAttribute('data-fleury-bounds-left'), '1');

      presenter.present(
        const SemanticTree(
          root: SemanticNode(
            id: SemanticNodeId('root'),
            role: SemanticRole.app,
            children: [
              SemanticNode(
                id: SemanticNodeId('save'),
                role: SemanticRole.button,
                label: 'Run',
              ),
            ],
          ),
        ),
      );

      final retained = root.querySelector('[data-fleury-semantic-id="save"]')!;
      expect(retained, same(save));
      expect(retained.textContent, 'Run');
      expect(retained.getAttribute('aria-busy'), isNull);
      expect(retained.getAttribute('aria-selected'), isNull);
      expect(retained.getAttribute('data-fleury-actions'), isNull);
      expect(retained.getAttribute('data-fleury-bounds-left'), isNull);
      expect(retained.getAttribute('tabindex'), isNull);
    });

    test('replaces same-id elements when the required tag changes', () {
      final root = web.document.createElement('div');
      final presenter = SemanticDomPresenter(root: root);

      presenter.present(
        const SemanticTree(
          root: SemanticNode(
            id: SemanticNodeId('root'),
            role: SemanticRole.app,
            children: [
              SemanticNode(
                id: SemanticNodeId('target'),
                role: SemanticRole.textField,
                label: 'Command',
                value: 'deploy',
              ),
            ],
          ),
        ),
      );
      final field = root.querySelector('[data-fleury-semantic-id="target"]')!;
      expect(field.localName, 'input');

      presenter.present(
        const SemanticTree(
          root: SemanticNode(
            id: SemanticNodeId('root'),
            role: SemanticRole.app,
            children: [
              SemanticNode(
                id: SemanticNodeId('target'),
                role: SemanticRole.button,
                label: 'Run',
              ),
            ],
          ),
        ),
      );

      final button = root.querySelector('[data-fleury-semantic-id="target"]')!;
      expect(button.localName, 'div');
      expect(button, isNot(same(field)));
    });
  });
}
