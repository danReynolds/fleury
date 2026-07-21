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
