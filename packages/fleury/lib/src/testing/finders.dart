// Finders: queries that walk the Element tree and return matching
// elements. Modelled on `flutter_test`'s `Finder` / `find.*` API.
//
// Usage:
//
//     final inputs = tester.find(byType(TextInput));
//     expect(inputs, hasLength(1));
//
//     final card = tester.findOne(byKey(const ValueKey('user-card')));
//
//     final matchingText = tester.find(text('Save'));
//
// Finders are pure descriptions — they do not retain state between
// applications. Apply via `tester.find(finder)` or
// `tester.findOne(finder)`; the tester walks its root element with
// the finder and returns the results.

import '../foundation/key.dart';
import '../widgets/basic.dart';
import '../widgets/framework.dart';

/// A query over an [Element] tree. Implementations walk the subtree
/// rooted at [apply]'s argument and yield matching elements.
///
/// Finders are stateless and reusable.
abstract class Finder {
  const Finder();

  /// Yields every element in the subtree rooted at [root] that
  /// matches this finder, in pre-order (parent before children).
  Iterable<Element> apply(Element root);

  /// Human-readable label used in test failure messages.
  String describe();

  @override
  String toString() => describe();
}

class _TypeFinder extends Finder {
  const _TypeFinder(this.type);
  final Type type;

  @override
  Iterable<Element> apply(Element root) sync* {
    yield* _walk(root).where((e) => e.widget.runtimeType == type);
  }

  @override
  String describe() => 'byType($type)';
}

class _KeyFinder extends Finder {
  const _KeyFinder(this.key);
  final Key key;

  @override
  Iterable<Element> apply(Element root) sync* {
    yield* _walk(root).where((e) => e.widget.key == key);
  }

  @override
  String describe() => 'byKey($key)';
}

class _TextFinder extends Finder {
  const _TextFinder(this.data);
  final String data;

  @override
  Iterable<Element> apply(Element root) sync* {
    for (final e in _walk(root)) {
      final widget = e.widget;
      if (widget is Text && widget.data == data) yield e;
    }
  }

  @override
  String describe() => 'text(${_quote(data)})';
}

class _PredicateFinder extends Finder {
  const _PredicateFinder(this._predicate, [this._description]);
  final bool Function(Widget widget) _predicate;
  final String? _description;

  @override
  Iterable<Element> apply(Element root) sync* {
    yield* _walk(root).where((e) => _predicate(e.widget));
  }

  @override
  String describe() => _description ?? 'byPredicate(<closure>)';
}

class _DescendantFinder extends Finder {
  const _DescendantFinder({required this.of, required this.matching});
  final Finder of;
  final Finder matching;

  @override
  Iterable<Element> apply(Element root) sync* {
    for (final ancestor in of.apply(root)) {
      // visitChildren takes a callback, so we can't `yield` directly
      // from inside it (yield is bound to the outer sync* function).
      // Materialize into a list and yield* it.
      final hits = <Element>[];
      ancestor.visitChildren((child) {
        hits.addAll(matching.apply(child));
      });
      yield* hits;
    }
  }

  @override
  String describe() =>
      '${matching.describe()} descendantOf '
      '${of.describe()}';
}

/// Yields [root] then every transitive descendant in pre-order.
Iterable<Element> _walk(Element root) sync* {
  yield root;
  final queue = <Element>[];
  root.visitChildren(queue.add);
  while (queue.isNotEmpty) {
    final next = queue.removeAt(0);
    yield next;
    next.visitChildren(queue.add);
  }
}

String _quote(String s) =>
    "'${s.replaceAll(r'\', r'\\').replaceAll("'", r"\'")}'";

/// Matches elements whose widget [runtimeType] equals [type].
///
/// `byType(TextInput)` matches every `TextInput` widget in the tree
/// — including duplicates. Use [byKey] when there are multiple
/// instances and you want a specific one.
Finder byType(Type type) => _TypeFinder(type);

/// Matches elements whose widget carries [key].
Finder byKey(Key key) => _KeyFinder(key);

/// Matches [Text] widgets whose `data` equals [data].
Finder text(String data) => _TextFinder(data);

/// Matches any element whose widget satisfies [predicate].
/// [description] is shown in test failure messages.
Finder byPredicate(
  bool Function(Widget widget) predicate, {
  String? description,
}) => _PredicateFinder(predicate, description);

/// Matches elements yielded by [matching] when they appear in the
/// subtree of an element matched by [of].
///
///     find(descendantOf(of: byKey(card), matching: byType(TextInput)));
Finder descendantOf({required Finder of, required Finder matching}) =>
    _DescendantFinder(of: of, matching: matching);
