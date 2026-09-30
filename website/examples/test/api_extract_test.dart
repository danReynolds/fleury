@TestOn('vm')
library;

import 'dart:io';

import '../bin/api_extract.dart';
import 'package:test/test.dart';

void main() {
  group('extractApiFromSource', () {
    test(
      'extracts every public constructor and constructor parameter shape',
      () {
        final api = extractApiFromSource(
          _constructorFixture,
          file: 'fixture.dart',
        );
        final entry = api['Example']! as Map<String, Object?>;
        final constructors =
            entry['constructors']! as List<Map<String, Object?>>;

        expect(constructors.map((constructor) => constructor['name']), [
          'Example',
          'Example.named',
        ]);
        expect(constructors.map((constructor) => constructor['line']), [
          15,
          28,
        ]);
        expect(constructors.first['doc'], 'Creates the primary example.');
        expect(constructors.last['doc'], 'Creates a named example.');

        final primaryParams =
            constructors.first['params']! as List<Map<String, Object?>>;
        expect(primaryParams, [
          {
            'name': 'child',
            'type': 'String',
            'required': true,
            'named': true,
            'default': null,
            'doc': 'Describes the inherited child.',
          },
          {
            'name': 'direct',
            'type': 'int',
            'required': true,
            'named': true,
            'default': null,
            'doc': 'The constructor-specific direct value.',
          },
          {
            'name': 'simple',
            'type': 'String',
            'required': false,
            'named': true,
            'default': "'default'",
            'doc': 'Stored after construction.',
          },
        ]);
        expect(
          primaryParams.map((parameter) => parameter['name']),
          isNot(contains('key')),
        );

        final namedParams =
            constructors.last['params']! as List<Map<String, Object?>>;
        expect(namedParams.single['name'], 'positional');
        expect(namedParams.single['named'], isFalse);
        expect(namedParams.single['doc'], 'Documents the positional value.');

        // The compatibility view continues to select the unnamed constructor.
        expect(entry['params'], primaryParams);
      },
    );

    test('records class coverage metadata', () {
      final api = extractApiFromSource(
        _constructorFixture,
        file: 'fixture.dart',
      );
      final entry = api['Example']! as Map<String, Object?>;
      final base = api['Base']! as Map<String, Object?>;

      expect(entry['abstract'], isTrue);
      expect(entry['extends'], 'Base');
      expect(entry['file'], 'fixture.dart');
      expect(base['abstract'], isFalse);
      expect(base['extends'], 'Widget');
    });

    test(
      'omits widget identity keys but preserves domain parameters named key',
      () {
        final api = extractApiFromSource(_keyFixture, file: 'fixture.dart');
        final base = api['BaseWidget']! as Map<String, Object?>;
        final widget = api['ExampleWidget']! as Map<String, Object?>;
        final action = api['ToastAction']! as Map<String, Object?>;
        final inheritedAction =
            api['InheritedToastAction']! as Map<String, Object?>;

        expect(base['params'], isEmpty, reason: 'Key? is framework identity');
        expect(
          widget['params'],
          isEmpty,
          reason: 'super.key is framework identity',
        );
        expect(action['params'], [
          {
            'name': 'key',
            'type': 'KeySequence',
            'required': true,
            'named': true,
            'default': null,
            'doc': 'The hotkey that invokes the action.',
          },
        ]);
        expect(inheritedAction['params'], [
          {
            'name': 'key',
            'type': 'KeySequence',
            'required': true,
            'named': true,
            'default': null,
            'doc': 'The inherited hotkey.',
          },
        ]);
      },
    );

    test('resolves inherited super-formal types and preserves defaults', () {
      final api = extractApiFromSource(
        _superFormalFixture,
        file: 'fixture.dart',
      );
      final child = api['ChildBox']! as Map<String, Object?>;
      final children = api['ChildrenBox']! as Map<String, Object?>;

      expect(child['params'], [
        {
          'name': 'child',
          'type': 'Widget?',
          'required': false,
          'named': true,
          'default': null,
          'doc': 'Optional content.',
        },
      ]);
      expect(children['params'], [
        {
          'name': 'children',
          'type': 'List<Widget>',
          'required': false,
          'named': true,
          'default': 'const <Widget>[]',
          'doc': 'Ordered content.',
        },
      ]);
    });

    test('super parameters take their type and doc from the super '
        'constructor parameter they forward to', () {
      final api = extractApiFromSource(
        _superConstructorFixture,
        file: 'fixture.dart',
      );
      Map<String, Object?> param(String className, String name) =>
          ((api[className]! as Map<String, Object?>)['params']! as List)
              .cast<Map<String, Object?>>()
              .singleWhere((param) => param['name'] == name);

      // The field is nullable for the whole hierarchy; the constructor that
      // `Expanded` forwards to requires a non-null child.
      expect(param('Flexible', 'child')['type'], 'Widget');
      expect(param('Expanded', 'child'), {
        'name': 'child',
        'type': 'Widget',
        'required': true,
        'named': true,
        'default': null,
        'doc': 'Content laid out within the flex allocation.',
      });
      // Through two hops, and to the named constructor actually invoked.
      expect(param('TightExpanded', 'child')['type'], 'Widget');
      expect(param('Named', 'label')['type'], 'String');
      expect(param('Named', 'label')['doc'], 'The label the named form shows.');
      // A required super parameter never reports the optional default of the
      // parameter it forwards to.
      expect(param('Required', 'flex')['default'], isNull);
      expect(param('Expanded', 'flex')['default'], '1');
      // Positional super parameters forward in order among themselves, not by
      // their index among all positionals.
      expect(param('LabeledPair', 'first')['type'], 'int');
      expect(param('LabeledPair', 'first')['doc'], 'The first value.');
      expect(param('LabeledPair', 'second')['type'], 'String');
    });

    test('keeps every paragraph of constructor and parameter docs', () {
      final api = extractApiFromSource(_paragraphFixture, file: 'fixture.dart');
      final entry = api['Paragraphs']! as Map<String, Object?>;
      final constructor =
          (entry['constructors']! as List<Map<String, Object?>>).single;
      final params = (constructor['params']! as List)
          .cast<Map<String, Object?>>();

      expect(entry['doc'], 'Summary on one line.');
      expect(
        constructor['doc'],
        'Creates the example.\n\nSeparators hold no index of their own.',
      );
      expect(
        params.first['doc'],
        '''
Stable identity for `items`.

Supply this when items can move:

- keys must be unique
- keys must be stable'''
            .trim(),
      );
      expect(params.last['doc'], 'Own doc, first line\ncontinued.');
    });

    test('drops field-doc sentences about other constructors', () {
      final api = extractApiFromSource(
        _constructorDocsFixture,
        file: 'fixture.dart',
      );
      final constructors =
          ((api['Lister']! as Map<String, Object?>)['constructors']! as List)
              .cast<Map<String, Object?>>();
      String? doc(String constructor, String param) =>
          (constructors.singleWhere((c) => c['name'] == constructor)['params']
                      as List)
                  .cast<Map<String, Object?>>()
                  .singleWhere((p) => p['name'] == param)['doc']
              as String?;

      expect(doc('Lister', 'children'), 'Pre-built rows (eager form).');
      expect(doc('Lister.builder', 'itemCount'), 'Number of rows (lazy form).');
      expect(
        doc('Lister.separated', 'separatorBuilder'),
        'Builds the gap after row `i` (`Lister.separated` form).',
      );
      expect(
        doc('Lister.builder', 'document'),
        'An already parsed document.',
        reason: 'a `;` clause about another constructor goes too',
      );
      // A sentence that also names this constructor describes it, and a doc
      // with nothing to drop keeps its original lines.
      expect(
        doc('Lister.builder', 'color'),
        'Fill color. `Lister.builder` and `Lister.separated` fill with the\n'
        'surface instead.',
      );
      expect(doc('Lister', 'color'), 'Fill color.');
      // A parameter's own doc is constructor-specific already.
      expect(
        doc('Lister.separated', 'itemCount'),
        'Rows between separators. Unlike `children`, this counts rows.',
      );
      // Lists and other structure are left as written.
      expect(doc('Lister', 'notes'), contains('- also `itemCount`'));
    });

    test('super parameters without a default inherit the superclass one', () {
      final api = extractApiFromSource(
        _inheritedDefaultFixture,
        file: 'fixture.dart',
      );
      Object? defaultOf(String className, String name) =>
          ((api[className]! as Map<String, Object?>)['params']! as List)
              .cast<Map<String, Object?>>()
              .singleWhere((param) => param['name'] == name)['default'];

      expect(defaultOf('Line', 'size'), 'Size.max');
      expect(defaultOf('Line', 'align'), "'start'");
      expect(defaultOf('HorizontalLine', 'size'), 'Size.max');
      expect(defaultOf('Tight', 'flex'), '1');
      expect(defaultOf('Explicit', 'size'), 'Size.min');
      expect(defaultOf('Required', 'child'), isNull);
    });

    test('keeps parameterless and implicit public constructors', () {
      final api = extractApiFromSource(
        _visibilityFixture,
        file: 'fixture.dart',
      );

      expect(_constructorNames(api['Explicit']! as Map<String, Object?>), [
        'Explicit',
      ]);
      expect((api['Explicit']! as Map<String, Object?>)['params'], isEmpty);
      expect(_constructorNames(api['Implicit']! as Map<String, Object?>), [
        'Implicit',
      ]);
    });

    test('normalizes Dartdoc references only outside Markdown code', () {
      final api = extractApiFromSource(_markdownFixture, file: 'fixture.dart');
      final entry = api['Documented']! as Map<String, Object?>;

      expect(
        entry['classDoc'],
        r'''Renders `Widget` values such as `[x]` and `values[row][col]`.

```dart
final item = values[row][col];
final type = [Widget];
```''',
      );
      final parameter = (entry['params']! as List<Map<String, Object?>>).single;
      expect(parameter['doc'], 'Reads `values[row][col]`; see `Widget.build`.');
    });

    test('recognizes CommonMark fenced code boundaries', () {
      final api = extractApiFromSource(
        _markdownFenceFixture,
        file: 'fixture.dart',
      );
      final entry = api['FencedDocumented']! as Map<String, Object?>;

      expect(entry['classDoc'], r'''Before `Widget`.

```dart
final marker = '```';
final type = [Widget.build];
````

~~~dart
final type = [Widget];
~~~~

After `Widget.build`.''');
    });

    test('omits private classes and private constructors', () {
      final api = extractApiFromSource(
        _visibilityFixture,
        file: 'fixture.dart',
      );

      expect(api, isNot(contains('_PrivateClass')));
      expect(api, contains('PrivateOnly'));
      expect(
        (api['PrivateOnly']! as Map<String, Object?>)['constructors'],
        isEmpty,
      );
      expect((api['PrivateOnly']! as Map<String, Object?>)['params'], isEmpty);
    });
  });

  test('findApiSourceFiles scans nested sources with repository paths', () {
    final root = Directory.systemTemp.createTempSync('fleury_api_extract_');
    addTearDown(() => root.deleteSync(recursive: true));
    final nested = Directory('${root.path}/selection')..createSync();
    File('${root.path}/top.dart').writeAsStringSync('class Top {}');
    File(
      '${nested.path}/selectable.dart',
    ).writeAsStringSync('class Selectable {}');
    File('${nested.path}/notes.txt').writeAsStringSync('not Dart');

    final sources = findApiSourceFiles(root, 'packages/fleury/lib/src/widgets');

    expect(sources.map((source) => source.$2), [
      'packages/fleury/lib/src/widgets/selection/selectable.dart',
      'packages/fleury/lib/src/widgets/top.dart',
    ]);
  });
}

List<Object?> _constructorNames(Map<String, Object?> entry) =>
    (entry['constructors']! as List<Map<String, Object?>>)
        .map((constructor) => constructor['name'])
        .toList();

const _constructorFixture = r'''
class Widget { const Widget({this.key}); final Key? key; }

class Base extends Widget {
  Base({super.key, required this.child});

  final String child;
}

/// A documented example.
abstract class Example extends Base {
  /// The field-level direct value.
  final int direct;

  /// Creates the primary example.
  Example({
    super.key,
    /// Describes the inherited child.
    required String super.child,
    /// The constructor-specific direct value.
    required this.direct,
    String simple = 'default',
  }) : this.simple = simple;

  /// Stored after construction.
  final String simple;

  /// Creates a named example.
  Example.named(
    /// Documents the positional value.
    String positional,
  ) : direct = 0,
      simple = positional,
      super(child: positional);

  Example._private()
    : direct = 0,
      simple = '',
      super(child: '');
}
''';

const _visibilityFixture = r'''
class Explicit {
  const Explicit();
}

class Implicit {}

class PrivateOnly {
  PrivateOnly._();
}

class _PrivateClass {
  _PrivateClass();
}
''';

const _keyFixture = r'''
class Widget {
  const Widget({this.key});

  final Key? key;
}

class BaseWidget extends Widget {
  const BaseWidget({super.key});
}

class ExampleWidget extends BaseWidget {
  const ExampleWidget({super.key});
}

class ToastAction {
  const ToastAction({required this.key});

  /// The hotkey that invokes the action.
  final KeySequence key;
}

class InheritedToastAction extends ToastAction {
  const InheritedToastAction({
    /// The inherited hotkey.
    required super.key,
  });
}
''';

const _superFormalFixture = r'''
class Widget {}

class SingleChildWidget extends Widget {
  const SingleChildWidget({this.child});

  final Widget? child;
}

class MultiChildWidget extends Widget {
  const MultiChildWidget({this.children = const <Widget>[]});

  final List<Widget> children;
}

class ChildBox extends SingleChildWidget {
  const ChildBox({
    /// Optional content.
    super.child,
  });
}

class ChildrenBox extends MultiChildWidget {
  const ChildrenBox({
    /// Ordered content.
    super.children = const <Widget>[],
  });
}
''';

const _superConstructorFixture = r'''
class Widget {}

class SingleChildRenderObjectWidget extends Widget {
  const SingleChildRenderObjectWidget({this.child});

  /// The widget below this widget in the tree.
  final Widget? child;
}

class Flexible extends SingleChildRenderObjectWidget {
  const Flexible({
    this.flex = 1,

    /// Content laid out within the flex allocation.
    required Widget super.child,
  });

  final int flex;
}

class Expanded extends Flexible {
  const Expanded({super.flex, required super.child});
}

class TightExpanded extends Expanded {
  const TightExpanded({required super.child});
}

class Required extends Flexible {
  const Required({required super.flex, required super.child});
}

class Labelled {
  const Labelled({this.label});

  const Labelled.named({
    /// The label the named form shows.
    required String this.label,
  });

  /// Optional label.
  final String? label;
}

class Named extends Labelled {
  const Named({required super.label}) : super.named();
}

class Pair {
  const Pair(
    /// The first value.
    this.first,

    /// The second value.
    this.second,
  );

  final int first;
  final String second;
}

class LabeledPair extends Pair {
  const LabeledPair(this.label, super.first, super.second);

  final String label;
}
''';

const _paragraphFixture = r'''
/// Summary on one line.
///
/// More detail.
class Paragraphs {
  /// Creates the example.
  ///
  /// Separators hold no index of their own.
  const Paragraphs({
    this.keyBuilder,
    /// Own doc, first line
    /// continued.
    this.flag = false,
  });

  /// Stable identity for [items].
  ///
  /// Supply this when items can move:
  ///
  /// - keys must be unique
  /// - keys must be stable
  final Object? keyBuilder;

  /// Documented on the field.
  final bool flag;
}
''';

const _constructorDocsFixture = r'''
class Lister {
  const Lister({required this.children, this.color, this.notes})
    : itemCount = null,
      separatorBuilder = null,
      document = null;

  const Lister.builder({
    required int this.itemCount,
    this.color,
    this.document,
  }) : children = null,
       separatorBuilder = null,
       notes = null;

  const Lister.separated({
    /// Rows between separators. Unlike [children], this counts rows.
    required int this.itemCount,
    required Object this.separatorBuilder,
    this.color,
  }) : children = null,
       document = null,
       notes = null;

  /// Pre-built rows (eager form). Mutually exclusive with [itemCount] /
  /// [separatorBuilder].
  final List<Object>? children;

  /// Number of rows (lazy form). Mutually exclusive with [children].
  final int? itemCount;

  /// Builds the gap after row `i` ([Lister.separated] form). Null for the
  /// eager and [Lister.builder] forms.
  final Object? separatorBuilder;

  /// An already parsed document; null for [Lister.new].
  final Object? document;

  /// Fill color. [Lister.builder] and [Lister.separated] fill with the
  /// surface instead.
  final Object? color;

  /// Notes about the eager form:
  ///
  /// - also [itemCount]
  final Object? notes;
}
''';

const _inheritedDefaultFixture = r'''
enum Size { min, max }

class Base {
  const Base({
    this.size = Size.max,
    this.align = 'start',
    this.flex = 1,
    this.child,
  });

  final Size size;
  final String align;
  final int flex;
  final Object? child;
}

class Line extends Base {
  const Line({super.size, super.align});
}

class HorizontalLine extends Line {
  const HorizontalLine({super.size});
}

class Tight extends Base {
  const Tight({super.flex}) : super(size: Size.min);
}

class Explicit extends Base {
  const Explicit({super.size = Size.min});
}

class Required extends Base {
  const Required({required super.child});
}
''';

const _markdownFixture = r'''
/// Renders [Widget] values such as `[x]` and `values[row][col]`.
///
/// ```dart
/// final item = values[row][col];
/// final type = [Widget];
/// ```
class Documented {
  const Documented({required this.value});

  /// Reads `values[row][col]`; see [Widget.build].
  final String value;
}
''';

const _markdownFenceFixture = r'''
/// Before [Widget].
///
/// ```dart
/// final marker = '```';
/// final type = [Widget.build];
/// ````
///
/// ~~~dart
/// final type = [Widget];
/// ~~~~
///
/// After [Widget.build].
class FencedDocumented {}
''';
